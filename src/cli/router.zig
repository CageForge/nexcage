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
                    .lxc, .proxmox_lxc => types.NetworkConfig{
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

        // Routing supports regex patterns from the config file
        const runtime_type = cfg.getRoutedRuntime(container_id);
        if (self.logger) |log| {
            log.debug("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) }) catch {};
        }

        switch (runtime_type) {
            .lxc, .proxmox_lxc => try self.executeProxmoxLxc(operation, container_id, config),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
            else => try self.executeProxmoxLxc(operation, container_id, config),
        }
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .proxmox_lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        const proxmox_config = types.ProxmoxLxcBackendConfig{
            .allocator = self.allocator,
            .default_bridge = if (config) |cfg| if (cfg.network) |net| net.bridge else null else null,
        };

        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(self.allocator, proxmox_config);
        defer proxmox_backend.deinit();

        if (self.logger) |log| proxmox_backend.setLogger(log);
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
            .state => {
                // State operation handled by command, backend returns info
                // Router just ensures backend is initialized
            },
        }
    }

    fn executeCrun(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        // When the backend is compiled out, backends.crun is an empty struct.
        // The check is comptime-known, so the code below is never analyzed.
        if (!backends.isCrunEnabled()) return self.backendNotBuilt("crun");

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
        // Same as crun: backends.runc is an empty struct when compiled out.
        if (!backends.isRuncEnabled()) return self.backendNotBuilt("runc");

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

    /// The error must belong to core.types.Error: the command registry
    /// @errorCast's into that set, and anything outside it panics.
    fn backendNotBuilt(self: *Self, name: []const u8) types.Error {
        if (self.logger) |log| {
            log.err("The {s} backend is not built into this binary; rebuild with -Denable-backend-{s}=true", .{ name, name }) catch {};
        }
        return types.Error.UnsupportedOperation;
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
