const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Delete command implementation for modular architecture
pub const DeleteCommand = struct {
    const Self = @This();

    name: []const u8 = "delete",
    description: []const u8 = "Delete a container",
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
        try self.logCommandStart("delete");

        // Check for help flag
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            const stdout = std.fs.File.stdout();
            try stdout.writeAll(help_text);
            return;
        }

        // Validate required options using validation utility
        const container_id = try validation.ValidationUtils.requireContainerId(options, self.base.logger, "delete");

        try self.logOperation("Deleting container", container_id);

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.init(allocator, self.base.logger);

        // --force stops a running container first, as `runc delete --force`
        // does; without it pct refuses and the command fails.
        const operation = router.Operation{ .delete = router.DeleteConfig{ .force = options.force } };
        try backend_router.routeAndExecute(operation, container_id, options.runtime_type, null);

        try self.logCommandComplete("delete");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage delete --name <id> [--force] [--runtime <type>]\n\n" ++
            "Options:\n" ++
            "  --name <id>        Container identifier\n" ++
            "  -f, --force        Stop the container first if it is running\n" ++
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
