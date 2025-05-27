const std = @import("std");
const Spec = @import("../spec.zig").Spec;

pub const RuntimeType = enum {
    runc,
    crun,
};

pub const RuntimeError = error{
    RuntimeNotFound,
    RuntimeInitFailed,
    ContainerCreateFailed,
    ContainerStartFailed,
    ContainerKillFailed,
    ContainerDeleteFailed,
    ContainerNotFound,
    InvalidState,
} || std.mem.Allocator.Error;

pub const Runtime = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn create(self: *Self, spec: *Spec) RuntimeError!void {
        _ = self;
        _ = spec;
        return error.NotImplemented;
    }

    pub fn start(self: *Self, container_id: []const u8) RuntimeError!void {
        _ = self;
        _ = container_id;
        return error.NotImplemented;
    }

    pub fn kill(self: *Self, container_id: []const u8, signal: u32) RuntimeError!void {
        _ = self;
        _ = container_id;
        _ = signal;
        return error.NotImplemented;
    }

    pub fn delete(self: *Self, container_id: []const u8) RuntimeError!void {
        _ = self;
        _ = container_id;
        return error.NotImplemented;
    }
}; 