const std = @import("std");
const core = @import("core");
const backends = @import("backends");
const constants = core.constants;
const types = core.types;
const logging = core.logging;
const config_module = core.config;

pub const BackendRouter = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*logging.LogContext,
    debug_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, logger: ?*logging.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn initWithDebug(allocator: std.mem.Allocator, logger: ?*logging.LogContext, debug_mode: bool) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .debug_mode = debug_mode,
        };
    }

    /// Creates a SandboxConfig for the given operation and runtime type
    fn createSandboxConfig(
        self: *Self,
        operation: Operation,
        container_id: []const u8,
        runtime_type: types.RuntimeType,
        config: ?Config,
    ) !types.SandboxConfig {
        const name_buf = try self.allocator.dupe(u8, container_id);

        return switch (operation) {
            .create => |create_config| types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = runtime_type,
                .image = try self.allocator.dupe(u8, create_config.image),
                .resources = types.ResourceLimits{
                    .memory = constants.DEFAULT_MEMORY_BYTES,
                    .cpu = constants.DEFAULT_CPU_CORES,
                    .disk = null,
                    .network_bandwidth = null,
                },
                .security = null,
                .network = if (config) |cfg| cfg.network else switch (runtime_type) {
                    .lxc => types.NetworkConfig{
                        .bridge = try self.allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                        .ip = null,
                        .gateway = null,
                        .dns = null,
                        .port_mappings = null,
                    },
                    else => null,
                },
                .storage = null,
            },
            .run => |run_config| types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = runtime_type,
                .image = try self.allocator.dupe(u8, run_config.image),
                .resources = null,
                .security = null,
                .network = null,
                .storage = null,
            },
            else => types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = runtime_type,
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
        var config_loader = config_module.ConfigLoader.init(self.allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        // Use the new routing system that supports regex patterns
        const runtime_type = cfg.getRoutedRuntime(container_id);
        if (self.logger) |log| {
            try log.info("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) });
        }

        // Convert RuntimeType to ContainerType for backend execution
        const ctype = switch (runtime_type) {
            .lxc => types.ContainerType.lxc,
            .crun => types.ContainerType.crun,
            .runc => types.ContainerType.runc,
            .vm => types.ContainerType.vm,
            .proxmox_lxc => types.ContainerType.proxmox_lxc,
            else => types.ContainerType.lxc, // fallback
        };

        if (self.logger) |log| {
            try log.info("Executing with backend: {s} for container: {s}", .{ @tagName(ctype), container_id });
        }

        switch (ctype) {
            .lxc => try self.executeProxmoxLxc(operation, container_id, config),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
            .proxmox_lxc => try self.executeProxmoxLxc(operation, container_id, config),
        }
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .proxmox_lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        // Create Proxmox LXC backend with default config
        const proxmox_config = types.ProxmoxLxcBackendConfig{
            .allocator = self.allocator,
            .default_bridge = if (config) |cfg| if (cfg.network) |net| net.bridge else null else null,
        };

        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(self.allocator, proxmox_config);
        defer proxmox_backend.deinit();

        if (self.logger) |log| {
            proxmox_backend.setLogger(log);
        }
        
        // Set debug mode
        proxmox_backend.setDebugMode(self.debug_mode);

        switch (operation) {
            .create => try proxmox_backend.create(sandbox_config),
            .start => try proxmox_backend.start(container_id),
            .stop => try proxmox_backend.stop(container_id),
            .delete => try proxmox_backend.delete(container_id),
            .run => {
                try proxmox_backend.create(sandbox_config);
                try proxmox_backend.start(container_id);
            },
            .state => {
                // State operation handled by command, backend returns info
                // Router just ensures backend is initialized
                // No-op here, command will call backend directly
            },
        }
    }

    fn executeCrun(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var crun_backend = backends.crun.CrunDriver.init(self.allocator, self.logger);

        switch (operation) {
            .create => {
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .crun, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
                try crun_backend.create(sandbox_config);
            },
            .start => try crun_backend.start(container_id),
            .stop => try crun_backend.stop(container_id),
            .delete => try crun_backend.delete(container_id),
            .run => {
                if (self.logger) |log| {
                    try log.warn("Crun run operation not implemented", .{});
                }
            },
            .state => {
                // State operation handled by command
            },
        }
    }

    fn executeRunc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        var runc_backend = backends.runc.RuncDriver.init(self.allocator, self.logger);

        switch (operation) {
            .create => {
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .runc, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
                try runc_backend.create(sandbox_config);
            },
            .start => try runc_backend.start(container_id),
            .stop => try runc_backend.stop(container_id),
            .delete => try runc_backend.delete(container_id),
            .run => {
                if (self.logger) |log| {
                    try log.warn("Runc run operation not implemented", .{});
                }
            },
            .state => {
                // State operation handled by command
            },
        }
    }

    fn executeVm(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        _ = config;
        _ = container_id;

        switch (operation) {
            .create => |create_config| {
                if (self.logger) |log| {
                    try log.warn("Proxmox VM backend not fully integrated yet. VM creation for image {s} skipped.", .{create_config.image});
                }
            },
            .start, .stop, .delete, .run, .state => {
                if (self.logger) |log| {
                    try log.warn("Proxmox VM backend not fully integrated yet. VM operation skipped.", .{});
                }
            },
        }
    }


    /// Create LXC container using pct CLI
    fn createLxcWithPct(self: *Self, vmid: u32, hostname: []const u8, bundle_config: *const backends.proxmox_lxc.oci_bundle.OciBundleConfig, net0: ?[]const u8) !void {
        if (self.logger) |log| {
            try log.info("Creating LXC container {d} with pct CLI", .{vmid});
        }

        var pct = backends.proxmox_lxc.pct.Pct.init(self.allocator, self.logger);

        const hostname_to_use = bundle_config.hostname orelse hostname;
        const memory_mb: ?u64 = if (bundle_config.memory_limit) |m| m / (1024 * 1024) else null;
        const cores: ?u32 = if (bundle_config.cpu_limit) |cpu| @as(u32, @intFromFloat(cpu)) else null;

        try pct.create(vmid, bundle_config.rootfs_path, hostname_to_use, memory_mb, cores, net0);

        if (self.logger) |log| {
            try log.info("Successfully created LXC container {d}", .{vmid});
        }
    }

    /// Start LXC container using pct CLI
    fn startLxcWithPct(self: *Self, vmid: u32) !void {
        var pct = backends.proxmox_lxc.pct.Pct.init(self.allocator, self.logger);
        try pct.start(vmid);
    }

    /// Stop LXC container using pct CLI
    fn stopLxcWithPct(self: *Self, vmid: u32) !void {
        var pct = backends.proxmox_lxc.pct.Pct.init(self.allocator, self.logger);
        try pct.stop(vmid);
    }

    /// Delete LXC container using pct CLI
    fn deleteLxcWithPct(self: *Self, vmid: u32) !void {
        var pct = backends.proxmox_lxc.pct.Pct.init(self.allocator, self.logger);
        try pct.destroy(vmid);
    }
};

pub const Operation = union(enum) {
    create: CreateConfig,
    start: void,
    stop: void,
    delete: void,
    run: RunConfig,
    state: void,
};

pub const CreateConfig = struct {
    image: []const u8,
};

pub const RunConfig = struct {
    image: []const u8,
};

pub const Config = struct {
    network: ?types.NetworkConfig = null,
    resources: ?types.ResourceLimits = null,
};
