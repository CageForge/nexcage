const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Start command implementation for modular architecture
pub const StartCommand = struct {
    const Self = @This();

    name: []const u8 = "start",
    description: []const u8 = "Start a container or virtual machine",
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
        try self.logCommandStart("start");

        // Check for help flag
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(help_text);
            return;
        }

        // Validate required options using validation utility
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "start");

        try self.logOperation("Starting container", container_id);

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.initWithDebug(allocator, self.base.logger, options.debug);

        const operation = router.Operation{ .start = {} };
        try backend_router.routeAndExecute(operation, container_id, null);

        try self.logCommandComplete("start");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage start --name <id> [--runtime <type>]\n\n" ++
            "Options:\n" ++
            "  --name <id>        Container/VM identifier\n" ++
            "  --runtime <type>   Runtime: lxc|vm|crun (default: lxc)\n\n" ++
            "Notes:\n" ++
            "  If LXC tools are missing, command fails with UnsupportedOperation.\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
