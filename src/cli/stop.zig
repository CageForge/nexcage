const std = @import("std");
const core = @import("core");

const backends = @import("backends");

/// Stop command implementation for modular architecture
pub const StopCommand = struct {
    const Self = @This();
    
    name: []const u8 = "stop",
    description: []const u8 = "Stop a container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing stop command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| try log.err("Container ID is required for stop command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;

        if (self.logger) |log| {
            try log.info("Stopping container {s}", .{container_id});
        }

        // Load configuration for backend routing
        var config_loader = core.ConfigLoader.init(allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Select backend based on config routing
        const ctype = cfg.getContainerType(container_id);
        if (self.logger) |log| {
            try log.info("Selected backend: {s} for container: {s}", .{ @tagName(ctype), container_id });
        }

        // Stop container using selected backend
        switch (ctype) {
            .lxc => {
                // Create minimal sandbox config for LXC
                const name_buf = try allocator.dupe(u8, container_id);
                defer allocator.free(name_buf);
                
                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = name_buf,
                    .runtime_type = .lxc,
                    .resources = null,
                    .security = null,
                    .network = null,
                    .storage = null,
                };
                
                const lxc_backend = try backends.lxc.LxcBackend.init(allocator, sandbox_config);
                defer lxc_backend.deinit();
                try lxc_backend.stop(container_id);
            },
            else => {
                if (self.logger) |log| try log.warn("Selected backend not implemented for stop: {}", .{ctype});
                return core.Error.UnsupportedOperation;
            },
        }

        if (self.logger) |log| try log.info("Stop command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8,
            "Usage: proxmox-lxcri stop --name <id> [--runtime <type>]\n\n" ++
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
