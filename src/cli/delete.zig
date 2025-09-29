const std = @import("std");
const core = @import("core");
const backends = @import("backends");

/// Delete command implementation for modular architecture
pub const DeleteCommand = struct {
    const Self = @This();
    
    name: []const u8 = "delete",
    description: []const u8 = "Delete a container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = allocator;
        if (self.logger) |log| {
            try log.info("Executing delete command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| try log.err("Container ID is required for delete command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const runtime_type = options.runtime_type orelse .lxc;

        if (self.logger) |log| {
            try log.info("Deleting container {s} with runtime type {}", .{ container_id, runtime_type });
        }

        // Delete container based on runtime type
        switch (runtime_type) {
            .lxc => {
                if (self.logger) |log| {
                    try log.info("Deleting LXC container: {s}", .{container_id});
                    try log.warn("LXC backend temporarily disabled in CLI (no-op)", .{});
                }
                return;
            },
            .vm => {
                if (self.logger) |log| {
                    try log.info("Deleting Proxmox VM: {s}", .{container_id});
                    try log.warn("Proxmox VM backend not implemented yet", .{});
                    try log.info("Alert: Proxmox VM support is planned for v0.5.0", .{});
                }
                return;
            },
            // Proxmox VM branch disabled to avoid duplicate .vm; choose by config in future
            // else => { ... }
            .crun => {
                if (self.logger) |log| {
                    try log.info("Deleting Crun container: {s}", .{container_id});
                    try log.warn("Crun backend not implemented yet", .{});
                }
                return;
            },
            else => {
                if (self.logger) |log| try log.err("Unsupported runtime type: {}", .{runtime_type});
                return core.Error.UnsupportedOperation;
            },
        }

        if (self.logger) |log| try log.info("Delete command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: proxmox-lxcri delete --name <id>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return core.types.Error.InvalidInput;
    }
};
