const std = @import("std");
const core = @import("core");

const types = core.types;
const interfaces = core.interfaces;
const backends = @import("backends");
const router = @import("router.zig");
const validation = @import("validation.zig");

/// Run command implementation
/// Run command
pub const RunCommand = struct {
    const Self = @This();

    name: []const u8 = "run",
    description: []const u8 = "Run a container",

    pub fn execute(self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = self;

        // Validate required options using validation utility
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, null, "run");
        const container_id = validated.container_id;
        const image = validated.image;

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.init(allocator, null);

        const operation = router.Operation{ .run = router.RunConfig{ .image = image } };
        try backend_router.routeAndExecute(operation, container_id, null);

        std.debug.print("Running container: {s} with image: {s}\n", .{ container_id, image });
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
