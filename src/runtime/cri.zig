const std = @import("std");
const interface = @import("interface.zig");
const types = @import("types");
const proxmox = @import("proxmox");
const cni = @import("network/cni.zig");
const hooks = @import("hooks.zig");
const pod = @import("pod.zig");
const Allocator = std.mem.Allocator;

/// CRI-сумісний runtime для Proxmox LXC
pub const CRIRuntime = struct {
    interface: interface.RuntimeInterface,
    pods: std.StringHashMap(*pod.Pod),
    containers: std.StringHashMap(Container),
    proxmox_client: *proxmox.Client,
    cni_plugin: *cni.CNIPlugin,
    hooks_manager: *hooks.HooksManager,
    
    const Self = @This();

    /// Структура контейнера для CRI
    const Container = struct {
        id: []const u8,
        name: []const u8,
        pod_id: []const u8,
        state: interface.RuntimeInterface.State,
        resources: ?types.Resources,
        network: ?types.NetworkConfig,
        
        fn init(allocator: Allocator, id: []const u8, name: []const u8, pod_id: []const u8) !Container {
            return Container{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .pod_id = try allocator.dupe(u8, pod_id),
                .state = .created,
                .resources = null,
                .network = null,
            };
        }

        fn deinit(self: *Container, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            allocator.free(self.pod_id);
            if (self.network) |network| {
                network.deinit(allocator);
            }
        }
    };

    /// Створює новий CRI runtime
    pub fn init(
        allocator: Allocator,
        proxmox_client: *proxmox.Client,
        root_dir: []const u8,
        state_dir: []const u8,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.pods = std.StringHashMap(*pod.Pod).init(allocator);
        self.containers = std.StringHashMap(Container).init(allocator);
        self.proxmox_client = proxmox_client;
        
        // Ініціалізуємо CNI плагін
        self.cni_plugin = try cni.CNIPlugin.init(allocator, root_dir);
        errdefer self.cni_plugin.deinit();
        
        // Ініціалізуємо менеджер хуків
        self.hooks_manager = try hooks.HooksManager.init(allocator);
        errdefer self.hooks_manager.deinit();

        const config = interface.RuntimeInterface.Config{
            .runtime_type = .cri,
            .root_dir = root_dir,
            .state_dir = state_dir,
            .network_plugin = "cni",
        };

        const lifecycle = interface.RuntimeInterface.Lifecycle{
            .createFn = create,
            .startFn = start,
            .stopFn = stop,
            .deleteFn = delete,
            .stateFn = state,
        };

        const resources = interface.RuntimeInterface.Resources{
            .updateFn = updateResources,
            .statsFn = stats,
        };
        
        const network = interface.RuntimeInterface.Network{
            .setupFn = setupNetwork,
            .teardownFn = teardownNetwork,
            .statsFn = networkStats,
        };
        
        const hooks_interface = interface.RuntimeInterface.Hooks{
            .prestartFn = prestart,
            .poststartFn = poststart,
            .poststopFn = poststop,
        };
        
        const pod_interface = interface.RuntimeInterface.Pod{
            .createFn = createPod,
            .deleteFn = deletePod,
            .startFn = startPod,
            .stopFn = stopPod,
            .stateFn = podState,
        };

        self.interface = interface.RuntimeInterface.init(
            allocator,
            config,
            lifecycle,
            resources,
            network,
            hooks_interface,
            pod_interface,
        );

        return self;
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var pod_it = self.pods.iterator();
        while (pod_it.next()) |entry| {
            entry.value_ptr.*.deinit(self.interface.allocator);
        }
        self.pods.deinit();
        
        var container_it = self.containers.iterator();
        while (container_it.next()) |entry| {
            var container = entry.value_ptr;
            container.deinit(self.interface.allocator);
        }
        self.containers.deinit();
        
        self.cni_plugin.deinit();
        self.hooks_manager.deinit();
        self.interface.allocator.destroy(self);
    }

    /// Створює новий Pod
    fn createPod(rt: *interface.RuntimeInterface, config: types.PodConfig) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        // Створюємо новий Pod
        const new_pod = try pod.Pod.init(
            rt.allocator,
            config.id,
            config.name,
            config.namespace,
        );
        errdefer new_pod.deinit(rt.allocator);
        
        // Додаємо анотації
        if (config.annotations) |annotations| {
            var it = annotations.iterator();
            while (it.next()) |entry| {
                try new_pod.setAnnotation(rt.allocator, entry.key_ptr.*, entry.value_ptr.*);
            }
        }
        
        try self.pods.put(config.id, new_pod);
    }
    
    /// Видаляє Pod
    fn deletePod(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.pods.fetchRemove(id)) |entry| {
            const pod_ptr = entry.value;
            
            // Видаляємо всі контейнери Pod-а
            var it = pod_ptr.containers.iterator();
            while (it.next()) |container_entry| {
                const container_id = container_entry.key_ptr.*;
                try self.delete(rt, container_id);
            }
            
            // Видаляємо Pod
            pod_ptr.deinit(rt.allocator);
        } else {
            return error.NotFound;
        }
    }
    
    /// Запускає Pod
    fn startPod(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.pods.getPtr(id)) |pod_ptr| {
            // Запускаємо всі контейнери Pod-а
            var it = pod_ptr.containers.iterator();
            while (it.next()) |container_entry| {
                const container_id = container_entry.key_ptr.*;
                try self.start(rt, container_id);
            }
            
            pod_ptr.updateState();
        } else {
            return error.NotFound;
        }
    }
    
    /// Зупиняє Pod
    fn stopPod(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.pods.getPtr(id)) |pod_ptr| {
            // Зупиняємо всі контейнери Pod-а
            var it = pod_ptr.containers.iterator();
            while (it.next()) |container_entry| {
                const container_id = container_entry.key_ptr.*;
                try self.stop(rt, container_id);
            }
            
            pod_ptr.updateState();
        } else {
            return error.NotFound;
        }
    }
    
    /// Отримує стан Pod-а
    fn podState(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!pod.Pod.State {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.pods.getPtr(id)) |pod_ptr| {
            return pod_ptr.state;
        } else {
            return error.NotFound;
        }
    }

    /// Створює новий контейнер
    fn create(rt: *interface.RuntimeInterface, config: types.ContainerConfig) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        // Створюємо контейнер в Proxmox
        try self.proxmox_client.createContainer(.{
            .vmid = config.id,
            .hostname = config.hostname,
            .rootfs = config.root_path,
            .memory = if (config.resources) |res| res.memory.limit else 512 * 1024 * 1024,
            .swap = if (config.resources) |res| res.memory.swap else 1024 * 1024 * 1024,
            .cores = if (config.resources) |res| res.cpu.shares else 1,
        }) catch |err| {
            return switch (err) {
                error.ProxmoxError => error.CreationError,
                else => error.CreationError,
            };
        };

        // Створюємо локальний запис про контейнер
        var container = try Container.init(
            rt.allocator,
            config.id,
            config.name,
            config.pod_id orelse "default",
        );
        container.resources = config.resources;

        try self.containers.put(config.id, container);
    }

    /// Запускає контейнер
    fn start(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.proxmox_client.startContainer(id) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.StartError,
                    else => error.StartError,
                };
            };
            container.state = .running;
        } else {
            return error.NotFound;
        }
    }

    /// Зупиняє контейнер
    fn stop(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.proxmox_client.stopContainer(id) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.StopError,
                    else => error.StopError,
                };
            };
            container.state = .stopped;
        } else {
            return error.NotFound;
        }
    }

    /// Видаляє контейнер
    fn delete(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.proxmox_client.deleteContainer(id) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.DeleteError,
                    else => error.DeleteError,
                };
            };
            
            var container_mut = container;
            container_mut.deinit(rt.allocator);
            _ = self.containers.remove(id);
        } else {
            return error.NotFound;
        }
    }

    /// Отримує стан контейнера
    fn state(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!interface.RuntimeInterface.State {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            // Оновлюємо стан з Proxmox
            const proxmox_state = try self.proxmox_client.getContainerState(id) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.StateError,
                    else => error.StateError,
                };
            };

            return switch (proxmox_state) {
                .running => .running,
                .stopped => .stopped,
                .created => .created,
                else => .unknown,
            };
        } else {
            return error.NotFound;
        }
    }

    /// Оновлює ресурси контейнера
    fn updateResources(rt: *interface.RuntimeInterface, id: []const u8, resources: types.Resources) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.proxmox_client.updateContainerResources(id, .{
                .memory = resources.memory.limit,
                .swap = resources.memory.swap,
                .cores = resources.cpu.shares,
            }) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.ResourceError,
                    else => error.ResourceError,
                };
            };
            container.resources = resources;
        } else {
            return error.NotFound;
        }
    }

    /// Отримує статистику використання ресурсів
    fn stats(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!types.ResourceStats {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            const proxmox_stats = try self.proxmox_client.getContainerStats(id) catch |err| {
                return switch (err) {
                    error.ProxmoxError => error.ResourceError,
                    else => error.ResourceError,
                };
            };

            return .{
                .cpu = .{
                    .usage = proxmox_stats.cpu_usage,
                    .system = proxmox_stats.cpu_system,
                    .user = proxmox_stats.cpu_user,
                },
                .memory = .{
                    .usage = proxmox_stats.memory_usage,
                    .max_usage = proxmox_stats.memory_max_usage,
                    .failcnt = proxmox_stats.memory_failcnt,
                },
            };
        } else {
            return error.NotFound;
        }
    }

    /// Налаштування мережі контейнера
    fn setupNetwork(rt: *interface.RuntimeInterface, id: []const u8, config: types.NetworkConfig) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.cni_plugin.setup(id, config) catch |err| {
                return switch (err) {
                    error.CNIError => error.NetworkError,
                    else => error.NetworkError,
                };
            };
            container.network = config;
        } else {
            return error.NotFound;
        }
    }

    /// Видалення мережевих налаштувань
    fn teardownNetwork(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            if (container.network) |network| {
                try self.cni_plugin.teardown(id, network) catch |err| {
                    return switch (err) {
                        error.CNIError => error.NetworkError,
                        else => error.NetworkError,
                    };
                };
                container.network = null;
            }
        } else {
            return error.NotFound;
        }
    }

    /// Отримання мережевої статистики
    fn networkStats(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!types.NetworkStats {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            return self.cni_plugin.stats(id) catch |err| {
                return switch (err) {
                    error.CNIError => error.NetworkError,
                    else => error.NetworkError,
                };
            };
        } else {
            return error.NotFound;
        }
    }

    /// Виконання prestart хуків
    fn prestart(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try self.hooks_manager.runPrestart(container) catch |err| {
                return switch (err) {
                    error.HookError => error.HookError,
                    else => error.HookError,
                };
            };
        } else {
            return error.NotFound;
        }
    }

    /// Виконання poststart хуків
    fn poststart(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try self.hooks_manager.runPoststart(container) catch |err| {
                return switch (err) {
                    error.HookError => error.HookError,
                    else => error.HookError,
                };
            };
        } else {
            return error.NotFound;
        }
    }

    /// Виконання poststop хуків
    fn poststop(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try self.hooks_manager.runPoststop(container) catch |err| {
                return switch (err) {
                    error.HookError => error.HookError,
                    else => error.HookError,
                };
            };
        } else {
            return error.NotFound;
        }
    }
}; 