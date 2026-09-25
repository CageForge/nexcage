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
                // Only an explicit override sets the network here. The Proxmox
                // backend falls back to the bridge from the config file, and a
                // default filled in at this point would shadow it.
                .network = if (config) |c| c.network else null,
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
                // network is borrowed from the caller's override, never allocated here
                if (sandbox_config.image) |img| self.allocator.free(img);
            },
            else => {},
        }
        self.allocator.free(sandbox_config.name);
    }

    /// `runtime` is an explicit --runtime. Without one, the routing rules in
    /// the config file (which support regex patterns) pick the backend.
    pub fn routeAndExecute(self: *Self, operation: Operation, container_id: []const u8, runtime: ?types.RuntimeType, config: ?Config) !void {
        var config_loader = config_module.ConfigLoader.init(self.allocator);
        var cfg = try config_loader.loadDefault();
        defer cfg.deinit();

        const runtime_type = runtime orelse cfg.getRoutedRuntime(container_id);
        if (self.logger) |log| {
            log.debug("Routing container '{s}' to runtime: {s}", .{ container_id, @tagName(runtime_type) }) catch {};
        }

        switch (runtime_type) {
            .lxc, .proxmox_lxc => try self.executeProxmoxLxc(operation, container_id, config, &cfg),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
            else => try self.executeProxmoxLxc(operation, container_id, config, &cfg),
        }
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config, cfg: *const config_module.Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .proxmox_lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        // Strings are borrowed from cfg, which routeAndExecute keeps alive
        // until the backend is gone. Before this, nothing from the config file
        // reached the backend: the bridge was always the compiled-in default.
        const proxmox_config = types.ProxmoxLxcBackendConfig{
            .allocator = self.allocator,
            .default_bridge = if (config) |c| (if (c.network) |net| net.bridge else null) else cfg.network.bridge,
            .default_storage = cfg.proxmox.storage,
            .rootfs_size_gb = cfg.proxmox.rootfs_size_gb,
            .default_ostype = cfg.proxmox.ostype,
            .default_unprivileged = cfg.proxmox.unprivileged,
        };

        const proxmox_backend = try backends.proxmox_lxc.driver.ProxmoxLxcDriver.init(self.allocator, proxmox_config);
        defer proxmox_backend.deinit();

        if (self.logger) |log| proxmox_backend.setLogger(log);
        proxmox_backend.setDebugMode(self.debug_mode);

        // --console-socket and --pid-file mean what the runtime-spec means by
        // them: create leaves the container's process alive on a pty, and the
        // runtime hands the master end over and writes the pid. `pct create`
        // starts nothing, so there is neither. Refusing is the point — a flag
        // accepted and ignored is worse than one rejected.
        if (operation == .create) {
            const cc = operation.create;
            if (cc.console_socket != null or cc.pid_file != null) {
                const which = if (cc.console_socket != null) "--console-socket" else "--pid-file";
                if (self.logger) |log| {
                    log.err("{s} is not possible on the Proxmox LXC backend: pct create starts no process, so there is no pty to hand over and no pid to write. Use --runtime crun", .{which}) catch {};
                }
                return types.Error.UnsupportedOperation;
            }
        }

        switch (operation) {
            .create => try proxmox_backend.create(sandbox_config),
            .start => try proxmox_backend.start(container_id),
            .stop => try proxmox_backend.stop(container_id),
            .delete => |del| try proxmox_backend.delete(container_id, del.force),
            .kill => |kill_cfg| try proxmox_backend.kill(container_id, kill_cfg.signal),
            // An OCI runtime exits with the status of the command it ran, so
            // the backend's answer is carried out to main rather than dropped.
            .exec => |exec_cfg| core.exit_status.propagated = try proxmox_backend.exec(container_id, exec_cfg.argv),
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
        // The driver keeps the NUL-terminated strings libcrun's context points
        // at; without this they leak on every command. Nothing reached this
        // backend until exec was routed here, so nothing noticed.
        defer crun_backend.deinit();

        switch (operation) {
            .create => |create_cfg| {
                crun_backend.console_socket = create_cfg.console_socket;
                crun_backend.pid_file = create_cfg.pid_file;
                const sandbox_config = try self.createSandboxConfig(operation, container_id, .crun, config);
                defer self.cleanupSandboxConfig(operation, &sandbox_config);
                try crun_backend.create(sandbox_config);
            },
            .start => try crun_backend.start(container_id),
            .stop => try crun_backend.stop(container_id),
            .delete => try crun_backend.delete(container_id),
            .kill => |kill_cfg| try crun_backend.kill(container_id, kill_cfg.signal),
            .exec => |exec_cfg| try crun_backend.exec(container_id, exec_cfg.argv),
            .run => return self.notImplemented("run", "crun"),
            .state => {
                // State operation handled by command
            },
        }
    }

    fn executeRunc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        // Same as crun: backends.runc is an empty struct when compiled out.
        if (!backends.isRuncEnabled()) return self.backendNotBuilt("runc");

        var runc_backend = backends.runc.RuncDriver.init(self.allocator, self.logger);
        defer runc_backend.deinit();

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
            .exec => return self.notImplemented("exec", "runc"),
            .run => return self.notImplemented("run", "runc"),
            .state => {
                // State operation handled by command
            },
        }
    }

    fn executeVm(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        _ = config;
        _ = container_id;
        // This logged a warning and returned success, so `create` reported a
        // VM that was never created and exited 0.
        return self.notImplemented(@tagName(operation), "Proxmox VM");
    }

    /// The error must belong to core.types.Error: the command registry
    /// @errorCast's into that set, and anything outside it panics.
    fn backendNotBuilt(self: *Self, name: []const u8) types.Error {
        if (self.logger) |log| {
            log.err("The {s} backend is not built into this binary; rebuild with -Denable-backend-{s}=true", .{ name, name }) catch {};
        }
        return types.Error.UnsupportedOperation;
    }

    /// For operations a backend does not have. Same error-set rule as above.
    fn notImplemented(self: *Self, operation: []const u8, backend: []const u8) types.Error {
        if (self.logger) |log| {
            log.err("{s} is not implemented for the {s} backend", .{ operation, backend }) catch {};
        }
        return types.Error.UnsupportedOperation;
    }
};

pub const Operation = union(enum) {
    create: CreateConfig,
    start: void,
    stop: void,
    delete: DeleteConfig,
    run: RunConfig,
    state: void,
    kill: KillConfig,
    exec: ExecConfig,
};

pub const CreateConfig = struct {
    image: []const u8,
    /// Where to send the master end of the container's pty, and where to write
    /// the container process's pid. Both belong to the runtime-spec `create`;
    /// only a backend that starts a process on create can honour them.
    console_socket: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
};

pub const RunConfig = struct {
    image: []const u8,
};

pub const KillConfig = struct {
    signal: []const u8,
};

pub const DeleteConfig = struct {
    /// Stop the container first instead of refusing. `runc delete --force`
    /// does the same, and a container engine relies on it when it gives up on
    /// a clean shutdown.
    force: bool = false,
};

pub const ExecConfig = struct {
    /// The command and its arguments, as the caller typed them
    argv: []const []const u8,
};

pub const Config = struct {
    network: ?types.NetworkConfig = null,
    resources: ?types.ResourceLimits = null,
};
