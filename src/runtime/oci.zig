const std = @import("std");
const interface = @import("interface.zig");
const types = @import("types");
const proxmox = @import("proxmox");
const network = @import("network/oci.zig");
const hooks = @import("hooks.zig");
const Allocator = std.mem.Allocator;

/// OCI-сумісний runtime для Proxmox LXC
pub const OCIRuntime = struct {
    interface: interface.RuntimeInterface,
    containers: std.StringHashMap(Container),
    proxmox_client: *proxmox.Client,
    network_manager: *network.NetworkManager,
    hooks_manager: *hooks.HooksManager,
    
    const Self = @This();

    /// Структура контейнера для OCI
    const Container = struct {
        id: []const u8,
        bundle: []const u8,
        state: interface.RuntimeInterface.State,
        resources: ?types.Resources,
        network: ?types.NetworkConfig,
        
        fn init(allocator: Allocator, id: []const u8, bundle: []const u8) !Container {
            return Container{
                .id = try allocator.dupe(u8, id),
                .bundle = try allocator.dupe(u8, bundle),
                .state = .created,
                .resources = null,
                .network = null,
            };
        }

        fn deinit(self: *Container, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.bundle);
            if (self.network) |network| {
                network.deinit(allocator);
            }
        }
    };

    /// Створює новий OCI runtime
    pub fn init(
        allocator: Allocator,
        proxmox_client: *proxmox.Client,
        root_dir: []const u8,
        state_dir: []const u8,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.containers = std.StringHashMap(Container).init(allocator);
        self.proxmox_client = proxmox_client;
        
        // Ініціалізуємо менеджер мережі
        self.network_manager = try network.NetworkManager.init(allocator, root_dir);
        errdefer self.network_manager.deinit();
        
        // Ініціалізуємо менеджер хуків
        self.hooks_manager = try hooks.HooksManager.init(allocator);
        errdefer self.hooks_manager.deinit();

        const config = interface.RuntimeInterface.Config{
            .runtime_type = .oci,
            .root_dir = root_dir,
            .state_dir = state_dir,
            .network_plugin = "native",
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
        
        const network_interface = interface.RuntimeInterface.Network{
            .setupFn = setupNetwork,
            .teardownFn = teardownNetwork,
            .statsFn = networkStats,
        };
        
        const hooks_interface = interface.RuntimeInterface.Hooks{
            .prestartFn = prestart,
            .poststartFn = poststart,
            .poststopFn = poststop,
        };

        self.interface = interface.RuntimeInterface.init(
            allocator,
            config,
            lifecycle,
            resources,
            network_interface,
            hooks_interface,
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
        self.network_manager.deinit();
        self.hooks_manager.deinit();
        self.interface.allocator.destroy(self);
    }

    /// Створює новий контейнер
    fn create(rt: *interface.RuntimeInterface, config: types.ContainerConfig) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        // Створюємо OCI специфікацію
        var builder = try oci.Builder.init(rt.allocator);
        defer builder.deinit();

        try builder.setRoot(config.root_path);
        try builder.setHostname(config.hostname);
        
        // Додаємо ресурси
        if (config.resources) |res| {
            try builder.setResources(res);
        }

        // Створюємо контейнер
        const container = try oci.Container.create(
            rt.allocator,
            config.id,
            config.name,
            try builder.build(),
        );
        errdefer container.deinit();

        // Зберігаємо контейнер
        try self.containers.put(config.id, container);
    }

    /// Запускає контейнер
    fn start(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try container.start();
        } else {
            return error.NotFound;
        }
    }

    /// Зупиняє контейнер
    fn stop(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try container.stop();
        } else {
            return error.NotFound;
        }
    }

    /// Видаляє контейнер
    fn delete(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try container.delete();
            _ = self.containers.remove(id);
            rt.allocator.destroy(container);
        } else {
            return error.NotFound;
        }
    }

    /// Отримує стан контейнера
    fn state(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!interface.RuntimeInterface.State {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            return switch (container.getState()) {
                .created => .created,
                .running => .running,
                .stopped => .stopped,
                .paused => .paused,
                .deleting => .deleting,
            };
        } else {
            return error.NotFound;
        }
    }

    /// Оновлює ресурси контейнера
    fn updateResources(rt: *interface.RuntimeInterface, id: []const u8, resources: types.Resources) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            try container.updateResources(resources);
        } else {
            return error.NotFound;
        }
    }

    /// Отримує статистику використання ресурсів
    fn stats(rt: *interface.RuntimeInterface, id: []const u8) interface.RuntimeError!types.ResourceStats {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.get(id)) |container| {
            return container.getStats();
        } else {
            return error.NotFound;
        }
    }

    /// Налаштування мережі контейнера
    fn setupNetwork(rt: *interface.RuntimeInterface, id: []const u8, config: types.NetworkConfig) interface.RuntimeError!void {
        const self = @fieldParentPtr(Self, "interface", rt);
        
        if (self.containers.getPtr(id)) |container| {
            try self.network_manager.setup(id, config) catch |err| {
                return switch (err) {
                    error.NetworkError => error.NetworkError,
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
                try self.network_manager.teardown(id, network) catch |err| {
                    return switch (err) {
                        error.NetworkError => error.NetworkError,
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
            return self.network_manager.stats(id) catch |err| {
                return switch (err) {
                    error.NetworkError => error.NetworkError,
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