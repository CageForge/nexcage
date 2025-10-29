const std = @import("std");
const core = @import("core");

const backends = @import("backends");
const router = @import("router.zig");
const constants = core.constants;
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
        // Debug output only if enabled
        const stdout = std.fs.File.stdout();
        if (options.debug) {
            try stdout.writeAll("DEBUG: Create command started\n");
        }
        
        // Skip logging at start to prevent segfault issues with logger allocator
        // self.logCommandStart("create") catch {};
        if (options.debug) {
            try stdout.writeAll("DEBUG: After logCommandStart (skipped)\n");
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

        if (options.debug) {
            try stdout.writeAll("DEBUG: Before validation\n");
        }
        
        // Validate required options using validation utility
        const validated = try validation.ValidationUtils.requireContainerIdAndImage(options, self.base.logger, "create");
        const container_id = validated.container_id;
        const image = validated.image;

        if (options.debug) {
            try stdout.writeAll("DEBUG: After validation\n");
        }

        // Skip logging to prevent segfault issues
        // self.logInfo("Creating container {s} with image {s}", .{ container_id, image }) catch {};
        if (options.debug) {
            try stdout.writeAll("DEBUG: Before router init\n");
        }

        // Use router for backend selection and execution
        if (options.debug) {
            try stdout.writeAll("DEBUG: Calling BackendRouter.initWithDebug\n");
        }
        var backend_router = router.BackendRouter.initWithDebug(allocator, self.base.logger, options.debug);
        if (options.debug) {
            try stdout.writeAll("DEBUG: After BackendRouter.initWithDebug\n");
        }

        if (options.debug) {
            try stdout.writeAll("DEBUG: Before config creation\n");
        }
        // Try with null config first to see if config creation is the issue
        const config: ?router.Config = null;
        // const bridge_buf = try allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME);
        // const config = router.Config{
        //     .network = core.types.NetworkConfig{
        //         .bridge = bridge_buf,
        //         .ip = null,
        //         .gateway = null,
        //         .dns = null,
        //         .port_mappings = null,
        //     },
        // };

        if (options.debug) {
            try stdout.writeAll("DEBUG: Before operation creation\n");
        }
        const operation = router.Operation{ .create = router.CreateConfig{ .image = image } };
        if (options.debug) {
            try stdout.writeAll("DEBUG: Before routeAndExecute\n");
            try stdout.writeAll("DEBUG: backend_router address: ");
            const router_addr = try std.fmt.allocPrint(allocator, "{*}\n", .{&backend_router});
            defer allocator.free(router_addr);
            try stdout.writeAll(router_addr);
            try stdout.writeAll("DEBUG: operation = ");
            try stdout.writeAll(@tagName(operation));
            try stdout.writeAll("\n");
            try stdout.writeAll("DEBUG: container_id = '");
            try stdout.writeAll(container_id);
            try stdout.writeAll("'\n");
            try stdout.writeAll("DEBUG: config is ");
            if (config) |_| {
                try stdout.writeAll("not null\n");
            } else {
                try stdout.writeAll("null\n");
            }
            try stdout.writeAll("DEBUG: Calling routeAndExecute now...\n");
        }
        
        backend_router.routeAndExecute(operation, container_id, config) catch |err| {
            if (options.debug) {
                try stdout.writeAll("DEBUG: routeAndExecute returned error: ");
                const err_str = try std.fmt.allocPrint(allocator, "{}\n", .{err});
                defer allocator.free(err_str);
                try stdout.writeAll(err_str);
            }
            return err;
        };
        
        if (options.debug) {
            try stdout.writeAll("DEBUG: After routeAndExecute (success)\n");
        }

        // Safe logging: catch errors to prevent crashes
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
