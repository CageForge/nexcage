const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ContainerConfig = struct {
    id: []const u8,
    spec: []const u8,

    pub fn deinit(self: *const ContainerConfig, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.spec);
    }
};

pub const ContainerError = error{
    InvalidConfig,
    ContainerNotFound,
    ContainerAlreadyExists,
    ContainerStartFailed,
    ContainerStopFailed,
    ContainerDeleteFailed,
};
