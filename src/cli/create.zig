const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const constants = @import("constants.zig");
const validation = @import("validation.zig");

/// Create command implementation for modular architecture
pub const CreateCommand = struct {
    const Self = @This();

    name: []const u8 = "create",
    description: []const u8 = "Create a new container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing create command", .{});
        }

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
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, self.logger, "create");
        const container_id = validated.container_id;
        const image = validated.image;

        if (self.logger) |log| try log.info("Creating container {s} with image {s}", .{ container_id, image });

        // Use router for backend selection and execution
        var backend_router = router.BackendRouter.init(allocator, self.logger);

        const bridge_buf = try allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME);
        defer allocator.free(bridge_buf);

        const config = router.Config{
            .network = core.types.NetworkConfig{
                .bridge = bridge_buf,
                .ip = null,
                .gateway = null,
                .dns = null,
                .port_mappings = null,
            },
        };

        const operation = router.Operation{ .create = router.CreateConfig{ .image = image } };
        try backend_router.routeAndExecute(operation, container_id, config);

        if (self.logger) |log| try log.info("Create command completed successfully", .{});
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
