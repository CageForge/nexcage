const std = @import("std");
const types = @import("types");
const network = @import("network/manager.zig");
const Allocator = std.mem.Allocator;

pub const PodError = error{
    CreationFailed,
    NotFound,
    NetworkError,
    InvalidState,
    ResourceError,
};

/// Структура для управління Pod-ами
pub const Pod = struct {
    id: []const u8,
    name: []const u8,
    namespace: []const u8,
    containers: std.StringHashMap(*Container),
    network: ?*network.NetworkState,
    annotations: std.StringHashMap([]const u8),
    state: State,
    
    pub const State = enum {
        pending,
        running,
        succeeded,
        failed,
        unknown,
    };
    
    pub const Container = struct {
        id: []const u8,
        name: []const u8,
        image: []const u8,
        state: State,
        
        pub const State = enum {
            created,
            running,
            exited,
            unknown,
        };
        
        pub fn init(allocator: Allocator, id: []const u8, name: []const u8, image: []const u8) !*Container {
            const container = try allocator.create(Container);
            container.* = .{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .image = try allocator.dupe(u8, image),
                .state = .created,
            };
            return container;
        }
        
        pub fn deinit(self: *Container, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.name);
            allocator.free(self.image);
            allocator.destroy(self);
        }
    };
    
    /// Створює новий Pod
    pub fn init(
        allocator: Allocator,
        id: []const u8,
        name: []const u8,
        namespace: []const u8,
    ) !*Pod {
        const pod = try allocator.create(Pod);
        pod.* = .{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .namespace = try allocator.dupe(u8, namespace),
            .containers = std.StringHashMap(*Container).init(allocator),
            .network = null,
            .annotations = std.StringHashMap([]const u8).init(allocator),
            .state = .pending,
        };
        return pod;
    }
    
    /// Звільняє ресурси Pod-а
    pub fn deinit(self: *Pod, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.namespace);
        
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
        }
        self.containers.deinit();
        
        var annot_it = self.annotations.iterator();
        while (annot_it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.annotations.deinit();
        
        allocator.destroy(self);
    }
    
    /// Додає контейнер до Pod-а
    pub fn addContainer(
        self: *Pod,
        allocator: Allocator,
        container_id: []const u8,
        container_name: []const u8,
        image: []const u8,
    ) !void {
        const container = try Container.init(allocator, container_id, container_name, image);
        errdefer container.deinit(allocator);
        
        try self.containers.put(container_id, container);
    }
    
    /// Видаляє контейнер з Pod-а
    pub fn removeContainer(self: *Pod, allocator: Allocator, container_id: []const u8) void {
        if (self.containers.fetchRemove(container_id)) |entry| {
            entry.value.deinit(allocator);
        }
    }
    
    /// Встановлює анотацію для Pod-а
    pub fn setAnnotation(
        self: *Pod,
        allocator: Allocator,
        key: []const u8,
        value: []const u8,
    ) !void {
        const key_owned = try allocator.dupe(u8, key);
        errdefer allocator.free(key_owned);
        
        const value_owned = try allocator.dupe(u8, value);
        errdefer allocator.free(value_owned);
        
        if (self.annotations.fetchPut(key_owned, value_owned)) |old| {
            allocator.free(old.key);
            allocator.free(old.value);
        }
    }
    
    /// Оновлює стан Pod-а на основі стану контейнерів
    pub fn updateState(self: *Pod) void {
        if (self.containers.count() == 0) {
            self.state = .pending;
            return;
        }
        
        var running: usize = 0;
        var failed: usize = 0;
        var succeeded: usize = 0;
        
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            switch (entry.value_ptr.*.state) {
                .running => running += 1,
                .exited => succeeded += 1,
                .unknown => failed += 1,
                else => {},
            }
        }
        
        if (failed > 0) {
            self.state = .failed;
        } else if (running > 0) {
            self.state = .running;
        } else if (succeeded == self.containers.count()) {
            self.state = .succeeded;
        } else {
            self.state = .pending;
        }
    }
}; 