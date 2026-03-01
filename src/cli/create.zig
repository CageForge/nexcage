const std = @import("std");
const core = @import("core");
const router = @import("router.zig");
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Create command implementation for modular architecture
pub const CreateCommand = struct {
    const Self = @This();

    name: []const u8 = "create",
    description: []const u8 = "Create a new container or virtual machine",
    base: base_command.BaseCommand = .{},

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.base.setLogger(logger);
    }

    pub fn logInfo(self: *const Self, comptime format: []const u8, args: anytype) !void {
        try self.base.logInfo(format, args);
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
        // Check for help flag
        if (options.help) {
            const out = std.fs.File.stdout();
            try out.writeAll("Create Command Help:\n");
            try out.writeAll("  Usage: nexcage create --name <container_id> --image <image>\n");
            try out.writeAll("\n");
            try out.writeAll("  Options:\n");
            try out.writeAll("    --name <id>     Container ID/name (required)\n");
            try out.writeAll("    --image <img>   Container image (required)\n");
            try out.writeAll("    --runtime <rt>  Runtime type (lxc, crun, runc, vm)\n");
            try out.writeAll("    --config <cfg>  Configuration file path\n");
            try out.writeAll("    --verbose       Enable verbose logging\n");
            try out.writeAll("    --debug         Enable debug logging\n");
            try out.writeAll("\n");
            try out.writeAll("  Examples:\n");
            try out.writeAll("    nexcage create --name my-container --image ubuntu:20.04\n");
            try out.writeAll("    nexcage create --name kube-ovn-1 --image nginx --runtime crun\n");
            return;
        }

        // Validate required options using validation utility
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, self.base.logger, "create");
        const container_id = validated.container_id;
        const image = validated.image;

        // Additional input hardening: hostname-like container_id
        core.validation.SecurityValidation.validateHostname(container_id) catch {
            const errh = @import("errors.zig").createErrorHandler(self.base.logger);
            return errh.invalidInput("Invalid container name/hostname: {s}", .{container_id});
        };

        var backend_router = router.BackendRouter.initWithDebug(allocator, self.base.logger, options.debug);
        const config: ?router.Config = null;
        const operation = router.Operation{ .create = router.CreateConfig{ .image = image } };

        backend_router.routeAndExecute(operation, container_id, config) catch |err| {
            return err;
        };

        self.logCommandComplete("create") catch {};
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: nexcage create --name <id> <image>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        try validation.ValidationUtils.requireNonEmptyArgs(args);
    }
};
