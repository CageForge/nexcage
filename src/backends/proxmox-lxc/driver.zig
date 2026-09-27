const std = @import("std");
const core = @import("core");
const zfs = @import("zfs.zig");
const pve = @import("pve.zig");
const oci = @import("oci.zig");
const common = @import("common.zig");
const oci_spec = @import("oci_spec");
const bundle = oci_spec.runtime.bundle;
const template_manager = @import("template_manager.zig");

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
    /// Remove a template; answers whether its storage was a shared one, where
    /// the file is gone from every node rather than only the one named.
    pub fn removeTemplate(self: *Self, allocator: std.mem.Allocator, node: []const u8, volid: []const u8) !bool {
        return self.pve_client.removeTemplate(allocator, node, volid);
    }

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

    fn parseBundleImageFromConfig(self: *Self, config: *const bundle.OciBundleConfig) !?[]const u8 {
        return self.oci_processor.parseBundleImageFromConfig(config);
    }

    /// Create LXC container using pct command
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating Proxmox LXC container: {s}", .{config.name});
        }

        // The name becomes the container's hostname, so it has to be one.
        // This used to be checked in the create command, before the backend
        // was known, which made it a rule for every backend: a container
        // engine addresses containers by a 64-character hex id, and nexcage
        // answered "Invalid container name/hostname" to podman's very first
        // create. An id is not a hostname anywhere but here.
        core.validation.SecurityValidation.validateHostname(config.name) catch {
            if (self.logger) |log| log.err("'{s}' cannot be a container hostname; the Proxmox LXC backend uses the name as one, so it must be RFC-1123 (letters, digits and hyphens, at most 63 per label)", .{config.name}) catch {};
            return core.Error.InvalidInput;
        };

        // Every other command finds a container by name, so names must be
        // unique -- and unique across the cluster, not just on this host, or
        // the name would resolve to two containers and the first one found
        // would win. Checked before any image is pulled.
        if (self.pve_client.locate(self.allocator, config.name)) |found| {
            var existing = found;
            defer existing.deinit();
            if (existing.local) {
                if (self.logger) |log| log.err("Container '{s}' already exists (vmid {s})", .{ config.name, existing.vmid }) catch {};
            } else {
                if (self.logger) |log| log.err("Container '{s}' already exists on node {s} (vmid {s})", .{ config.name, existing.node, existing.vmid }) catch {};
            }
            return core.Error.OperationFailed;
        } else |err| {
            if (err != core.Error.NotFound) return err;
        }

        // --node: make the container on another node of the cluster, through
        // that node's API. Three things in the path below are local by
        // construction, and each is refused rather than half-done.
        var target_node: ?[]const u8 = null;
        if (config.node) |wanted| {
            const here = self.pve_client.getNodeName() catch null;
            defer if (here) |h| self.allocator.free(h);
            const same = if (here) |h| std.mem.eql(u8, h, wanted) else false;
            if (!same) target_node = wanted;
        }
        if (target_node) |node| {
            // A bundle's rootfs is packed into a template on *this* host's
            // storage, and a registry pull lands here too. Neither is visible
            // from another node unless the storage is shared, and nexcage
            // cannot make it so.
            const image_path = config.image orelse "";
            const is_template = std.mem.indexOf(u8, image_path, ":vztmpl/") != null or
                std.mem.endsWith(u8, image_path, ".tar.zst");
            if (!is_template) {
                if (self.logger) |log| {
                    log.err("--node {s} needs a template that node can read, named <storage>:vztmpl/<file>. An OCI bundle is packed into a template on this host, and a registry image is pulled to this host, so neither reaches {s} unless the storage is shared", .{ node, node }) catch {};
                }
                return core.Error.UnsupportedOperation;
            }

            // A ZFS rootfs is a dataset in this host's pool. The container
            // would be created there with a rootfs it cannot reach.
            if (self.zfs_mgr.isZFSAvailable()) {
                if (self.logger) |log| {
                    log.err("--node {s} cannot be used with a ZFS rootfs: the dataset would be created in this host's pool. Configure a storage both nodes can use", .{node}) catch {};
                }
                return core.Error.UnsupportedOperation;
            }

            // Before a VMID is taken, and with a message that names the node.
            try self.pve_client.requireTemplateOnNode(node, image_path);
        }

        // 1. Process image / template
        var template_name: ?[]const u8 = null;
        defer if (template_name) |tname| self.allocator.free(tname);

        var oci_bundle_path: ?[]const u8 = null;
        defer if (oci_bundle_path) |bp| self.allocator.free(bp);
        var bundle_config: ?bundle.OciBundleConfig = null;
        defer if (bundle_config) |*bc| bc.deinit();
        // The archive packed from a bundle's rootfs is needed only by pct create
        var bundle_template: ?oci.BundleTemplate = null;
        defer if (bundle_template) |*bt| bt.remove(self.allocator);

        if (config.image) |image_path| {
            const is_proxmox_template = std.mem.endsWith(u8, image_path, ".tar.zst") or
                std.mem.indexOf(u8, image_path, ":vztmpl/") != null;
            const is_registry_ref = std.mem.indexOf(u8, image_path, ":") != null and
                !is_proxmox_template and !std.fs.path.isAbsolute(image_path);

            if (is_registry_ref) {
                // Only Proxmox VE 9.1+ can pull OCI images. On older hosts a
                // registry reference used to fall through to bundle-path
                // validation and fail as a usage error, saying nothing about
                // the version.
                if (!try self.pve_client.supportsOciRegistryPull()) {
                    if (self.logger) |log| log.err("'{s}' is a registry image; pulling OCI images needs Proxmox VE 9.1 or later. Use a template (local:vztmpl/...) or an OCI bundle directory", .{image_path}) catch {};
                    return core.Error.UnsupportedOperation;
                }
                const storage = "local";
                const pulled = try self.pve_client.pullOciImage(image_path, storage);
                template_name = try self.allocator.dupe(u8, pulled);
                self.allocator.free(pulled);
            }

            if (template_name == null) {
                const is_tar = std.mem.endsWith(u8, image_path, ".tar.zst");
                const has_vztmpl = std.mem.indexOf(u8, image_path, ":vztmpl/") != null;
                if (is_tar or has_vztmpl) {
                    template_name = try self.allocator.dupe(u8, image_path);
                } else {
                    // OCI Bundle processing
                    const safe_path = core.validation.PathSecurity.validateBundlePath(image_path, self.allocator) catch |err| {
                        if (err == core.Error.ValidationError) {
                            if (self.logger) |log| log.err("OCI bundle '{s}' must be an absolute path", .{image_path}) catch {};
                        }
                        return err;
                    };
                    oci_bundle_path = safe_path;

                    var bundle_parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
                    // BundleError is not part of core.Error, the set the
                    // command registry casts every error into: a bundle
                    // without config.json crashed nexcage with "panic:
                    // invalid error code".
                    bundle_config = bundle_parser.parseBundle(safe_path) catch |err| {
                        if (err == error.OutOfMemory) return core.Error.OutOfMemory;
                        if (self.logger) |log| log.err("'{s}' is not a usable OCI bundle ({s}); it needs config.json and rootfs/", .{ safe_path, @errorName(err) }) catch {};
                        return core.Error.InvalidInput;
                    };

                    // pct creates containers only from templates. This used to
                    // hand pct a template name that nothing had written.
                    bundle_template = try self.oci_processor.createTemplateFromBundle(bundle_config.?.rootfs_path, config.name);
                    template_name = try self.allocator.dupe(u8, bundle_template.?.volid);
                }
            }
        }

        // 2. Take the next free VMID from the cluster
        const vmid = try self.pve_client.nextVmid();
        defer self.allocator.free(vmid);

        // 3. Resolve final template string
        var final_template: []const u8 = undefined;
        if (template_name) |tname| {
            if (std.mem.indexOf(u8, tname, ":") != null) {
                final_template = try self.allocator.dupe(u8, tname);
            } else if (std.mem.endsWith(u8, tname, ".tar.zst")) {
                // A bare template file name or a path into the template cache.
                // The extension used to be appended again: "x.tar.zst.tar.zst".
                final_template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{std.fs.path.basename(tname)});
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

        // The options after this are the same either way -- `pct create` and the
        // API take the same names -- so only the front of the command differs.
        var api_path: ?[]u8 = null;
        defer if (api_path) |ap| self.allocator.free(ap);
        if (target_node) |node| {
            api_path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/lxc", .{node});
            try args_builder.appendSlice(&[_][]const u8{ "pvesh", "create", api_path.?, "--vmid", vmid, "--ostemplate", final_template, "--hostname", config.name });
        } else {
            try args_builder.appendSlice(&[_][]const u8{ "pct", "create", vmid, final_template, "--hostname", config.name });
        }

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
        // Unprivileged unless the config says otherwise, as in the Proxmox VE
        // web UI. This used to default to privileged.
        const unprivileged = self.config.default_unprivileged orelse true;
        const is_oci = std.mem.endsWith(u8, final_template, ".tar") and !std.mem.endsWith(u8, final_template, ".tar.zst");
        if (!is_oci) {
            // pct detects the OS type from the template, so only pass one that
            // was configured; "ubuntu" was forced here for every template.
            if (self.config.default_ostype) |ostype| try args_builder.appendSlice(&[_][]const u8{ "--ostype", ostype });
            try args_builder.appendSlice(&[_][]const u8{ "--unprivileged", if (unprivileged) "1" else "0" });
        } else if (unprivileged) {
            try args_builder.appendSlice(&[_][]const u8{ "--unprivileged", "1" });
        } else {
            // pct rejects --unprivileged 0 for OCI images
            if (self.logger) |log| log.warn("OCI images always run unprivileged; ignoring proxmox.unprivileged=false", .{}) catch {};
        }

        if (zfs_dataset) |ds| {
            try args_builder.appendSlice(&[_][]const u8{ "--rootfs", ds });
        } else if (self.config.default_storage) |storage| {
            // A new volume on a Proxmox storage is "<storage>:<size in GiB>"
            const rootfs = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ storage, self.config.rootfs_size_gb orelse core.constants.DEFAULT_ROOTFS_SIZE_GB });
            try allocated_args.append(rootfs);
            try args_builder.appendSlice(&[_][]const u8{ "--rootfs", rootfs });
        }

        // 6. Execute create
        const result = try common.runCommand(self.allocator, self.logger, args_builder.items);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        // Any non-zero exit is a failure. Output containing "already exists"
        // used to be let through, reporting success for a container that was
        // never created.
        if (result.exit_code != 0) {
            if (zfs_dataset) |ds| {
                const failed = try std.mem.concat(self.allocator, u8, &.{ ds, "-failed" });
                defer self.allocator.free(failed);
                _ = common.runCommand(self.allocator, self.logger, &.{ "zfs", "rename", "-r", ds, failed }) catch {};
            }
            return self.pve_client.mapPctError(result.stderr);
        }

        // 7. Post-creation setup
        if (oci_bundle_path) |bp| {
            try self.applyMountsToLxcConfig(vmid, bp);
            // Only a bundle with mounts can have mp entries to look for; every
            // other bundle logged "No mp entries visible" on create.
            const has_mounts = if (bundle_config) |bc| (if (bc.mounts) |m| m.len > 0 else false) else false;
            if (has_mounts) try self.verifyMountsInConfig(vmid);
            if (bundle_config) |bc| {
                if (bc.namespaces) |ns| try self.applyNamespacesToLxcConfig(vmid, ns);
            }
        }

        const bundle_ptr: ?*const bundle.OciBundleConfig = if (bundle_config) |*bc| bc else null;
        try self.persistRuntimeMetadata(config.name, vmid, bundle_ptr, net_runtime.items);
        try self.writeOciState(config.name, "created", 0, oci_bundle_path);

        if (target_node) |node| {
            if (self.logger) |log| log.info("Proxmox LXC container created on node {s}: {s} (vmid {s})", .{ node, config.name, vmid }) catch {};
        } else {
            if (self.logger) |log| log.info("Proxmox LXC container created: {s} (vmid {s})", .{ config.name, vmid }) catch {};
        }
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

        const state_dir = core.state_root.get();
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
        try core.json.writeString(&writer, vmid);

        if (intel_has_data) {
            const intel = intel_cfg.?;
            try writer.writeAll(",\n  \"intelRdt\": {\n");
            var field_written = false;
            if (intel.clos_id) |clos| {
                try writer.writeAll("    \"closID\": ");
                try core.json.writeString(&writer, clos);
                field_written = true;
            }
            if (intel.schemata) |schemata| if (schemata.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"schemata\": [");
                for (schemata, 0..) |entry, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try core.json.writeString(&writer, entry);
                }
                try writer.writeAll("]");
                field_written = true;
            };
            if (intel.l3_cache_schema) |schema| if (schema.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"l3CacheSchema\": ");
                try core.json.writeString(&writer, schema);
                field_written = true;
            };
            if (intel.mem_bw_schema) |schema| if (schema.len > 0) {
                if (field_written) try writer.writeAll(",\n");
                try writer.writeAll("    \"memBwSchema\": ");
                try core.json.writeString(&writer, schema);
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
                try core.json.writeString(&writer, device.alias);
                try writer.writeAll(",\n      \"bridge\": ");
                try core.json.writeString(&writer, device.bridge);
                if (device.host_name) |host| {
                    try writer.writeAll(",\n      \"hostName\": ");
                    try core.json.writeString(&writer, host);
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

        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();

        try self.pve_client.start(loc.vmid, loc.remote());

        const init_pid = (self.pve_client.initPid(loc.vmid, loc.remote()) catch null) orelse 0;
        const kept_bundle = self.persistedBundle(container_id);
        defer if (kept_bundle) |b| self.allocator.free(b);
        self.writeOciState(container_id, "running", init_pid, kept_bundle) catch {};
    }

    /// Stop LXC container using pct command
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping Proxmox LXC container: {s}", .{container_id});
        }

        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();

        try self.pve_client.stop(loc.vmid, loc.remote());
        const kept_bundle = self.persistedBundle(container_id);
        defer if (kept_bundle) |b| self.allocator.free(b);
        self.writeOciState(container_id, "stopped", 0, kept_bundle) catch {};
    }

    /// Delete LXC container using pct command
    pub fn delete(self: *Self, container_id: []const u8, force: bool) !void {
        if (self.logger) |log| {
            try log.info("Deleting Proxmox LXC container: {s}", .{container_id});
        }

        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();
        const vmid = loc.vmid;

        // `pct destroy` refuses a running container. With --force, stop it
        // first, as `runc delete --force` does; a container engine sends that
        // when it has given up waiting for a clean shutdown.
        if (force) {
            // On another node there is no PID here to look at, so the stop is
            // sent unconditionally: shutdown on a stopped container is a no-op
            // the API accepts, and the alternative is refusing --force for a
            // container the cluster can perfectly well stop.
            if (!loc.local or (self.pve_client.initPid(vmid, loc.remote()) catch null) != null) {
                if (self.logger) |log| log.info("Stopping {s} before delete (--force)", .{container_id}) catch {};
                self.pve_client.stop(vmid, loc.remote()) catch |err| {
                    if (self.logger) |log| log.warn("forced stop of {s} failed: {s}", .{ container_id, @errorName(err) }) catch {};
                };
            }
        }

        try self.pve_client.delete(vmid, loc.remote());

        // Drop the state nexcage persisted for this container. The name matched
        // a pct hostname, but never let it address anything above the state root.
        if (std.mem.indexOfScalar(u8, container_id, '/') == null and
            !std.mem.eql(u8, container_id, ".") and !std.mem.eql(u8, container_id, ".."))
        {
            const state_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ core.state_root.get(), container_id });
            defer self.allocator.free(state_path);
            std.fs.cwd().deleteTree(state_path) catch {};
        }

        // ZFS cleanup if needed (renaming with -delete suffix was a specific feature)
        if (self.config.zfs_pool) |pool| {
            const dataset_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ pool, container_id, vmid });
            defer self.allocator.free(dataset_name);
            const delete_name = try std.mem.concat(self.allocator, u8, &.{ dataset_name, "-delete" });
            defer self.allocator.free(delete_name);
            _ = common.runCommand(self.allocator, self.logger, &.{ "zfs", "rename", "-r", dataset_name, delete_name }) catch {};
        }
    }

    /// Freeze the container's processes, and thaw them again.
    pub fn pause(self: *Self, container_id: []const u8) !void {
        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();
        try self.pve_client.freeze(loc.vmid, true, loc.remote());
        const kept = self.persistedBundle(container_id);
        defer if (kept) |b| self.allocator.free(b);
        self.writeOciState(container_id, "paused", 0, kept) catch {};
    }

    pub fn unpause(self: *Self, container_id: []const u8) !void {
        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();
        try self.pve_client.freeze(loc.vmid, false, loc.remote());
        const init_pid = (self.pve_client.initPid(loc.vmid, loc.remote()) catch null) orelse 0;
        const kept = self.persistedBundle(container_id);
        defer if (kept) |b| self.allocator.free(b);
        self.writeOciState(container_id, "running", init_pid, kept) catch {};
    }

    /// Whether the container's processes are frozen. `pct status` cannot answer
    /// this -- Proxmox has no notion of the state -- so `state` reads the
    /// cgroup.
    pub fn isFrozen(self: *Self, vmid: []const u8) ?bool {
        return self.pve_client.isFrozen(vmid);
    }

    /// Send a signal to the container's init process from the host
    pub fn kill(self: *Self, container_id: []const u8, signal: []const u8) !void {
        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();
        try self.pve_client.kill(loc.vmid, signal, loc.remote());
    }

    /// Run a command inside the container; returns the status it exited with
    pub fn exec(self: *Self, container_id: []const u8, argv: []const []const u8) !u8 {
        var loc = try self.resolveLocation(container_id);
        defer loc.deinit();
        return self.pve_client.exec(loc.vmid, argv, loc.remote());
    }

    /// Host PID of the container's init, or null when it is not running
    /// Host PID of a container's init on **this** host. `state` asks for it by
    /// VMID, which carries no node, so a container elsewhere in the cluster is
    /// reported without a PID rather than with one from the wrong machine.
    pub fn initPid(self: *Self, vmid: []const u8) !?std.posix.pid_t {
        return self.pve_client.initPid(vmid, null);
    }

    /// List LXC containers using pct command
    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        return self.pve_client.list(allocator);
    }

    /// The bundle path this container was created from, as the last state
    /// write recorded it, or null. start and stop rewrite the state file, and
    /// an OCI caller reads `bundle` back from `state` after both.
    fn persistedBundle(self: *Self, container_id: []const u8) ?[]u8 {
        if (std.mem.indexOfScalar(u8, container_id, '/') != null) return null;
        const path = std.fmt.allocPrint(self.allocator, "{s}/{s}/state.json", .{ core.state_root.get(), container_id }) catch return null;
        defer self.allocator.free(path);
        const data = std.fs.cwd().readFileAlloc(self.allocator, path, 64 * 1024) catch return null;
        defer self.allocator.free(data);
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, data, .{}) catch return null;
        defer parsed.deinit();
        if (parsed.value != .object) return null;
        const value = parsed.value.object.get("bundle") orelse return null;
        if (value != .string) return null;
        return self.allocator.dupe(u8, value.string) catch null;
    }

    fn writeOciState(self: *Self, container_id: []const u8, status: []const u8, pid: i32, bundle_path: ?[]const u8) !void {
        const state_dir = core.state_root.get();
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
        try core.json.writeString(writer, container_id);
        try writer.print(",\n  \"status\": \"{s}\",\n  \"pid\": {d},\n  \"bundle\": ", .{ status, pid });
        if (bundle_path) |bp| try core.json.writeString(writer, bp) else try writer.writeAll("null");
        try writer.writeAll(",\n  \"annotations\": {}\n}\n");

        try file.writeAll(json_buf.items);
    }

    /// The node nexcage is running on. `state` needs it to tell a container
    /// here from one on another node of the cluster, where a host PID would
    /// mean nothing.
    pub fn nodeName(self: *Self) ![]const u8 {
        return self.pve_client.getNodeName();
    }

    /// The templates the cluster can create from; `only_node` narrows it.
    /// Distinct from `listTemplates`, which reads this host's template cache.
    pub fn listClusterTemplates(self: *Self, allocator: std.mem.Allocator, only_node: ?[]const u8) ![]pve.PveClient.Template {
        return self.pve_client.listTemplates(allocator, only_node);
    }

    /// Pull an OCI image into a storage on a node, answering with the volid.
    pub fn pullTemplate(
        self: *Self,
        allocator: std.mem.Allocator,
        node: []const u8,
        storage: []const u8,
        reference: []const u8,
        filename: ?[]const u8,
    ) ![]u8 {
        return self.pve_client.pullTemplate(allocator, node, storage, reference, filename);
    }

    pub fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        return self.pve_client.getVmidByName(name);
    }

    /// Name → where the container is, for commands that act on an existing
    /// one. Looks across the cluster, so a container on another node resolves
    /// instead of being reported as missing; the not-found case is logged under
    /// the name the user typed.
    fn resolveLocation(self: *Self, container_id: []const u8) !pve.PveClient.Location {
        return self.pve_client.locate(self.allocator, container_id) catch |err| {
            if (err == core.Error.NotFound) {
                if (self.logger) |log| log.err("Container '{s}' not found on any node", .{container_id}) catch {};
            }
            return err;
        };
    }

    /// Name → VMID for commands that act on an existing container, with the
    /// not-found case logged under the name the user typed.
    fn resolveVmid(self: *Self, container_id: []const u8) ![]u8 {
        return self.pve_client.getVmidByName(container_id) catch |err| {
            if (err == core.Error.NotFound) {
                if (self.logger) |log| log.err("Container '{s}' not found", .{container_id}) catch {};
            }
            return err;
        };
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
