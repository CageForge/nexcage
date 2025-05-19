const std = @import("std");

pub const ContainerError = error{
    NotPaused,
};

pub const State = enum {
    created,
    running,
    paused,
    stopped,
};

pub const ContainerMetadata = struct {
    id: []const u8,
    name: []const u8,
};

pub const Spec = struct {
    oci_version: []const u8,
    process: Process,
    root: Root,
    hostname: []const u8,
};

pub const Process = struct {
    terminal: bool,
    user: User,
    args: []const []const u8,
    env: []const []const u8,
    cwd: []const u8,
};

pub const User = struct {
    uid: u32,
    gid: u32,
};

pub const Root = struct {
    path: []const u8,
    readonly: bool,
};

pub const Container = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    metadata: *ContainerMetadata,
    spec: *Spec,
    state: State,
    pid: ?i32,
    exit_code: ?i32,
    exit_reason: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, metadata: *ContainerMetadata, spec: *Spec) !*Container {
        var self = try allocator.create(Container);
        self.* = .{
            .allocator = allocator,
            .metadata = metadata,
            .spec = spec,
            .state = .created,
            .pid = null,
            .exit_code = null,
            .exit_reason = null,
        };
        return self;
    }

    pub fn resume(self: *Self) !void {
        // Check if the container is in a paused state
        if (self.state != .paused) {
            return ContainerError.NotPaused;
        }
        // Change the state to running
        self.state = .running;
    }
}; 