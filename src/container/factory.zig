const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("../types.zig");
const Error = @import("../error.zig").Error;

pub const ContainerType = enum {
    lxc,
    vm,
};

pub const ContainerConfig = struct {
    type: ContainerType,
    name: []const u8,
    id: []const u8,
    bundle: []const u8,
    root: struct {
        path: []const u8,
        readonly: bool = false,
    },
    // Додаткові поля конфігурації...
};

pub const Container = union(ContainerType) {
    lxc: *LXCContainer,
    vm: *VMContainer,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .lxc => |container| container.deinit(),
            .vm => |container| container.deinit(),
        }
    }

    pub fn start(self: *@This()) Error!void {
        switch (self.*) {
            .lxc => |container| try container.start(),
            .vm => |container| try container.start(),
        }
    }

    pub fn stop(self: *@This()) Error!void {
        switch (self.*) {
            .lxc => |container| try container.stop(),
            .vm => |container| try container.stop(),
        }
    }

    pub fn state(self: *@This()) Error!types.ContainerState {
        return switch (self.*) {
            .lxc => |container| try container.state(),
            .vm => |container| try container.state(),
        };
    }
};

pub const ContainerFactory = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) ContainerFactory {
        return .{
            .allocator = allocator,
        };
    }

    pub fn createContainer(self: *@This(), config: ContainerConfig) Error!Container {
        return switch (config.type) {
            .lxc => Container{ .lxc = try LXCContainer.init(self.allocator, config) },
            .vm => Container{ .vm = try VMContainer.init(self.allocator, config) },
        };
    }
};

const LXCContainer = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: types.ContainerState,

    pub fn init(allocator: Allocator, config: ContainerConfig) Error!*LXCContainer {
        const self = try allocator.create(LXCContainer);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .state = .created,
        };
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *@This()) Error!void {
        // Реалізація запуску LXC контейнера
        self.state = .running;
    }

    pub fn stop(self: *@This()) Error!void {
        // Реалізація зупинки LXC контейнера
        self.state = .stopped;
    }

    pub fn state(self: *@This()) Error!types.ContainerState {
        return self.state;
    }
};

const VMContainer = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: types.ContainerState,

    pub fn init(allocator: Allocator, config: ContainerConfig) Error!*VMContainer {
        const self = try allocator.create(VMContainer);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .state = .created,
        };
        return self;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *@This()) Error!void {
        // Реалізація запуску VM
        self.state = .running;
    }

    pub fn stop(self: *@This()) Error!void {
        // Реалізація зупинки VM
        self.state = .stopped;
    }

    pub fn state(self: *@This()) Error!types.ContainerState {
        return self.state;
    }
}; 