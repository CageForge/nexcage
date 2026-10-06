const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Stop command implementation for modular architecture
pub const StopCommand = struct {
    const Self = @This();

    name: []const u8 = "stop",
    description: []const u8 = "Stop a container",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn logCommandStart(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandStart(command_name);
    }

    pub fn logCommandComplete(self: *const Self, command_name: []const u8) !void {
        try self.base.logCommandComplete(command_name);
    }

    pub fn logOperation(self: *const Self, operation: []const u8, target: []const u8) !void {
        try self.base.logOperation(operation, target);
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        try self.logCommandStart("stop");

        // Check for help flag
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(help_text);
            return;
        }

        // Validate required options using validation utility
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "stop");

        try self.logOperation("Stopping container", container_id);

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.initWithDebug(allocator, self.base.logger, options.debug);

        const operation = router.Operation{ .stop = {} };
        try backend_router.routeAndExecute(operation, container_id, options.runtime_type, null);

        try self.logCommandComplete("stop");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage stop --name <id> [--runtime <type>]\n\n" ++
            "Options:\n" ++
            "  --name <id>        Container identifier\n" ++
            "  --runtime <type>   lxc|crun; overrides routing from the config file\n\n" ++
            "Notes:\n" ++
            "  If pct is not in PATH, the Proxmox LXC backend fails: nexcage must run on a\n" ++
            "  Proxmox VE host.\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
