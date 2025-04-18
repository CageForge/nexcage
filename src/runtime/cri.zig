const std = @import("std");
const interface = @import("interface.zig");
const types = @import("types");
const proxmox = @import("proxmox");
const Allocator = std.mem.Allocator;

/// CRI-сумісний runtime для Proxmox LXC
pub const CRIRuntime = struct {
    interface: interface.RuntimeInterface,
    containers: std.StringHashMap(Container),
    proxmox_client: *proxmox.Client,
    
    const Self = @This();

    /// Структура контейнера для CRI
    const Container = struct {
        id: []const u8,
        name: []const u8,
        pod_id: []const u8,
        state: interface.RuntimeInterface.State,
        resources: ?types.Resources,
        
        fn init(allocator: Allocator, id: []const u8, name: []const u8, pod_id: []const u8) !Container {
            return Container{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .pod_id = try allocator.dupe(u8, pod_id),
                .state = .created,
                .resources = null,
            };
        }

        fn deinit(self: *Container, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            allocator.free(self.pod_id);
        }
    };

    /// Створює новий CRI runtime
    pub fn init(allocator: Allocator, proxmox_client: *proxmox.Client, root_dir: []const u8, state_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.containers = std.StringHashMap(Container).init(allocator);
        self.proxmox_client = proxmox_client;

        const config = interface.RuntimeInterface.Config{
            .runtime_type = .cri,
            .root_dir = root_dir,
            .state_dir = state_dir,
            .network_plugin = "cni",  // Використовуємо CNI для мережі
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

        self.interface = interface.RuntimeInterface.init(
            allocator,
            config,
            lifecycle,
            resources,
        );

        return self;
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            var container = entry.value_ptr;
            container.deinit(self.interface.allocator);
        }
        self.containers.deinit();
        self.interface.allocator.destroy(self);
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
}; 