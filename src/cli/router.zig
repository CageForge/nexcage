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

    pub fn init(allocator: std.mem.Allocator, logger: ?*logging.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
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
            .lxc => try self.executeLxc(operation, container_id, config),
            .crun => try self.executeCrun(operation, container_id, config),
            .runc => try self.executeRunc(operation, container_id, config),
            .vm => try self.executeVm(operation, container_id, config),
            .proxmox_lxc => try self.executeProxmoxLxc(operation, container_id, config),
        }
    }

    fn executeLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        const lxc_backend = try backends.lxc.LxcBackend.init(self.allocator, sandbox_config);
        defer lxc_backend.deinit();

        switch (operation) {
            .create => try lxc_backend.create(sandbox_config),
            .start => try lxc_backend.start(container_id),
            .stop => try lxc_backend.stop(container_id),
            .delete => try lxc_backend.delete(container_id),
            .run => {
                try lxc_backend.create(sandbox_config);
                try lxc_backend.start(container_id);
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
            .start, .stop, .delete, .run => {
                if (self.logger) |log| {
                    try log.warn("Proxmox VM backend not fully integrated yet. VM operation skipped.", .{});
                }
            },
        }
    }

    fn executeProxmoxLxc(self: *Self, operation: Operation, container_id: []const u8, config: ?Config) !void {
        const sandbox_config = try self.createSandboxConfig(operation, container_id, .proxmox_lxc, config);
        defer self.cleanupSandboxConfig(operation, &sandbox_config);

        // Initialize state directory
        const state_dir = "/var/lib/proxmox-lxcri/state";
        
        // Initialize managers
        var vmid_mgr = try backends.proxmox_lxc.vmid_manager.VmidManager.init(self.allocator, self.logger, state_dir);
        defer vmid_mgr.deinit();

        var state_mgr = try backends.proxmox_lxc.state_manager.StateManager.init(self.allocator, self.logger, state_dir);
        defer state_mgr.deinit();

        switch (operation) {
            .create => |create_config| {
                if (self.logger) |log| {
                    try log.info("Creating Proxmox LXC container {s} with image {s}", .{ container_id, create_config.image });
                }

                // Check if container already exists
                if (try state_mgr.stateExists(container_id)) {
                    if (self.logger) |log| {
                        try log.err("Container {s} already exists", .{container_id});
                    }
                    return error.ContainerExists;
                }

                // For OCI bundle support, we need to parse the bundle
                // For now, treat the image as bundle path
                const bundle_path = create_config.image;
                
                // Parse OCI bundle
                var bundle_parser = backends.proxmox_lxc.oci_bundle.OciBundleParser.init(self.allocator, self.logger);
                var bundle_config = try bundle_parser.parseBundle(bundle_path);
                defer bundle_config.deinit();

                // Generate unique VMID
                const vmid = try vmid_mgr.generateVmid(container_id);

                // Build net0 arg from provided config (bridge)
                var net0: ?[]const u8 = null;
                if (config) |cfg_in| if (cfg_in.network) |net| if (net.bridge) |br| {
                    net0 = try std.fmt.allocPrint(self.allocator, "name=eth0,bridge={s}", .{ br });
                };
                defer if (net0) |n| self.allocator.free(n);

                // Create LXC container using pct CLI
                try self.createLxcWithPct(vmid, container_id, &bundle_config, net0);

                // Configure mounts from bundle (best-effort)
                if (bundle_config.mounts) |mounts| {
                    var idx: u8 = 0;
                    while (idx < mounts.len) : (idx += 1) {
                        const m = mounts[idx];
                        if (m.source != null and m.destination != null) {
                            var pct2 = backends.proxmox_lxc.pct.Pct.init(self.allocator, self.logger);
                            // Read-only if type is not null and equals "ro" in options (simple heuristic)
                            const ro = if (m.options) |opt| std.mem.indexOf(u8, opt, "ro") != null else false;
                            backends.proxmox_lxc.pct.Pct.setMount(&pct2, vmid, idx, m.source.?, m.destination.?, ro) catch {
                                if (self.logger) |log| log.warn("mount idx={d} skipped", .{ idx }) catch {};
                            };
                        }
                    }
                }

                // Environment variables note: pct does not provide a direct CLI flag
                // to set arbitrary environment variables at container config time.
                // We log a warning and skip for now.
                if (bundle_config.environment) |_| {
                    if (self.logger) |log| {
                        try log.warn("Environment variables from OCI bundle are not applied via pct; skipping", .{});
                    }
                }

                // Store mapping
                try vmid_mgr.storeMapping(container_id, vmid, bundle_path);

                // Create state
                try state_mgr.createState(container_id, vmid, bundle_path);

                if (self.logger) |log| {
                    try log.info("Successfully created Proxmox LXC container {s} with VMID {d}", .{ container_id, vmid });
                }
            },
            .start => {
                // Get vmid from mapping and start container
                const vmid = try vmid_mgr.getVmid(container_id);
                try self.startLxcWithPct(vmid);
                
                // Update state
                try state_mgr.updateState(container_id, "running", 0);

                if (self.logger) |log| {
                    try log.info("Started Proxmox LXC container {s} (VMID: {d})", .{ container_id, vmid });
                }
            },
            .stop => {
                // Get vmid from mapping and stop container
                const vmid = try vmid_mgr.getVmid(container_id);
                try self.stopLxcWithPct(vmid);
                
                // Update state
                try state_mgr.updateState(container_id, "stopped", 0);

                if (self.logger) |log| {
                    try log.info("Stopped Proxmox LXC container {s} (VMID: {d})", .{ container_id, vmid });
                }
            },
            .delete => {
                // Get vmid from mapping and delete container
                const vmid = try vmid_mgr.getVmid(container_id);
                try self.deleteLxcWithPct(vmid);
                
                // Remove mapping and state
                try vmid_mgr.removeMapping(container_id);
                try state_mgr.deleteState(container_id);

                if (self.logger) |log| {
                    try log.info("Deleted Proxmox LXC container {s} (VMID: {d})", .{ container_id, vmid });
                }
            },
            .run => |run_config| {
                // Create and start container
                if (self.logger) |log| {
                    try log.info("Running Proxmox LXC container {s} with image {s}", .{ container_id, run_config.image });
                }
                
                // First create the container
                const create_config = CreateConfig{
                    .image = run_config.image,
                };
                const create_op = Operation{ .create = create_config };
                try self.executeProxmoxLxc(create_op, container_id, config);
                
                // Then start it
                const start_op = Operation{ .start = {} };
                try self.executeProxmoxLxc(start_op, container_id, config);
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
