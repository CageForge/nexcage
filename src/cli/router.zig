const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const constants = core.constants;
const types = core.types;

pub const BackendRouter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    debug_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn initWithDebug(allocator: std.mem.Allocator, logger: ?*core.LogContext, debug_mode: bool) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .debug_mode = debug_mode,
        };
    }

    /// Creates a SandboxConfig for the given operation
    fn createSandboxConfig(
        self: *Self,
        operation: Operation,
        container_id: []const u8,
        config: ?Config,
    ) !types.SandboxConfig {
        const name_buf = try self.allocator.dupe(u8, container_id);

        return switch (operation) {
            .create => |create_config| blk: {
                const image_buf = try self.allocator.dupe(u8, create_config.image);
                const sandbox_cfg = types.SandboxConfig{
                    .allocator = self.allocator,
                    .name = name_buf,
                    .runtime_type = .lxc,
                    .image = image_buf,
                    .resources = types.ResourceLimits{
                        .memory = constants.DEFAULT_MEMORY_BYTES,
                        .cpu = constants.DEFAULT_CPU_CORES,
                        .disk = null,
                        .network_bandwidth = null,
                    },
                    .security = null,
                    .network = if (config) |cfg| cfg.network else types.NetworkConfig{
                        .bridge = try self.allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                        .ip = null,
                        .gateway = null,
                        .dns = null,
                        .port_mappings = null,
                    },
                    .storage = null,
                };
                break :blk sandbox_cfg;
            },
            .run => |run_config| types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = .lxc,
                .image = try self.allocator.dupe(u8, run_config.image),
                .resources = null,
                .security = null,
                .network = null,
                .storage = null,
            },
            else => types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = .lxc,
                .resources = null,
                .security = null,
                .network = null,
                .storage = null,
            },
        };
    }

    /// Cleanup allocated resources in SandboxConfig
    fn cleanupSandboxConfig(self: *Self, operation: Operation, sandbox_config: *const types.SandboxConfig) void {
        switch (operation) {
            .create, .run => {
                if (sandbox_config.image) |img| self.allocator.free(img);
                if (sandbox_config.network) |net| {
                    if (net.bridge) |bridge| self.allocator.free(bridge);
                }
            },
            else => {},
        }
        self.allocator.free(sandbox_config.name);
    }

    pub fn routeAndExecute(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        // All requests are routed to Proxmox LXC backend
        try self.executeProxmoxLxc(operation, container_id, config);
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        const proxmox_config = types.ProxmoxLxcBackendConfig{
            .allocator = self.allocator,
            .default_bridge = if (config) |cfg| if (cfg.network) |net| net.bridge else null else null,
        };

        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(self.allocator, proxmox_config);
        defer proxmox_backend.deinit();

        if (self.logger) |log| {
            proxmox_backend.setLogger(log);
        }
        proxmox_backend.setDebugMode(self.debug_mode);

        switch (operation) {
            .create => try proxmox_backend.create(sandbox_config),
            .start => try proxmox_backend.start(container_id),
            .stop => try proxmox_backend.stop(container_id),
            .delete => try proxmox_backend.delete(container_id),
            .kill => |kill_cfg| try proxmox_backend.kill(container_id, kill_cfg.signal),
            .run => {
                try proxmox_backend.create(sandbox_config);
                try proxmox_backend.start(container_id);
            },
            .state => {},
        }
    }
};

pub const Operation = union(enum) {
    create: CreateConfig,
    start: void,
    stop: void,
    delete: void,
    run: RunConfig,
    state: void,
    kill: KillConfig,
};

pub const CreateConfig = struct {
    image: []const u8,
};

pub const RunConfig = struct {
    image: []const u8,
};

pub const KillConfig = struct {
    signal: []const u8,
};

pub const Config = struct {
    network: ?types.NetworkConfig = null,
    resources: ?types.ResourceLimits = null,
};
