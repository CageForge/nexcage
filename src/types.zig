const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ContainerStatus = enum {
    created,
    running,
    stopped,
    unknown,
};

pub const PodStatus = enum {
    pending,
    running,
    stopped,
    unknown,
};

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: *EnvVar, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const ContainerSpec = struct {
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    args: []const []const u8,
    env: []EnvVar,

    pub fn deinit(self: *ContainerSpec, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        for (self.command) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(self.command);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        for (self.env) |*env| {
            env.deinit(allocator);
        }
        allocator.free(self.env);
    }
};

pub const Container = struct {
    id: []const u8,
    name: []const u8,
    status: ContainerStatus,
    spec: ContainerSpec,

    pub fn deinit(self: *Container, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        self.spec.deinit(allocator);
    }
};

pub const PodSpec = struct {
    name: []const u8,
    namespace: []const u8,
    containers: []ContainerSpec,

    pub fn deinit(self: *PodSpec, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.namespace);
        for (self.containers) |*container| {
            container.deinit(allocator);
        }
        allocator.free(self.containers);
    }
};

pub const Pod = struct {
    id: []const u8,
    name: []const u8,
    namespace: []const u8,
    status: PodStatus,
    containers: []Container,

    pub fn init(allocator: Allocator, spec: PodSpec, containers: []Container) !Pod {
        return Pod{
            .id = try allocator.dupe(u8, spec.name),
            .name = try allocator.dupe(u8, spec.name),
            .namespace = try allocator.dupe(u8, spec.namespace),
            .status = .pending,
            .containers = containers,
        };
    }

    pub fn deinit(self: *Pod, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.namespace);
        for (self.containers) |*container| {
            container.deinit(allocator);
        }
        allocator.free(self.containers);
    }
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};
