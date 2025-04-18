const std = @import("std");
const interface = @import("interface.zig");
const types = @import("types");
const oci = @import("oci");
const Allocator = std.mem.Allocator;

/// OCI-сумісний runtime
pub const OCIRuntime = struct {
    interface: interface.RuntimeInterface,
    containers: std.StringHashMap(*oci.Container),
    
    const Self = @This();

    /// Створює новий OCI runtime
    pub fn init(allocator: Allocator, root_dir: []const u8, state_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.containers = std.StringHashMap(*oci.Container).init(allocator);

        const config = interface.RuntimeInterface.Config{
            .runtime_type = .oci,
            .root_dir = root_dir,
            .state_dir = state_dir,
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
            const container = entry.value_ptr.*;
            container.deinit();
            self.interface.allocator.destroy(container);
        }
        self.containers.deinit();
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
}; 