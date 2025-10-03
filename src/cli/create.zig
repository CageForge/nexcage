const std = @import("std");
const core = @import("core");

const backends = @import("backends");

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

        // Validate required options
        if (options.container_id == null or options.image == null) {
            if (self.logger) |log| try log.err("Container ID and image are required for create command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const image = options.image.?;

        if (self.logger) |log| try log.info("Creating container {s} with image {s}", .{ container_id, image });

        // Load configuration for backend routing
        var config_loader = core.ConfigLoader.init(allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Select backend based on config routing
        const ctype = cfg.getContainerType(container_id);
        if (self.logger) |log| {
            try log.info("Selected backend: {s} for container: {s}", .{ @tagName(ctype), container_id });
        }

        // Create sandbox configuration
        const name_buf = try allocator.dupe(u8, container_id);
        defer allocator.free(name_buf);

        const bridge_buf = try allocator.dupe(u8, "lxcbr0");
        defer allocator.free(bridge_buf);

        const image_buf = try allocator.dupe(u8, image);
        defer allocator.free(image_buf);

        const sandbox_config = core.types.SandboxConfig{
            .allocator = allocator,
            .name = name_buf,
            .runtime_type = options.runtime_type orelse .lxc,
            .image = image_buf,
            .resources = core.types.ResourceLimits{
                .memory = 512 * 1024 * 1024,
                .cpu = 1.0,
                .disk = null,
                .network_bandwidth = null,
            },
            .security = null,
            .network = core.types.NetworkConfig{
                .bridge = bridge_buf,
                .ip = null,
                .gateway = null,
                .dns = null,
                .port_mappings = null,
            },
            .storage = null,
        };

        // Create container using selected backend
        switch (ctype) {
            .lxc => {
                const lxc_backend = try backends.lxc.LxcBackend.init(allocator, sandbox_config);
                defer lxc_backend.deinit();
                try lxc_backend.create(sandbox_config);
            },
            else => {
                if (self.logger) |log| try log.warn("Selected backend not implemented for create: {}", .{ctype});
                return core.Error.UnsupportedOperation;
            },
        }

        if (self.logger) |log| try log.info("Create command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8, "Usage: proxmox-lxcri create --name <id> <image>\n");
    }

    pub fn validate(self: *Self, args: []const []const u8) !void {
        _ = self;
        if (args.len == 0) return core.types.Error.InvalidInput;
    }
};
