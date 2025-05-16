const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const types = @import("types");
const Error = @import("error").Error;
const Config = @import("config").Config;

pub const ContainerType = enum {
    lxc,
    crun,
};

pub const ContainerConfig = struct {
    allocator: Allocator,
    id: []const u8,
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    env: []const []const u8,
    working_dir: []const u8,
    user: []const u8,
    type: ContainerType,
};

pub const ContainerState = enum {
    created,
    running,
    stopped,
    deleted,
};

pub const Container = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: ContainerState,
    pid: ?i32,

    pub fn init(allocator: Allocator, config: ContainerConfig) !*Container {
        var container = try allocator.create(Container);
        container.* = Container{
            .allocator = allocator,
            .config = config,
            .state = .created,
            .pid = null,
        };
        return container;
    }

    pub fn deinit(self: *Container) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *Container) !void {
        switch (self.config.type) {
            .lxc => try self.startLxc(),
            .crun => try self.startCrun(),
        }
    }

    pub fn stop(self: *Container) !void {
        switch (self.config.type) {
            .lxc => try self.stopLxc(),
            .crun => try self.stopCrun(),
        }
    }

    pub fn getState(self: *Container) ContainerState {
        return self.state;
    }

    fn startLxc(self: *Container) !void {
        // TODO: Implement LXC container start
        log.info("Starting LXC container: {s}", .{self.config.id});
        self.state = .running;
    }

    fn startCrun(self: *Container) !void {
        // TODO: Implement crun container start
        log.info("Starting crun container: {s}", .{self.config.id});
        self.state = .running;
    }

    fn stopLxc(self: *Container) !void {
        // TODO: Implement LXC container stop
        log.info("Stopping LXC container: {s}", .{self.config.id});
        self.state = .stopped;
    }

    fn stopCrun(self: *Container) !void {
        // TODO: Implement crun container stop
        log.info("Stopping crun container: {s}", .{self.config.id});
        self.state = .stopped;
    }
};

pub fn createContainer(allocator: Allocator, config: *Config, container_config: ContainerConfig) !*Container {
    var new_config = container_config;
    new_config.type = config.getContainerType(container_config.name);
    return try Container.init(allocator, new_config);
} 