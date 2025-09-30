const std = @import("std");
const core = @import("core");
const backends = @import("backends");

/// Start command implementation for modular architecture
pub const StartCommand = struct {
    const Self = @This();
    
    name: []const u8 = "start",
    description: []const u8 = "Start a container or virtual machine",
    logger: ?*core.LogContext = null,

    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing start command", .{});
        }

        // Validate required options
        if (options.container_id == null) {
            if (self.logger) |log| try log.err("Container ID is required for start command", .{});
            return core.Error.InvalidInput;
        }

        const container_id = options.container_id.?;
        const runtime_type = options.runtime_type orelse .lxc;

        if (self.logger) |log| {
            try log.info("Starting container {s} with runtime type {}", .{ container_id, runtime_type });
        }

        // Start container based on runtime type
        switch (runtime_type) {
            .lxc => {
                if (self.logger) |log| {
                    try log.info("Starting LXC container: {s}", .{container_id});
                }

                const sandbox_config = core.types.SandboxConfig{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, container_id),
                    .runtime_type = .lxc,
                    .resources = core.types.ResourceLimits{
                        .memory = 512 * 1024 * 1024,
                        .cpu = 1.0,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = core.types.NetworkConfig{
                        .bridge = try allocator.dupe(u8, "lxcbr0"),
                        .ip = null,
                        .gateway = null,
                        .dns = null,
                        .port_mappings = null,
                    },
                    .storage = null,
                };
                defer {
                    allocator.free(sandbox_config.name);
                    if (sandbox_config.network) |net| {
                        if (net.bridge) |b| allocator.free(b);
                    }
                }

                const lxc_backend = try backends.lxc.LxcBackend.init(allocator, sandbox_config);
                defer lxc_backend.deinit();
                if (self.logger) |log| lxc_backend.driver.logger = log;

                lxc_backend.start(container_id) catch |err| {
                    if (err == core.Error.UnsupportedOperation) {
                        if (self.logger) |log| try log.warn("LXC tools not available; cannot start {s}", .{container_id});
                        return;
                    }
                    return err;
                };
                return;
            },
            .vm => {
                if (self.logger) |log| {
                    try log.info("Starting Proxmox VM: {s}", .{container_id});
                    try log.warn("Proxmox VM backend not implemented yet", .{});
                    try log.info("Alert: Proxmox VM support is planned for v0.5.0", .{});
                }
                return;
            },
            .crun => {
                // No-op stub for crun until types are finalized
                if (self.logger) |log| try log.info("[noop] crun start {s}", .{container_id});
            },
            else => {
                if (self.logger) |log| try log.err("Unsupported runtime type: {}", .{runtime_type});
                return core.Error.UnsupportedOperation;
            },
        }

        if (self.logger) |log| try log.info("Start command completed successfully", .{});
    }

    pub fn help(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
        _ = self;
        return allocator.dupe(u8,
            "Usage: proxmox-lxcri start --name <id> [--runtime <type>]\n\n" ++
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
