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
        if (self.logger) |log| {
            try log.info("Executing delete command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| try log.err("Container ID is required for delete command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;

        if (self.logger) |log| {
            try log.info("Deleting container {s}", .{container_id});
        }

        // Load configuration for backend routing
        var config_loader = core.ConfigLoader.init(allocator);
        const cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Initialize BackendManager
        var backend_manager = try core.BackendManager.init(allocator, &cfg.logger);
        defer backend_manager.deinit();
        try backend_manager.initializePlugins();

        // Select backend based on container name using routing
        const backend_type = backend_manager.selectBackendByName(&cfg, container_id);
        if (self.logger) |log| {
            try log.info("Selected backend: {s} for container: {s}", .{ @tagName(backend_type), container_id });
        }

        // Delete container using selected backend
        try backend_manager.deleteContainer(backend_type, container_id);

        if (self.logger) |log| try log.info("Delete command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8,
            "Usage: proxmox-lxcri delete --name <id> [--runtime <type>]\n\n" ++
            "Options:\n" ++
            "  --name <id>        Container/VM identifier\n" ++
            "  --runtime <type>   Runtime: lxc|vm|crun (default: lxc)\n\n" ++
            "Notes:\n" ++
            "  If LXC tools are missing, command fails with UnsupportedOperation.\n"
        );
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return core.types.Error.InvalidInput;
    }
};
