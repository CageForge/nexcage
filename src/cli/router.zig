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
        const stdout = std.fs.File.stdout();
        
        if (self.debug_mode) {
            try stdout.writeAll("[ROUTER] createSandboxConfig: Starting\n");
            try stdout.writeAll("[ROUTER] createSandboxConfig: container_id = '");
            try stdout.writeAll(container_id);
            try stdout.writeAll("'\n");
        }
        
        if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: Duplicating container_id\n");
        const name_buf = try self.allocator.dupe(u8, container_id);
        if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: name_buf created\n");

        if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: Creating SandboxConfig\n");
        
        return switch (operation) {
            .create => |create_config| blk: {
                if (self.debug_mode) {
                    try stdout.writeAll("[ROUTER] createSandboxConfig: operation is .create\n");
                    try stdout.writeAll("[ROUTER] createSandboxConfig: create_config.image = '");
                    try stdout.writeAll(create_config.image);
                    try stdout.writeAll("'\n");
                }
                if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: Duplicating image\n");
                const image_buf = try self.allocator.dupe(u8, create_config.image);
                if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: image_buf created\n");
                if (self.debug_mode) {
                    try stdout.writeAll("[ROUTER] createSandboxConfig: Building SandboxConfig struct\n");
                }
                const sandbox_cfg = types.SandboxConfig{
                .allocator = self.allocator,
                .name = name_buf,
                .runtime_type = runtime_type,
                .image = image_buf,
                .resources = types.ResourceLimits{
                    .memory = constants.DEFAULT_MEMORY_BYTES,
                    .cpu = constants.DEFAULT_CPU_CORES,
                    .disk = null,
                    .network_bandwidth = null,
                },
                .security = null,
                .network = if (config) |cfg| cfg.network else switch (runtime_type) {
                    .lxc, .proxmox_lxc => net_blk: {
                        if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: Creating network config for LXC\n");
                        break :net_blk types.NetworkConfig{
                            .bridge = try self.allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                            .ip = null,
                            .gateway = null,
                            .dns = null,
                            .port_mappings = null,
                        };
                    },
                    else => null,
                },
                .storage = null,
                };
                if (self.debug_mode) try stdout.writeAll("[ROUTER] createSandboxConfig: SandboxConfig created successfully\n");
                break :blk sandbox_cfg;
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
        // Use stderr for debug output to avoid buffering issues
        const stderr = std.fs.File.stderr();
        
        if (self.debug_mode) {
            // Immediately write to stderr (unbuffered) to catch segfault location
            stderr.writeAll("[ROUTER] routeAndExecute: ENTRY\n") catch {};
        }
        
        // Check self pointer validity by accessing fields (suppress unused warnings)
        _ = self.allocator;
        _ = self.debug_mode;
        
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] routeAndExecute: Self check passed\n") catch {};
        }
        
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] routeAndExecute: Starting (debug mode ON)\n") catch {};
            stderr.writeAll("[ROUTER] routeAndExecute: container_id = '") catch {};
            stderr.writeAll(container_id) catch {};
            stderr.writeAll("'\n") catch {};
        }
        
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Before ConfigLoader init\n") catch {};
        var config_loader = config_module.ConfigLoader.init(self.allocator);
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: ConfigLoader initialized\n") catch {};
        
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] routeAndExecute: Loading default config\n") catch {};
        }
        
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling loadDefault\n") catch {};
        var cfg = config_loader.loadDefault() catch |err| {
            if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: ERROR in loadDefault\n") catch {};
            return err;
        };
        defer cfg.deinit();
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Default config loaded successfully\n") catch {};
        
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] routeAndExecute: Config loaded, proceeding\n") catch {};
        }

        // Use the new routing system that supports regex patterns
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Before getRoutedRuntime\n") catch {};
        const runtime_type = cfg.getRoutedRuntime(container_id);
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: After getRoutedRuntime\n") catch {};
        
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] routeAndExecute: Runtime type: ") catch {};
            const rt_str = @tagName(runtime_type);
            stderr.writeAll(rt_str) catch {};
            stderr.writeAll("\n") catch {};
        }
        
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Before logger routing info\n") catch {};
        // Skip logger call to avoid segfault - logger allocator might be invalid
        // if (self.logger) |log| {
        //     log.info("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) }) catch {};
        // }
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: After logger routing info (skipped)\n") catch {};

        // Convert RuntimeType to ContainerType for backend execution
        const ctype = switch (runtime_type) {
            .lxc => types.ContainerType.lxc,
            .crun => types.ContainerType.crun,
            .runc => types.ContainerType.runc,
            .vm => types.ContainerType.vm,
            .proxmox_lxc => types.ContainerType.proxmox_lxc,
            else => types.ContainerType.lxc, // fallback
        };
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: ContainerType converted\n") catch {};

        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Before logger execution info\n") catch {};
        // Skip logger call to avoid segfault
        // if (self.logger) |log| {
        //     log.info("Executing with backend: {s} for container: {s}", .{ @tagName(ctype), container_id }) catch {};
        // }
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Before switch statement\n") catch {};

        switch (ctype) {
            .lxc => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling executeProxmoxLxc (lxc)\n") catch {};
                try self.executeProxmoxLxc(operation, container_id, config);
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: executeProxmoxLxc completed\n") catch {};
            },
            .crun => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling executeCrun\n") catch {};
                try self.executeCrun(operation, container_id, config);
            },
            .runc => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling executeRunc\n") catch {};
                try self.executeRunc(operation, container_id, config);
            },
            .vm => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling executeVm\n") catch {};
                try self.executeVm(operation, container_id, config);
            },
            .proxmox_lxc => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Calling executeProxmoxLxc (proxmox_lxc)\n") catch {};
                try self.executeProxmoxLxc(operation, container_id, config);
                if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: executeProxmoxLxc completed\n") catch {};
            },
        }
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: Switch completed\n") catch {};
        if (self.debug_mode) stderr.writeAll("[ROUTER] routeAndExecute: FINISHED\n") catch {};
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const stderr = std.fs.File.stderr();
        
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: ENTRY\n") catch {};
        if (self.debug_mode) {
            stderr.writeAll("[ROUTER] executeProxmoxLxc: container_id = '") catch {};
            stderr.writeAll(container_id) catch {};
            stderr.writeAll("'\n") catch {};
        }
        
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Before createSandboxConfig\n") catch {};
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .proxmox_lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Sandbox config created\n") catch {};

        // Create Proxmox LXC backend with default config
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Creating ProxmoxLxcBackendConfig\n") catch {};
        const proxmox_config = types.ProxmoxLxcBackendConfig{
            .allocator = self.allocator,
            .default_bridge = if (config) |cfg| if (cfg.network) |net| net.bridge else null else null,
        };
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Config created\n") catch {};

        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Initializing ProxmoxLxcDriver\n") catch {};
        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(self.allocator, proxmox_config);
        defer proxmox_backend.deinit();
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Driver initialized\n") catch {};

        // Set logger if available
        if (self.logger) |log| {
            if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Setting logger\n") catch {};
            proxmox_backend.setLogger(log);
            if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Logger set\n") catch {};
        } else {
            if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: No logger available\n") catch {};
        }
        
        // Set debug mode
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Setting debug mode\n") catch {};
        proxmox_backend.setDebugMode(self.debug_mode);
        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Debug mode set\n") catch {};

        if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Before operation switch\n") catch {};
        
        switch (operation) {
            .create => {
                if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: Calling backend.create\n") catch {};
                try proxmox_backend.create(sandbox_config);
                if (self.debug_mode) stderr.writeAll("[ROUTER] executeProxmoxLxc: backend.create completed\n") catch {};
            },
            .start => try proxmox_backend.start(container_id),
            .stop => try proxmox_backend.stop(container_id),
            .delete => try proxmox_backend.delete(container_id),
            .kill => |kill_cfg| try proxmox_backend.kill(container_id, kill_cfg.signal),
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
            .kill => |kill_cfg| try crun_backend.kill(container_id, kill_cfg.signal),
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
            .kill => |kill_cfg| try runc_backend.kill(container_id, kill_cfg.signal),
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
            .start, .stop, .delete, .run, .state, .kill => {
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
