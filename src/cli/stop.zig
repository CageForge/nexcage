const std = @import("std");
const core = @import("core");
const backends = @import("backends");

/// Stop command implementation for modular architecture
pub const StopCommand = struct {
    const Self = @This();
    
    name: []const u8 = "stop",
    description: []const u8 = "Stop a container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = allocator;
        if (self.logger) |log| {
            try log.info("Executing stop command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| try log.err("Container ID is required for stop command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const runtime_type = options.runtime_type orelse .lxc;

        if (self.logger) |log| {
            try log.info("Stopping container {s} with runtime type {}", .{ container_id, runtime_type });
        }

        // Stop container based on runtime type
        switch (runtime_type) {
            .lxc => {
                if (self.logger) |log| {
                    try log.info("Stopping LXC container: {s}", .{container_id});
                    try log.warn("LXC backend temporarily disabled in CLI (no-op)", .{});
                }
                return;
            },
            // Proxmox LXC mapped under VM runtime type
            .vm => {
                if (self.logger) |log| {
                    try log.info("Stopping Proxmox VM: {s}", .{container_id});
                    try log.warn("Proxmox VM backend not implemented yet", .{});
                    try log.info("Alert: Proxmox VM support is planned for v0.5.0", .{});
                }
                return;
            },
            // Proxmox VM branch temporarily disabled to avoid duplicate .vm case; choose by config later
            .crun => {
                if (self.logger) |log| {
                    try log.info("Stopping Crun container: {s}", .{container_id});
                    try log.warn("Crun backend not implemented yet", .{});
                }
                return;
            },
            else => {
                if (self.logger) |log| try log.err("Unsupported runtime type: {}", .{runtime_type});
                return core.Error.UnsupportedOperation;
            },
        }

        if (self.logger) |log| try log.info("Stop command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: proxmox-lxcri stop --name <id>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return core.types.Error.InvalidInput;
    }
};
