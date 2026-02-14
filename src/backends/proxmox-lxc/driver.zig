const std = @import("std");
const core = @import("core");
const zfs = @import("zfs.zig");
const pve = @import("pve.zig");
const oci = @import("oci.zig");
const common = @import("common.zig");
const oci_spec = @import("oci_spec");
const bundle = oci_spec.runtime.bundle;
const template_manager = @import("template_manager.zig");

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = .{ '\\', 'u', '0', '0', 0, 0 };
                    const hex = "0123456789abcdef";
                    buf[4] = hex[(c >> 4) & 0xF];
                    buf[5] = hex[c & 0xF];
                    try writer.writeAll(buf[0..]);
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

/// Proxmox LXC backend driver
pub const ProxmoxLxcDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: core.types.ProxmoxLxcBackendConfig,
    logger: ?*core.LogContext = null,
    debug_mode: bool = false,
    template_manager: template_manager.TemplateManager,
    zfs_mgr: zfs.ZfsManager,
    pve_client: pve.PveClient,
    oci_processor: oci.OciProcessor,

    pub const CommandResult = common.CommandResult;
    pub const NetDeviceRuntimeInfo = common.NetDeviceRuntimeInfo;

    pub fn init(allocator: std.mem.Allocator, config: core.types.ProxmoxLxcBackendConfig) !*Self {
        const driver = try allocator.alloc(Self, 1);

        // Initialize template manager with cache directory
        const cache_dir = "/tmp/nexcage-template-cache";
        const template_mgr = template_manager.TemplateManager.init(allocator, null, cache_dir);

        driver[0] = Self{
            .allocator = allocator,
            .config = config,
            .template_manager = template_mgr,
            .zfs_mgr = zfs.ZfsManager.init(allocator, null, config.zfs_pool),
            .pve_client = pve.PveClient.init(allocator, null),
            .oci_processor = oci.OciProcessor.init(allocator, null, config),
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.template_manager.deinit();
        self.allocator.destroy(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        self.template_manager.logger = logger;
        self.zfs_mgr.logger = logger;
        self.pve_client.logger = logger;
        self.oci_processor.logger = logger;
    }

    /// Set debug mode
    pub fn setDebugMode(self: *Self, debug_mode: bool) void {
        self.debug_mode = debug_mode;
    }

    /// Convert core.LogContext to bundle.Logger
    fn getBundleLogger(self: *const Self) ?bundle.Logger {
        if (self.logger) |log| {
            return @as(?bundle.Logger, @ptrCast(log));
        }
        return null;
    }

    /// No-op: direct ZFS CLI integration (no wrapper/client)
    pub fn setZFSClient(self: *Self) void {
        _ = self;
    }

    /// List all cached templates
    pub fn listTemplates(self: *Self) ![][]const u8 {
        return self.template_manager.listTemplates();
    }

    /// Verify template integrity
    pub fn verifyTemplate(self: *Self, template_name: []const u8) !bool {
        return self.template_manager.verifyTemplate(template_name);
    }

    /// Prune old templates
    pub fn pruneTemplates(self: *Self, max_age_days: u32) !void {
        return self.template_manager.pruneTemplates(max_age_days);
    }

    /// Get template information
    pub fn getTemplateInfo(self: *Self, template_name: []const u8) ?template_manager.TemplateInfo {
        return self.template_manager.getTemplate(template_name);
    }

    /// Check if ZFS is available (via CLI)
    pub fn isZFSAvailable(self: *Self) bool {
        return self.zfs_mgr.isZFSAvailable();
    }

    /// Check if ZFS pool exists
    fn poolExists(self: *Self, pool_name: []const u8) bool {
        return self.zfs_mgr.poolExists(pool_name);
    }

    fn datasetExists(self: *Self, dataset_name: []const u8) bool {
        return self.zfs_mgr.datasetExists(dataset_name);
    }

    fn getParentDataset(self: *Self, dataset_name: []const u8) ?[]const u8 {
        return self.zfs_mgr.getParentDataset(dataset_name);
    }

    fn isZfsCompatible(self: *Self, min_major: u32, min_minor: u32) bool {
        return self.zfs_mgr.isZfsCompatible(min_major, min_minor);
    }

    /// Get Proxmox VE version using pveversion command
    /// Returns version string like "9.1" or null on error
    pub fn getProxmoxVeVersion(self: *Self) !?[]const u8 {
        return self.pve_client.getProxmoxVeVersion();
    }

    /// Check if Proxmox VE version is >= 9.1 (supports OCI Registry pull)
    pub fn supportsOciRegistryPull(self: *Self) !bool {
        return self.pve_client.supportsOciRegistryPull();
    }

    fn getNodeName(self: *Self) ![]const u8 {
        return self.pve_client.getNodeName();
    }

    pub fn pullOciImage(self: *Self, image_ref: []const u8, storage: []const u8) ![]const u8 {
        return self.pve_client.pullOciImage(image_ref, storage);
    }

    pub fn setZFSPool(self: *Self, pool: []const u8) !void {
        try self.zfs_mgr.setPool(pool);
    }

    /// Create ZFS dataset for container
    pub fn createContainerDataset(self: *Self, container_name: []const u8, vmid: []const u8) !?[]const u8 {
        return self.zfs_mgr.createContainerDataset(container_name, vmid);
    }

    /// Destroy ZFS dataset for container
    pub fn destroyContainerDataset(self: *Self, dataset_name: []const u8) !void {
        return self.zfs_mgr.destroyContainerDataset(dataset_name);
    }

    /// Get ZFS dataset mountpoint for container
    pub fn getContainerDatasetMountpoint(self: *Self, dataset_name: []const u8) !?[]const u8 {
        return self.zfs_mgr.getContainerDatasetMountpoint(dataset_name);
    }

    fn processOciBundle(self: *Self, bundle_path: []const u8, container_name: []const u8) !?[]const u8 {
        return self.oci_processor.processOciBundle(bundle_path, container_name, &self.template_manager);
    }

    fn parseBundleImageFromConfig(self: *Self, config: *const bundle.OciBundleConfig) !?[]const u8 {
        return self.oci_processor.parseBundleImageFromConfig(config);
    }

    /// Create LXC container using pct command
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating Proxmox LXC container: {s}", .{config.name});
        }

        // 1. Process image / template
        var template_name: ?[]const u8 = null;
        defer if (template_name) |tname| self.allocator.free(tname);

        var oci_bundle_path: ?[]const u8 = null;
        var bundle_config: ?bundle.OciBundleConfig = null;
        defer if (bundle_config) |*bc| bc.deinit();

        if (config.image) |image_path| {
            if (try self.pve_client.supportsOciRegistryPull()) {
                const has_colon = std.mem.indexOf(u8, image_path, ":") != null;
                const is_tar = std.mem.endsWith(u8, image_path, ".tar.zst");
                const has_vztmpl = std.mem.indexOf(u8, image_path, ":vztmpl/") != null;
                const is_proxmox_template = is_tar or has_vztmpl;
                const is_absolute_path = std.fs.path.isAbsolute(image_path);

                if (has_colon and !is_proxmox_template and !is_absolute_path) {
                    const storage = "local";
                    const pulled = try self.pve_client.pullOciImage(image_path, storage);
                    template_name = try self.allocator.dupe(u8, pulled);
                    self.allocator.free(pulled);
                }
            }

            if (template_name == null) {
                const is_tar = std.mem.endsWith(u8, image_path, ".tar.zst");
                const has_vztmpl = std.mem.indexOf(u8, image_path, ":vztmpl/") != null;
                if (is_tar or has_vztmpl) {
                    template_name = try self.allocator.dupe(u8, image_path);
                } else {
                    // OCI Bundle processing
                    const safe_path = try core.validation.PathSecurity.validateBundlePath(image_path, self.allocator);
                    oci_bundle_path = safe_path;

                    var bundle_parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
                    bundle_config = try bundle_parser.parseBundle(safe_path);

                    template_name = try self.oci_processor.processOciBundle(safe_path, config.name, &self.template_manager);
                }
            }
        }

        // 2. Generate and validate VMID
        const vmid = try self.pve_client.generateVmid(config.name);
        defer self.allocator.free(vmid);

        if (try self.pve_client.vmidExists(vmid)) {
            if (self.logger) |log| log.err("Container with VMID {s} already exists.", .{vmid}) catch {};
            return core.Error.OperationFailed;
        }

        // 3. Resolve final template string
        var final_template: []const u8 = undefined;
        if (template_name) |tname| {
            if (std.mem.indexOf(u8, tname, ":") != null) {
                final_template = try self.allocator.dupe(u8, tname);
            } else {
                final_template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}.tar.zst", .{tname});
            }
        } else {
            final_template = try self.pve_client.findAvailableTemplate();
        }
        defer self.allocator.free(final_template);

        // 4. Handle ZFS dataset
        var zfs_dataset: ?[]const u8 = null;
        defer if (zfs_dataset) |ds| self.allocator.free(ds);
        if (self.zfs_mgr.isZFSAvailable()) {
            zfs_dataset = try self.zfs_mgr.createContainerDataset(config.name, vmid);
        }

        // 5. Build pct create command
        var args_builder = std.array_list.Managed([]const u8).init(self.allocator);
        defer args_builder.deinit();
        var allocated_args = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (allocated_args.items) |item| self.allocator.free(item);
            allocated_args.deinit();
        }

        try args_builder.appendSlice(&[_][]const u8{ "pct", "create", vmid, final_template, "--hostname", config.name });

        // Resources
        const mem_mb = if (bundle_config) |bc| (bc.memory_limit orelse (if (config.resources) |r| r.memory orelse core.constants.DEFAULT_MEMORY_BYTES else core.constants.DEFAULT_MEMORY_BYTES)) else (if (config.resources) |r| r.memory orelse core.constants.DEFAULT_MEMORY_BYTES else core.constants.DEFAULT_MEMORY_BYTES);
        const mem_mb_str = try std.fmt.allocPrint(self.allocator, "{d}", .{mem_mb / (1024 * 1024)});
        try allocated_args.append(mem_mb_str);
        try args_builder.appendSlice(&[_][]const u8{ "--memory", mem_mb_str });

        const cores = if (bundle_config) |bc| @as(u32, @intFromFloat(if (bc.cpu_limit) |l| @max(1.0, l / 1024.0) else (if (config.resources) |r| r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES) else @as(f64, core.constants.DEFAULT_CPU_CORES)))) else @as(u32, @intFromFloat(if (config.resources) |r| r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES) else @as(f64, core.constants.DEFAULT_CPU_CORES)));
        const cores_str = try std.fmt.allocPrint(self.allocator, "{d}", .{cores});
        try allocated_args.append(cores_str);
        try args_builder.appendSlice(&[_][]const u8{ "--cores", cores_str });

        // Network
        const bridge = if (config.network) |net| net.bridge orelse self.config.default_bridge orelse core.constants.DEFAULT_BRIDGE_NAME else self.config.default_bridge orelse core.constants.DEFAULT_BRIDGE_NAME;
        const net_val = try std.fmt.allocPrint(self.allocator, "name=eth0,bridge={s},ip=dhcp", .{bridge});
        try allocated_args.append(net_val);
        try args_builder.appendSlice(&[_][]const u8{ "--net0", net_val });

        var net_runtime = std.ArrayListUnmanaged(common.NetDeviceRuntimeInfo){};
        defer net_runtime.deinit(self.allocator);
        try net_runtime.append(self.allocator, .{ .alias = "eth0", .bridge = bridge, .host_name = null });

        // OS Type & Unprivileged
        const is_oci = std.mem.endsWith(u8, final_template, ".tar") and !std.mem.endsWith(u8, final_template, ".tar.zst");
        if (!is_oci) {
            try args_builder.appendSlice(&[_][]const u8{ "--ostype", self.config.default_ostype orelse "ubuntu", "--unprivileged", if (self.config.default_unprivileged) |u| if (u) "1" else "0" else "0" });
        } else if (self.config.default_unprivileged) |u| {
            if (u) try args_builder.appendSlice(&[_][]const u8{ "--unprivileged", "1" });
        }

        if (zfs_dataset) |ds| try args_builder.appendSlice(&[_][]const u8{ "--rootfs", ds });

        // 6. Execute create
        const result = try common.runCommand(self.allocator, self.logger, args_builder.items);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            if (std.mem.indexOf(u8, result.stderr, "already exists") == null) {
                if (zfs_dataset) |ds| {
                    const failed = try std.mem.concat(self.allocator, u8, &.{ ds, "-failed" });
                    defer self.allocator.free(failed);
                    _ = common.runCommand(self.allocator, self.logger, &.{ "zfs", "rename", "-r", ds, failed }) catch {};
                }
                return self.pve_client.mapPctError(result.stderr);
            }
        }

        // 7. Post-creation setup
        if (oci_bundle_path) |bp| {
            try self.applyMountsToLxcConfig(vmid, bp);
            try self.verifyMountsInConfig(vmid);
            if (bundle_config) |bc| {
                if (bc.namespaces) |ns| try self.applyNamespacesToLxcConfig(vmid, ns);
            }
        }

        const bundle_ptr: ?*const bundle.OciBundleConfig = if (bundle_config) |*bc| bc else null;
        try self.persistRuntimeMetadata(config.name, vmid, bundle_ptr, net_runtime.items);
        try self.writeOciState(config.name, "created", 0);

        if (self.logger) |log| log.info("Proxmox LXC container created: {s} (vmid {s})", .{ config.name, vmid }) catch {};
    }

    fn persistRuntimeMetadata(
        self: *Self,
        container_name: []const u8,
        vmid: []const u8,
        bundle_config: ?*const bundle.OciBundleConfig,
        net_devices: []const NetDeviceRuntimeInfo,
    ) !void {
        const intel_cfg = if (bundle_config) |bc| bc.intel_rdt else null;
        const intel_has_data = if (intel_cfg) |intel| blk: {
            if (intel.clos_id) |_| break :blk true;
            if (intel.schemata) |schemata| if (schemata.len > 0) break :blk true;
            if (intel.l3_cache_schema) |schema| if (schema.len > 0) break :blk true;
            if (intel.mem_bw_schema) |schema| if (schema.len > 0) break :blk true;
            if (intel.enable_monitoring) |_| break :blk true;
            break :blk false;
        } else false;

        if (!intel_has_data and net_devices.len == 0) {
            return;
        }

        const state_dir = "/run/nexcage";
        std.fs.cwd().makePath(state_dir) catch {};

        const container_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ state_dir, container_name });
        defer self.allocator.free(container_dir);
        std.fs.cwd().makePath(container_dir) catch {};

        const metadata_path = try std.fmt.allocPrint(self.allocator, "{s}/runtime-metadata.json", .{container_dir});
        defer self.allocator.free(metadata_path);

        const file = try std.fs.cwd().createFile(metadata_path, .{ .truncate = true });
        defer file.close();

        var buffer = std.array_list.Managed(u8).init(self.allocator);
        defer buffer.deinit();
        var writer = buffer.writer();

        try writer.writeAll("{\n  \"vmid\": ");
        try writeJsonString(&writer, vmid);

        if (intel_has_data) {
            const intel = intel_cfg.?;
            try writer.writeAll(",\n  \"intelRdt\": {\n");
            var field_written = false;
            if (intel.clos_id) |clos| {
                try writer.writeAll("    \"closID\": ");
                try writeJsonString(&writer, clos);
                field_written = true;
            }
            if (intel.schemata) |schemata| if (schemata.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"schemata\": [");
                for (schemata, 0..) |entry, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try writeJsonString(&writer, entry);
                }
                try writer.writeAll("]");
                field_written = true;
            };
            if (intel.l3_cache_schema) |schema| if (schema.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"l3CacheSchema\": ");
                try writeJsonString(&writer, schema);
                field_written = true;
            };
            if (intel.mem_bw_schema) |schema| if (schema.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"memBwSchema\": ");
                try writeJsonString(&writer, schema);
                field_written = true;
            };
            if (intel.enable_monitoring) |flag| {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"enableMonitoring\": ");
                try writer.writeAll(if (flag) "true" else "false");
                field_written = true;
            }
            if (field_written) {
                try writer.writeAll("\n  }");
            } else {
                try writer.writeAll("  }");
            }
        }

        if (net_devices.len > 0) {
            try writer.writeAll(",\n  \"netDevices\": [\n");
            for (net_devices, 0..) |device, idx| {
                try writer.writeAll("    {\n      \"alias\": ");
                try writeJsonString(&writer, device.alias);
                try writer.writeAll(",\n      \"bridge\": ");
                try writeJsonString(&writer, device.bridge);
                if (device.host_name) |host| {
                    try writer.writeAll(",\n      \"hostName\": ");
                    try writeJsonString(&writer, host);
                }
                try writer.writeAll("\n    }");
                if (idx + 1 < net_devices.len) {
                    try writer.writeAll(",\n");
                } else {
                    try writer.writeAll("\n");
                }
            }
            try writer.writeAll("  ]");
        }

        try writer.writeAll("\n}\n");
        try file.writeAll(buffer.items);

        if (self.logger) |log| log.debug("Persisted runtime metadata for {s} at {s}", .{ container_name, metadata_path }) catch {};
    }

    /// Validate that mounts in bundle config point to existing host paths or valid Proxmox storage refs
    fn validateBundleVolumes(self: *Self, bundle_path: []const u8) !void {
        return self.oci_processor.validateBundleVolumes(bundle_path, &self.pve_client);
    }

    /// Append mounts from bundle config to /etc/pve/lxc/<vmid>.conf using mpX syntax
    fn applyMountsToLxcConfig(self: *Self, vmid: []const u8, bundle_path: []const u8) !void {
        return self.oci_processor.applyMountsToLxcConfig(vmid, bundle_path);
    }

    /// Apply namespaces from OCI bundle to LXC container via pct set --features
    /// Maps OCI namespace types to LXC features where applicable
    /// Apply namespaces from OCI bundle to LXC container via pct set --features
    fn applyNamespacesToLxcConfig(self: *Self, vmid: []const u8, namespaces: []const oci_spec.runtime.bundle.NamespaceConfig) !void {
        return self.oci_processor.applyNamespacesToLxcConfig(vmid, namespaces);
    }

    /// Verify config contains mp entries via pct config
    fn verifyMountsInConfig(self: *Self, vmid: []const u8) !void {
        const args = [_][]const u8{ "pct", "config", vmid };
        const res = try self.runCommand(&args);
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return core.Error.OperationFailed;
        // Presence of "mp" lines indicates success (best-effort)
        if (std.mem.indexOf(u8, res.stdout, "mp0:") == null and std.mem.indexOf(u8, res.stdout, "mp1:") == null) {
            if (self.logger) |log| log.warn("No mp entries visible in pct config after update", .{}) catch {};
        }
    }

    /// Start LXC container using pct command
    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting Proxmox LXC container: {s}", .{container_id});
        }

        const vmid = try self.pve_client.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        try self.pve_client.start(vmid);

        const init_pid: i32 = self.pve_client.getInitPid(vmid) orelse 0;
        self.writeOciState(container_id, "running", init_pid) catch {};
    }

    /// Stop LXC container using pct command
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping Proxmox LXC container: {s}", .{container_id});
        }

        const vmid = try self.pve_client.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        try self.pve_client.stop(vmid);
        self.writeOciState(container_id, "stopped", 0) catch {};
    }

    /// Delete LXC container using pct command
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting Proxmox LXC container: {s}", .{container_id});
        }

        const vmid = try self.pve_client.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        try self.pve_client.delete(vmid);

        // ZFS cleanup if needed (renaming with -delete suffix was a specific feature)
        if (self.config.zfs_pool) |pool| {
            const dataset_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ pool, container_id, vmid });
            defer self.allocator.free(dataset_name);
            const delete_name = try std.mem.concat(self.allocator, u8, &.{ dataset_name, "-delete" });
            defer self.allocator.free(delete_name);
            _ = common.runCommand(self.allocator, self.logger, &.{ "zfs", "rename", "-r", dataset_name, delete_name }) catch {};
        }
    }

    /// Send signal to container using pct exec kill
    pub fn kill(self: *Self, container_id: []const u8, signal: []const u8) !void {
        const vmid = try self.pve_client.getVmidByName(container_id);
        defer self.allocator.free(vmid);
        try self.pve_client.kill(vmid, signal);
    }

    /// List LXC containers using pct command
    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        return self.pve_client.list(allocator);
    }

    fn writeOciState(self: *Self, container_id: []const u8, status: []const u8, pid: i32) !void {
        const state_dir = "/run/nexcage";
        try std.fs.cwd().makePath(state_dir);
        const container_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ state_dir, container_id });
        defer self.allocator.free(container_dir);
        try std.fs.cwd().makePath(container_dir);
        const state_path = try std.fmt.allocPrint(self.allocator, "{s}/state.json", .{container_dir});
        defer self.allocator.free(state_path);
        const file = try std.fs.cwd().createFile(state_path, .{ .truncate = true, .read = false });
        defer file.close();

        var json_buf = std.ArrayListUnmanaged(u8){};
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        try writer.writeAll("{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": ");
        try writeJsonString(writer, container_id);
        try writer.print(",\n  \"status\": \"{s}\",\n  \"pid\": {d},\n  \"bundle\": null,\n  \"annotations\": {{}}\n}}\n", .{ status, pid });

        try file.writeAll(json_buf.items);
    }

    pub fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        return self.pve_client.getVmidByName(name);
    }

    pub fn vmidExists(self: *Self, vmid: []const u8) !bool {
        return self.pve_client.vmidExists(vmid);
    }

    fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
        return self.pve_client.mapPctError(exit_code, stderr);
    }

    pub fn runCommand(self: *Self, args: []const []const u8) !common.CommandResult {
        return common.runCommand(self.allocator, self.logger, args);
    }
};
