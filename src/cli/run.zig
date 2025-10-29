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

        // Additional input hardening: hostname-like container_id
        core.validation.SecurityValidation.validateHostname(container_id) catch {
            const errh = @import("errors.zig").createErrorHandler(self.base.logger);
            return errh.invalidInput("Invalid container name/hostname: {s}", .{container_id});
        };

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.init(allocator, self.base.logger);

        const operation = router.Operation{ .run = router.RunConfig{ .image = image } };
        try backend_router.routeAndExecute(operation, container_id, null);

        try self.logOperation("Running container", container_id);
        try self.logCommandComplete("run");
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        _ = allocator;

        return "Usage: nexcage run [OPTIONS] IMAGE [COMMAND] [ARG...]\n\n" ++
            "Run a container from an image\n\n" ++
            "Options:\n" ++
            "  -i, --interactive    Keep STDIN open even if not attached\n" ++
            "  -t, --tty           Allocate a pseudo-TTY\n" ++
            "  -d, --detach         Run container in background and print container ID\n" ++
            "  --name string        Assign a name to the container\n" ++
            "  --runtime string     Runtime to use for this container\n" ++
            "  --config string      Path to configuration file\n" ++
            "  -v, --verbose        Verbose output\n" ++
            "  --debug              Debug output\n" ++
            "  -h, --help           Show this help message\n";
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
