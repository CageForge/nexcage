const std = @import("std");
const core = @import("core");

const types = core.types;
const interfaces = core.interfaces;
const backends = @import("backends");
const router = @import("router.zig");
const validation = @import("validation.zig");
const base_command = @import("base_command.zig");

/// Run command implementation
/// Run command
pub const RunCommand = struct {
    const Self = @This();

    name: []const u8 = "run",
    description: []const u8 = "Run a container",
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

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const stdout = std.fs.File.stdout();

        // Check for help flag first
        if (options.help) {
            const help_text = try self.help(allocator);
            defer allocator.free(help_text);
            try stdout.writeAll(help_text);
            return;
        }

        try self.logCommandStart("run");

        // Validate required options using validation utility
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, self.base.logger, "run");
        const container_id = validated.container_id;
        const image = validated.image;

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.init(allocator, self.base.logger);

        const operation = router.Operation{ .run = router.RunConfig{ .image = image } };
        try backend_router.routeAndExecute(operation, container_id, options.runtime_type, null);

        try self.logOperation("Running container", container_id);
        try self.logCommandComplete("run");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        // Allocated because execute() frees it: returning the literal made
        // `nexcage run --help` abort with "Invalid free".
        return allocator.dupe(u8, "Usage: nexcage run --name <name> <image>\n\n" ++
            "Create a container and start it; the same as create followed by start.\n" ++
            "<image> takes the same forms as for create (see 'nexcage create --help').\n\n" ++
            "Options:\n" ++
            "  --name <name>   Container name, used as its hostname (required)\n" ++
            "  -h, --help      Show this help message\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;

        try validation.ValidationUtils.requireNonEmptyArgs(args);
        try validation.ValidationUtils.requireImageInArgs(args);
    }
};

/// Create a run command instance
pub fn createRunCommand() RunCommand {
    return RunCommand{};
}
