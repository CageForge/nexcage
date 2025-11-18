const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const oci_bundle = @import("oci_bundle.zig");
const image_converter = @import("image_converter.zig");
const template_manager = @import("template_manager.zig");

/// Result of running a command
const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

const NetDeviceRuntimeInfo = struct {
    alias: []const u8,
    bridge: []const u8,
    host_name: ?[]const u8 = null,
};

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
    zfs_pool: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, config: core.types.ProxmoxLxcBackendConfig) !*Self {
        const driver = try allocator.alloc(Self, 1);

        // Initialize template manager with cache directory
        const cache_dir = "/tmp/nexcage-template-cache";
        const template_mgr = template_manager.TemplateManager.init(allocator, null, cache_dir);

        driver[0] = Self{
            .allocator = allocator,
            .config = config,
            .template_manager = template_mgr,
            .zfs_pool = blk: {
                if (config.zfs_pool) |p| break :blk try allocator.dupe(u8, p);
                break :blk try allocator.dupe(u8, "tank/containers");
            },
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.template_manager.deinit();
        if (self.zfs_pool) |pool| {
            self.allocator.free(pool);
        }
        self.allocator.destroy(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Set debug mode
    pub fn setDebugMode(self: *Self, debug_mode: bool) void {
        self.debug_mode = debug_mode;
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
        const args = [_][]const u8{ "zfs", "version" };
        const res = self.runCommand(&args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        return res.exit_code == 0;
    }

    /// Check if ZFS pool exists
    fn poolExists(self: *Self, pool_name: []const u8) bool {
        // pool_name should already be just the pool name (e.g., "tank", "rpool")
        const args = [_][]const u8{ "zpool", "list", "-H", "-o", "name", pool_name };
        const res = self.runCommand(&args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        // Check if pool name appears in output (should be exact match on a line)
        if (res.exit_code != 0) return false;
        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.eql(u8, trimmed, pool_name)) {
                return true;
            }
        }
        return false;
    }

    /// Check if ZFS dataset exists
    fn datasetExists(self: *Self, dataset_name: []const u8) bool {
        const args = [_][]const u8{ "zfs", "list", "-H", "-o", "name", dataset_name };
        const res = self.runCommand(&args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        // Check if dataset name appears in output
        return res.exit_code == 0 and std.mem.indexOf(u8, res.stdout, dataset_name) != null;
    }

    /// Get parent dataset path from full dataset path
    fn getParentDataset(self: *Self, dataset_name: []const u8) ?[]const u8 {
        _ = self;
        // Find last '/' to get parent
        if (std.mem.lastIndexOf(u8, dataset_name, "/")) |idx| {
            return dataset_name[0..idx];
        }
        return null;
    }

    /// Check minimal ZFS version compatibility (best-effort)
    fn isZfsCompatible(self: *Self, min_major: u32, min_minor: u32) bool {
        const args = [_][]const u8{ "zfs", "version" };
        const res = self.runCommand(&args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return false;
        // Parse like: "zfs-2.2.2-1\nzfs-kmod-2.2.2-1"
        var it = std.mem.splitScalar(u8, res.stdout, '\n');
        while (it.next()) |line| {
            if (std.mem.indexOf(u8, line, "zfs-") != null) {
                if (std.mem.indexOfScalar(u8, line, '-')) |dash_idx| {
                    const v = line[dash_idx + 1 ..];
                    // take major.minor
                    var dot = std.mem.splitScalar(u8, v, '.');
                    const maj_s = dot.next() orelse continue;
                    const min_s = dot.next() orelse continue;
                    const maj = std.fmt.parseInt(u32, maj_s, 10) catch continue;
                    const min = std.fmt.parseInt(u32, min_s, 10) catch continue;
                    if (maj > min_major or (maj == min_major and min >= min_minor)) return true;
                }
            }
        }
        return false;
    }

    /// Set ZFS pool for containers
    pub fn setZFSPool(self: *Self, pool: []const u8) !void {
        if (self.zfs_pool) |old_pool| {
            self.allocator.free(old_pool);
        }
        self.zfs_pool = try self.allocator.dupe(u8, pool);
    }

    /// Create ZFS dataset for container
    pub fn createContainerDataset(self: *Self, container_name: []const u8, vmid: []const u8) !?[]const u8 {
        const stderr = std.fs.File.stderr();
        stderr.writeAll("[DRIVER] createContainerDataset: ENTRY\n") catch {};
        stderr.writeAll("[DRIVER] createContainerDataset: container_name = '") catch {};
        stderr.writeAll(container_name) catch {};
        stderr.writeAll("', vmid = '") catch {};
        stderr.writeAll(vmid) catch {};
        stderr.writeAll("'\n") catch {};

        stderr.writeAll("[DRIVER] createContainerDataset: Checking ZFS availability and pool\n") catch {};
        const zfs_avail = self.isZFSAvailable();
        const pool_set = self.zfs_pool != null;
        stderr.writeAll("[DRIVER] createContainerDataset: zfs_avail = ") catch {};
        if (zfs_avail) {
            stderr.writeAll("true") catch {};
        } else {
            stderr.writeAll("false") catch {};
        }
        stderr.writeAll(", pool_set = ") catch {};
        if (pool_set) {
            stderr.writeAll("true\n") catch {};
        } else {
            stderr.writeAll("false\n") catch {};
        }

        if (!zfs_avail or !pool_set) {
            stderr.writeAll("[DRIVER] createContainerDataset: ZFS not available or pool not set, returning null\n") catch {};
            // Skip logger to avoid segfault
            // if (self.logger) |log| log.warn("ZFS not available, skipping dataset creation", .{}) catch {};
            return null;
        }

        stderr.writeAll("[DRIVER] createContainerDataset: Getting pool value\n") catch {};
        const pool_config = self.zfs_pool.?;
        stderr.writeAll("[DRIVER] createContainerDataset: pool_config = '") catch {};
        stderr.writeAll(pool_config) catch {};
        stderr.writeAll("'\n") catch {};

        // Extract pool name from config (e.g., "tank" from "tank/containers" or just "tank")
        const pool_name: []const u8 = if (std.mem.indexOf(u8, pool_config, "/")) |idx| pool_config[0..idx] else pool_config;
        stderr.writeAll("[DRIVER] createContainerDataset: Extracted pool_name = '") catch {};
        stderr.writeAll(pool_name) catch {};
        stderr.writeAll("'\n") catch {};

        // Verify pool exists
        stderr.writeAll("[DRIVER] createContainerDataset: Checking if pool exists\n") catch {};
        if (!self.poolExists(pool_name)) {
            stderr.writeAll("[DRIVER] createContainerDataset: Pool does not exist, returning null\n") catch {};
            return null;
        }
        stderr.writeAll("[DRIVER] createContainerDataset: Pool exists\n") catch {};

        // Create dataset name: use pool_config as base if it contains path, otherwise use pool_name/containers
        // If pool_config is "tank/containers", use it directly, otherwise use "pool_name/containers"
        const base_path: []const u8 = if (std.mem.indexOf(u8, pool_config, "/")) |_| pool_config else try std.fmt.allocPrint(self.allocator, "{s}/containers", .{pool_name});
        defer if (base_path.ptr != pool_config.ptr) self.allocator.free(base_path);

        stderr.writeAll("[DRIVER] createContainerDataset: base_path = '") catch {};
        stderr.writeAll(base_path) catch {};
        stderr.writeAll("'\n") catch {};

        // Create dataset name: base_path/container_name-vmid
        stderr.writeAll("[DRIVER] createContainerDataset: Creating dataset name\n") catch {};
        const dataset_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ base_path, container_name, vmid });
        defer self.allocator.free(dataset_name);
        stderr.writeAll("[DRIVER] createContainerDataset: dataset_name = '") catch {};
        stderr.writeAll(dataset_name) catch {};
        stderr.writeAll("'\n") catch {};

        // Check if dataset already exists
        stderr.writeAll("[DRIVER] createContainerDataset: Checking if dataset already exists\n") catch {};
        if (self.datasetExists(dataset_name)) {
            stderr.writeAll("[DRIVER] createContainerDataset: Dataset already exists, returning existing name\n") catch {};
            // Return existing dataset name
            return try self.allocator.dupe(u8, dataset_name);
        }
        stderr.writeAll("[DRIVER] createContainerDataset: Dataset does not exist, will create\n") catch {};

        // Check if parent dataset exists, create if missing
        if (self.getParentDataset(dataset_name)) |parent_dataset| {
            stderr.writeAll("[DRIVER] createContainerDataset: Checking parent dataset: '") catch {};
            stderr.writeAll(parent_dataset) catch {};
            stderr.writeAll("'\n") catch {};

            if (!self.datasetExists(parent_dataset)) {
                stderr.writeAll("[DRIVER] createContainerDataset: Parent dataset does not exist, creating\n") catch {};
                const parent_args = [_][]const u8{ "zfs", "create", "-p", parent_dataset };
                const parent_res = self.runCommand(&parent_args) catch {
                    stderr.writeAll("[DRIVER] createContainerDataset: Failed to create parent dataset\n") catch {};
                    return null;
                };
                defer {
                    self.allocator.free(parent_res.stdout);
                    self.allocator.free(parent_res.stderr);
                }

                if (parent_res.exit_code != 0) {
                    stderr.writeAll("[DRIVER] createContainerDataset: Parent dataset creation failed, stderr = '") catch {};
                    stderr.writeAll(parent_res.stderr) catch {};
                    stderr.writeAll("'\n") catch {};
                    return null;
                }
                stderr.writeAll("[DRIVER] createContainerDataset: Parent dataset created successfully\n") catch {};
            } else {
                stderr.writeAll("[DRIVER] createContainerDataset: Parent dataset exists\n") catch {};
            }
        }

        // Skip logger to avoid segfault
        // if (self.logger) |log| log.info("Creating ZFS dataset for container: {s}", .{dataset_name}) catch {};
        stderr.writeAll("[DRIVER] createContainerDataset: Logger skipped\n") catch {};

        // Create the dataset
        stderr.writeAll("[DRIVER] createContainerDataset: Before zfs create command\n") catch {};
        {
            const args = [_][]const u8{ "zfs", "create", dataset_name };
            stderr.writeAll("[DRIVER] createContainerDataset: Executing zfs create\n") catch {};
            const res = try self.runCommand(&args);
            stderr.writeAll("[DRIVER] createContainerDataset: zfs create command returned\n") catch {};
            stderr.writeAll("[DRIVER] createContainerDataset: res.stdout len = ") catch {};
            const stdout_len_str = try std.fmt.allocPrint(self.allocator, "{d}", .{res.stdout.len});
            defer self.allocator.free(stdout_len_str);
            stderr.writeAll(stdout_len_str) catch {};
            stderr.writeAll(", res.stderr len = ") catch {};
            const stderr_len_str = try std.fmt.allocPrint(self.allocator, "{d}", .{res.stderr.len});
            defer self.allocator.free(stderr_len_str);
            stderr.writeAll(stderr_len_str) catch {};
            stderr.writeAll("\n") catch {};

            if (res.stderr.len > 0) {
                stderr.writeAll("[DRIVER] createContainerDataset: zfs stderr = '") catch {};
                stderr.writeAll(res.stderr) catch {};
                stderr.writeAll("'\n") catch {};
            }

            stderr.writeAll("[DRIVER] createContainerDataset: res.exit_code = ") catch {};
            const exit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{res.exit_code});
            defer self.allocator.free(exit_str);
            stderr.writeAll(exit_str) catch {};
            stderr.writeAll("\n") catch {};
            defer self.allocator.free(res.stdout);
            defer self.allocator.free(res.stderr);
            stderr.writeAll("[DRIVER] createContainerDataset: Before exit_code check\n") catch {};
            if (res.exit_code != 0) {
                stderr.writeAll("[DRIVER] createContainerDataset: zfs create failed, returning null (continuing without ZFS dataset)\n") catch {};
                // Return null to continue without ZFS dataset instead of failing
                return null;
            }
            stderr.writeAll("[DRIVER] createContainerDataset: zfs create succeeded\n") catch {};
        }
        // Set compression and other properties
        {
            const args1 = [_][]const u8{ "zfs", "set", "compression=lz4", dataset_name };
            const res1 = try self.runCommand(&args1);
            defer self.allocator.free(res1.stdout);
            defer self.allocator.free(res1.stderr);
            if (res1.exit_code != 0) return core.Error.OperationFailed;
        }
        {
            const args2 = [_][]const u8{ "zfs", "set", "atime=off", dataset_name };
            const res2 = try self.runCommand(&args2);
            defer self.allocator.free(res2.stdout);
            defer self.allocator.free(res2.stderr);
            if (res2.exit_code != 0) return core.Error.OperationFailed;
        }
        {
            const args3 = [_][]const u8{ "zfs", "set", "sync=disabled", dataset_name };
            const res3 = try self.runCommand(&args3);
            defer self.allocator.free(res3.stdout);
            defer self.allocator.free(res3.stderr);
            if (res3.exit_code != 0) return core.Error.OperationFailed;
        }

        if (self.logger) |log| log.info("Successfully created ZFS dataset: {s}", .{dataset_name}) catch {};

        // Return the dataset name (caller should free it)
        return try self.allocator.dupe(u8, dataset_name);
    }

    /// Destroy ZFS dataset for container
    pub fn destroyContainerDataset(self: *Self, dataset_name: []const u8) !void {
        if (!self.isZFSAvailable()) {
            if (self.logger) |log| log.warn("ZFS not available, skipping dataset destruction", .{}) catch {};
            return;
        }

        if (self.logger) |log| log.info("Destroying ZFS dataset: {s}", .{dataset_name}) catch {};

        const args = [_][]const u8{ "zfs", "destroy", "-r", dataset_name };
        const res = try self.runCommand(&args);
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return core.Error.OperationFailed;

        if (self.logger) |log| log.info("Successfully destroyed ZFS dataset: {s}", .{dataset_name}) catch {};
    }

    /// Get ZFS dataset mountpoint for container
    pub fn getContainerDatasetMountpoint(self: *Self, dataset_name: []const u8) !?[]const u8 {
        if (!self.isZFSAvailable()) {
            return null;
        }

        const args = [_][]const u8{ "zfs", "get", "-H", "-o", "value", "mountpoint", dataset_name };
        const res = try self.runCommand(&args);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return null;
        const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
        const mount = try self.allocator.dupe(u8, trimmed);
        self.allocator.free(res.stdout);
        return mount;
    }

    /// Process OCI bundle - convert to template if needed, return template name
    fn processOciBundle(self: *Self, bundle_path: []const u8, container_name: []const u8) !?[]const u8 {
        if (self.logger) |log| log.info("Processing OCI bundle: {s}", .{bundle_path}) catch {};
        if (self.logger) |log| log.info("Logger is working in processOciBundle", .{}) catch {};

        // Parse bundle to check if it's a standard OCI bundle
        var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        // Check if this bundle has an image reference that exists as a template
        const maybe_image = try self.parseBundleImageFromConfig(&cfg);
        if (maybe_image) |image_ref| {
            defer self.allocator.free(image_ref);

            // Check if template already exists
            if (try self.templateExists(image_ref)) {
                if (self.logger) |log| log.info("Using existing template: {s}", .{image_ref}) catch {};
                return image_ref;
            }
        }

        // If no existing template found, convert OCI bundle to template
        const template_name = try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ container_name, std.time.timestamp() });
        defer self.allocator.free(template_name);

        if (self.logger) |log| log.info("Converting OCI bundle to template: {s}", .{template_name}) catch {};

        var converter = image_converter.ImageConverter.init(self.allocator, self.logger);
        try converter.convertOciToProxmoxTemplate(bundle_path, template_name, "local");

        if (self.logger) |log| log.info("Successfully converted OCI bundle to template: {s}", .{template_name}) catch {};

        // Add template to cache with metadata
        var template_info = try template_manager.TemplateInfo.init(self.allocator, template_name, 0, // Size will be updated later
            .oci_bundle);
        errdefer template_info.deinit(self.allocator); // Cleanup on error

        // Extract metadata from OCI bundle if available
        var metadata_parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var metadata_cfg = metadata_parser.parseBundle(bundle_path) catch |err| {
            if (self.logger) |log| log.warn("Failed to parse bundle for metadata: {}", .{err}) catch {};
            // Add template without metadata
            try self.template_manager.addTemplate(template_name, template_info);
            return try self.allocator.dupe(u8, template_name);
        };
        defer metadata_cfg.deinit();

        // Create metadata from OCI bundle
        var metadata = template_manager.TemplateMetadata.init(self.allocator);
        errdefer metadata.deinit(self.allocator); // Cleanup metadata on error

        if (metadata_cfg.image_name) |name| metadata.image_name = try self.allocator.dupe(u8, name);
        if (metadata_cfg.image_tag) |tag| metadata.image_tag = try self.allocator.dupe(u8, tag);
        if (metadata_cfg.entrypoint) |ep| {
            var entrypoint_array = try self.allocator.alloc([]const u8, ep.len);
            errdefer {
                for (entrypoint_array[0..]) |arg| self.allocator.free(arg);
                self.allocator.free(entrypoint_array);
            }
            for (ep, 0..) |arg, i| {
                entrypoint_array[i] = try self.allocator.dupe(u8, arg);
            }
            metadata.entrypoint = entrypoint_array;
        }
        if (metadata_cfg.cmd) |cmd| {
            var cmd_array = try self.allocator.alloc([]const u8, cmd.len);
            errdefer {
                for (cmd_array[0..]) |arg| self.allocator.free(arg);
                self.allocator.free(cmd_array);
            }
            for (cmd, 0..) |arg, i| {
                cmd_array[i] = try self.allocator.dupe(u8, arg);
            }
            metadata.cmd = cmd_array;
        }
        if (metadata_cfg.working_directory) |wd| metadata.working_directory = try self.allocator.dupe(u8, wd);

        if (metadata_cfg.intel_rdt) |intel| {
            var intel_meta = template_manager.TemplateMetadata.IntelRdtMetadata{};
            if (intel.clos_id) |clos| intel_meta.clos_id = try self.allocator.dupe(u8, clos);
            if (intel.l3_cache_schema) |schema| intel_meta.l3_cache_schema = try self.allocator.dupe(u8, schema);
            if (intel.mem_bw_schema) |schema| intel_meta.mem_bw_schema = try self.allocator.dupe(u8, schema);
            intel_meta.enable_monitoring = intel.enable_monitoring;
            if (intel.schemata) |schemata| {
                var schemata_array = try self.allocator.alloc([]const u8, schemata.len);
                errdefer {
                    for (schemata_array) |entry| if (entry.len > 0) self.allocator.free(entry);
                    self.allocator.free(schemata_array);
                }
                for (schemata, 0..) |entry, i| {
                    schemata_array[i] = try self.allocator.dupe(u8, entry);
                }
                intel_meta.schemata = schemata_array;
            }
            metadata.intel_rdt = intel_meta;
        }

        if (metadata_cfg.net_devices) |devices| {
            var device_meta = try self.allocator.alloc(template_manager.TemplateMetadata.NetDeviceMetadata, devices.len);
            errdefer {
                for (device_meta) |dev| {
                    if (dev.alias.len > 0) self.allocator.free(dev.alias);
                    if (dev.bridge.len > 0) self.allocator.free(dev.bridge);
                    if (dev.host_name) |name| if (name.len > 0) self.allocator.free(name);
                }
                self.allocator.free(device_meta);
            }
            for (devices, 0..) |device, i| {
                device_meta[i] = .{};
                device_meta[i].alias = try self.allocator.dupe(u8, device.alias);
                // Interpret device.name as preferred host link; fallback to default bridge will happen during pct create
                const bridge_ref = device.name orelse (self.config.default_bridge orelse core.constants.DEFAULT_BRIDGE_NAME);
                device_meta[i].bridge = try self.allocator.dupe(u8, bridge_ref);
                if (device.name) |name| {
                    device_meta[i].host_name = try self.allocator.dupe(u8, name);
                }
            }
            metadata.net_devices = device_meta;
        }

        // Transfer ownership to template_info (metadata will be cleaned up via template_info.deinit)
        template_info.metadata = metadata;

        // addTemplate clones template_info, so we need to deinit the original
        // Note: addTemplate makes its own copies via clone(), so original must be cleaned up
        defer template_info.deinit(self.allocator);

        try self.template_manager.addTemplate(template_name, template_info);

        // Return a copy since we're freeing the original
        return try self.allocator.dupe(u8, template_name);
    }

    /// Parse image reference from OCI bundle config
    fn parseBundleImageFromConfig(self: *Self, config: *const oci_bundle.OciBundleConfig) !?[]const u8 {
        if (config.annotations) |annotations| {
            if (annotations.get("org.opencontainers.image.ref.name")) |image_ref| {
                return try self.allocator.dupe(u8, image_ref.string);
            }
        }
        return null;
    }

    /// Create LXC container using pct command
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        const stderr = std.fs.File.stderr();
        const stdout = std.fs.File.stdout();

        // Use stderr for immediate output (unbuffered)
        stderr.writeAll("[DRIVER] create: ENTRY\n") catch {};
        stderr.writeAll("[DRIVER] create: container name = '") catch {};
        stderr.writeAll(config.name) catch {};
        stderr.writeAll("'\n") catch {};
        stderr.writeAll("[DRIVER] create: debug_mode = ") catch {};
        if (self.debug_mode) {
            stderr.writeAll("true\n") catch {};
        } else {
            stderr.writeAll("false\n") catch {};
        }

        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: Starting (detailed debug)\n");
            try stdout.writeAll("[DRIVER] create: container name = '");
            try stdout.writeAll(config.name);
            try stdout.writeAll("'\n");
        }

        stderr.writeAll("[DRIVER] create: Before logger check\n") catch {};

        // Use logger if available - with additional safety checks
        if (self.logger) |log| {
            const name = config.name;
            if (name.len > 0) {
                stderr.writeAll("[DRIVER] create: Checking logger validity\n") catch {};

                // Additional safety checks before calling logger
                // Check if allocator pointer is valid by trying to access it
                _ = log.allocator;
                stderr.writeAll("[DRIVER] create: Logger allocator check passed\n") catch {};

                // Check if file is valid
                _ = log.file;
                stderr.writeAll("[DRIVER] create: Logger file check passed\n") catch {};

                stderr.writeAll("[DRIVER] create: Calling logger.info\n") catch {};

                // Try to use logger with explicit error handling
                log.info("Creating Proxmox LXC container: {s}", .{name}) catch {
                    stderr.writeAll("[DRIVER] create: Logger.info failed with error\n") catch {};
                    // Continue execution even if logging fails
                };
                stderr.writeAll("[DRIVER] create: Logger.info completed\n") catch {};
            }
        } else {
            stderr.writeAll("[DRIVER] create: No logger available\n") catch {};
        }

        stderr.writeAll("[DRIVER] create: Processing image\n") catch {};

        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Processing image (detailed)\n");

        // Process bundle image if provided (bundle path with config.json)
        stderr.writeAll("[DRIVER] create: Initializing template_name variable\n") catch {};
        var template_name: ?[]const u8 = null;
        defer if (template_name) |tname| self.allocator.free(tname);

        // Keep track of original OCI bundle path for mounts and resources
        stderr.writeAll("[DRIVER] create: Initializing oci_bundle_path variable\n") catch {};
        var oci_bundle_path: ?[]const u8 = null;
        // Store parsed bundle config for resources and namespaces
        var bundle_config: ?oci_bundle.OciBundleConfig = null;
        defer if (bundle_config) |*bc| bc.deinit();

        stderr.writeAll("[DRIVER] create: Checking if config.image exists\n") catch {};
        if (config.image) |image_path| {
            stderr.writeAll("[DRIVER] create: Image provided: '") catch {};
            stderr.writeAll(image_path) catch {};
            stderr.writeAll("'\n") catch {};

            if (self.debug_mode) {
                try stdout.writeAll("[DRIVER] create: Image provided: '");
                try stdout.writeAll(image_path);
                try stdout.writeAll("'\n");
            }
            // Classify image type:
            // - Proxmox template if:
            //   a) ends with .tar.zst
            //   b) contains ":vztmpl/" (storage template path)
            // - Otherwise:
            //   c) treat as OCI bundle path if directory exists
            //   d) strings like "ubuntu:20.04" are NOT proxmox templates
            stderr.writeAll("[DRIVER] create: Checking image type\n") catch {};
            const is_tar = std.mem.endsWith(u8, image_path, ".tar.zst");
            const has_vztmpl = std.mem.indexOf(u8, image_path, ":vztmpl/") != null;
            const has_colon = std.mem.indexOf(u8, image_path, ":") != null;
            const has_slash = std.mem.indexOf(u8, image_path, "/") != null;
            const is_proxmox_template = is_tar or has_vztmpl;
            stderr.writeAll("[DRIVER] create: is_tar = ") catch {};
            if (is_tar) stderr.writeAll("true\n") catch {} else stderr.writeAll("false\n") catch {};
            stderr.writeAll("[DRIVER] create: has_vztmpl = ") catch {};
            if (has_vztmpl) stderr.writeAll("true\n") catch {} else stderr.writeAll("false\n") catch {};
            stderr.writeAll("[DRIVER] create: has_colon = ") catch {};
            if (has_colon) stderr.writeAll("true\n") catch {} else stderr.writeAll("false\n") catch {};
            stderr.writeAll("[DRIVER] create: has_slash = ") catch {};
            if (has_slash) stderr.writeAll("true\n") catch {} else stderr.writeAll("false\n") catch {};

            if (is_proxmox_template) {
                stderr.writeAll("[DRIVER] create: Image classified as Proxmox template\n") catch {};
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Image classified as Proxmox template\n");
                // It's a Proxmox template, use it directly
                stderr.writeAll("[DRIVER] create: Duplicating template name\n") catch {};
                template_name = try self.allocator.dupe(u8, image_path);
                stderr.writeAll("[DRIVER] create: Template name duplicated successfully\n") catch {};

                stderr.writeAll("[DRIVER] create: After template_name assignment, checking next step\n") catch {};
                stderr.writeAll("[DRIVER] create: template_name is set: ") catch {};
                if (template_name) |_| {
                    stderr.writeAll("yes\n") catch {};
                } else {
                    stderr.writeAll("no\n") catch {};
                }
            } else {
                stderr.writeAll("[DRIVER] create: Image is OCI bundle, processing\n") catch {};
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Image is OCI bundle, processing\n");
                // It's an OCI bundle - validate path boundaries and ensure directory exists
                const safe_bundle_path = core.validation.PathSecurity.validateBundlePath(image_path, self.allocator) catch |verr| {
                    if (self.logger) |log| log.err("Bundle path validation failed: {s} ({})", .{ image_path, verr }) catch {};
                    return core.Error.InvalidInput;
                };
                defer self.allocator.free(safe_bundle_path);
                var bundle_dir = std.fs.cwd().openDir(safe_bundle_path, .{}) catch |err| {
                    // If path is not a directory and looks like docker image ref (e.g., ubuntu:20.04),
                    // do NOT treat it as Proxmox template; return a clear error for now.
                    if (!is_proxmox_template and has_colon and !has_slash) {
                        if (self.logger) |log| log.err("Unsupported image reference: {s}. Use Proxmox template (.tar.zst or storage:vztmpl/...) or local OCI bundle directory.", .{image_path}) catch {};
                        return core.Error.InvalidConfig;
                    }
                    if (self.logger) |log| log.err("Bundle path not found: {s} ({})", .{ safe_bundle_path, err }) catch {};
                    if (self.debug_mode) {
                        try stdout.writeAll("[DRIVER] create: ERROR: Bundle path not found\n");
                    }
                    return core.Error.FileNotFound;
                };
                defer bundle_dir.close();
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Bundle directory opened\n");

                // Ensure config.json exists in the bundle
                bundle_dir.access("config.json", .{}) catch |err| {
                    if (self.logger) |log| log.err("config.json not found in bundle: {s} ({})", .{ image_path, err }) catch {};
                    if (self.debug_mode) {
                        try stdout.writeAll("[DRIVER] create: ERROR: config.json not found\n");
                    }
                    return core.Error.FileNotFound;
                };
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: config.json found in bundle\n");

                // Save OCI bundle path for mounts processing
                oci_bundle_path = safe_bundle_path;

                // Parse bundle config for resources and namespaces (before processing template)
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Parsing bundle config for resources\n");
                var bundle_parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
                const parsed_bundle_cfg = try bundle_parser.parseBundle(safe_bundle_path);
                // Note: We'll defer deinit after using it for resources/namespaces
                bundle_config = parsed_bundle_cfg;

                // Process OCI bundle - convert to template if needed
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Processing OCI bundle\n");
                template_name = try self.processOciBundle(safe_bundle_path, config.name);
                if (self.debug_mode) {
                    try stdout.writeAll("[DRIVER] create: OCI bundle processed, template_name set\n");
                }
            }
        } else {
            stderr.writeAll("[DRIVER] create: No image provided\n") catch {};
            if (self.debug_mode) try stdout.writeAll("[DRIVER] create: No image provided\n");
        }

        stderr.writeAll("[DRIVER] create: After image processing, before VMID generation\n") catch {};
        stderr.writeAll("[DRIVER] create: Generating VMID from name\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Generating VMID from name\n");

        // Generate VMID from name (Proxmox requires numeric vmid)
        stderr.writeAll("[DRIVER] create: Initializing hash\n") catch {};
        var hasher = std.hash.Wyhash.init(0);
        stderr.writeAll("[DRIVER] create: Updating hash with container name\n") catch {};
        stderr.writeAll("[DRIVER] create: container name = '") catch {};
        stderr.writeAll(config.name) catch {};
        stderr.writeAll("'\n") catch {};
        hasher.update(config.name);
        stderr.writeAll("[DRIVER] create: Getting hash final value\n") catch {};
        const vmid_num: u32 = @truncate(hasher.final());
        stderr.writeAll("[DRIVER] create: Calculating VMID\n") catch {};
        const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
        stderr.writeAll("[DRIVER] create: Allocating VMID string\n") catch {};
        const vmid = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
        defer self.allocator.free(vmid);
        stderr.writeAll("[DRIVER] create: VMID allocated: ") catch {};
        stderr.writeAll(vmid) catch {};
        stderr.writeAll("\n") catch {};

        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: VMID calculated: ");
            try stdout.writeAll(vmid);
            try stdout.writeAll("\n");
        }

        // Validate VMID uniqueness - check if container with this VMID already exists
        stderr.writeAll("[DRIVER] create: Checking VMID uniqueness\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Checking VMID uniqueness\n");

        stderr.writeAll("[DRIVER] create: Before vmidExists call\n") catch {};
        const vmid_exists = try self.vmidExists(vmid);
        stderr.writeAll("[DRIVER] create: After vmidExists call, result = ") catch {};
        if (vmid_exists) {
            stderr.writeAll("true\n") catch {};
        } else {
            stderr.writeAll("false\n") catch {};
        }

        if (vmid_exists) {
            if (self.logger) |log| {
                log.err("Container with VMID {s} already exists. Try a different container name.", .{vmid}) catch {};
            }
            if (self.debug_mode) {
                try stdout.writeAll("[DRIVER] create: ERROR: VMID already exists\n");
            }
            stderr.writeAll("[DRIVER] create: ERROR: VMID already exists\n") catch {};
            return core.Error.OperationFailed; // Already exists
        }
        stderr.writeAll("[DRIVER] create: VMID is unique\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: VMID is unique\n");

        stderr.writeAll("[DRIVER] create: Resolving template\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Resolving template\n");

        // Resolve template to use: prefer converted template or find available one
        stderr.writeAll("[DRIVER] create: Before template resolution\n") catch {};
        var template: []u8 = undefined;
        stderr.writeAll("[DRIVER] create: Checking if template_name exists\n") catch {};
        if (template_name) |tname| {
            stderr.writeAll("[DRIVER] create: template_name provided: '") catch {};
            stderr.writeAll(tname) catch {};
            stderr.writeAll("'\n") catch {};
            if (self.debug_mode) {
                try stdout.writeAll("[DRIVER] create: Template name provided: '");
                try stdout.writeAll(tname);
                try stdout.writeAll("'\n");
            }
            // Check if template already has storage prefix (contains :)
            stderr.writeAll("[DRIVER] create: Checking for storage prefix in template name\n") catch {};
            const has_storage = std.mem.indexOf(u8, tname, ":") != null;
            if (has_storage) {
                stderr.writeAll("[DRIVER] create: Template has storage prefix, using as is\n") catch {};
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Template has storage prefix, using as is\n");
                // Template already has storage prefix, use as is
                stderr.writeAll("[DRIVER] create: Duplicating template name\n") catch {};
                template = try self.allocator.dupe(u8, tname);
                stderr.writeAll("[DRIVER] create: Template duplicated\n") catch {};
            } else {
                stderr.writeAll("[DRIVER] create: Template is just name, adding storage prefix\n") catch {};
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Template is just name, adding storage prefix\n");
                // Template is just a name, add storage prefix
                stderr.writeAll("[DRIVER] create: Formatting template with storage prefix\n") catch {};
                template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}.tar.zst", .{tname});
                stderr.writeAll("[DRIVER] create: Template formatted\n") catch {};
            }
        } else {
            stderr.writeAll("[DRIVER] create: No template name, finding available template\n") catch {};
            if (self.debug_mode) try stdout.writeAll("[DRIVER] create: No template name, finding available template\n");
            stderr.writeAll("[DRIVER] create: Calling findAvailableTemplate\n") catch {};
            const t = try self.findAvailableTemplate();
            stderr.writeAll("[DRIVER] create: Template found, duplicating\n") catch {};
            template = try self.allocator.dupe(u8, t);
            self.allocator.free(t);
            stderr.writeAll("[DRIVER] create: Template duplicated and free'd\n") catch {};
        }
        defer self.allocator.free(template);

        stderr.writeAll("[DRIVER] create: Final template: '") catch {};
        stderr.writeAll(template) catch {};
        stderr.writeAll("'\n") catch {};
        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: Final template: '");
            try stdout.writeAll(template);
            try stdout.writeAll("'\n");
        }

        stderr.writeAll("[DRIVER] create: Checking ZFS availability\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Checking ZFS availability\n");

        // Create ZFS dataset for container if ZFS is available
        stderr.writeAll("[DRIVER] create: Before ZFS dataset variable initialization\n") catch {};
        var zfs_dataset: ?[]const u8 = null;
        defer if (zfs_dataset) |dataset| self.allocator.free(dataset);
        stderr.writeAll("[DRIVER] create: ZFS dataset variable initialized\n") catch {};

        stderr.writeAll("[DRIVER] create: Before isZFSAvailable call\n") catch {};
        const zfs_available = self.isZFSAvailable();
        stderr.writeAll("[DRIVER] create: After isZFSAvailable call, result = ") catch {};
        if (zfs_available) {
            stderr.writeAll("true\n") catch {};
        } else {
            stderr.writeAll("false\n") catch {};
        }

        if (zfs_available) {
            stderr.writeAll("[DRIVER] create: ZFS available, creating dataset\n") catch {};
            if (self.debug_mode) try stdout.writeAll("[DRIVER] create: ZFS available, creating dataset\n");
            stderr.writeAll("[DRIVER] create: Before createContainerDataset call\n") catch {};
            zfs_dataset = try self.createContainerDataset(config.name, vmid);
            stderr.writeAll("[DRIVER] create: After createContainerDataset call\n") catch {};
            if (zfs_dataset) |dataset| {
                stderr.writeAll("[DRIVER] create: ZFS dataset created: '") catch {};
                stderr.writeAll(dataset) catch {};
                stderr.writeAll("'\n") catch {};
                // Skip logger to avoid segfault
                // if (self.logger) |log| log.info("Created ZFS dataset for container: {s}", .{dataset}) catch {};
                if (self.debug_mode) {
                    try stdout.writeAll("[DRIVER] create: ZFS dataset created: '");
                    try stdout.writeAll(dataset);
                    try stdout.writeAll("'\n");
                }
            } else {
                stderr.writeAll("[DRIVER] create: ZFS dataset creation returned null\n") catch {};
            }
        } else {
            stderr.writeAll("[DRIVER] create: ZFS not available, skipping dataset\n") catch {};
            if (self.debug_mode) try stdout.writeAll("[DRIVER] create: ZFS not available, skipping dataset\n");
        }

        stderr.writeAll("[DRIVER] create: Building pct create command arguments\n") catch {};
        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Building pct create command arguments\n");

        var args_builder = std.array_list.Managed([]const u8).init(self.allocator);
        defer args_builder.deinit();

        var allocated_args = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (allocated_args.items) |item| {
                if (item.len > 0) self.allocator.free(item);
            }
            allocated_args.deinit();
        }

        try args_builder.appendSlice(&[_][]const u8{ "pct", "create", vmid, template, "--hostname", config.name });

        // Build dynamic args from config, bundle config (priority), and defaults
        // Priority: bundle_config.resources > config.resources > defaults
        const mem_mb_str = blk: {
            const mem_bytes = if (bundle_config) |bc| blk2: {
                // Use bundle config memory limit if available (OCI bundle takes priority)
                if (bc.memory_limit) |bundle_mem| break :blk2 bundle_mem;
                break :blk2 if (config.resources) |r| r.memory orelse core.constants.DEFAULT_MEMORY_BYTES else core.constants.DEFAULT_MEMORY_BYTES;
            } else if (config.resources) |r| r.memory orelse core.constants.DEFAULT_MEMORY_BYTES else core.constants.DEFAULT_MEMORY_BYTES;
            const mb: u64 = mem_bytes / (1024 * 1024);
            break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{mb});
        };
        defer self.allocator.free(mem_mb_str);
        try args_builder.appendSlice(&[_][]const u8{ "--memory", mem_mb_str });

        const cores_str = blk: {
            const c: f64 = if (bundle_config) |bc| blk2: {
                // Use bundle config CPU limit if available (OCI bundle takes priority)
                if (bc.cpu_limit) |bundle_cpu| {
                    // Convert CPU shares to cores (rough approximation: shares/1024 = cores ratio)
                    // Ensure minimum of 1 core
                    const calculated = bundle_cpu / 1024.0;
                    break :blk2 if (calculated < 1.0) 1.0 else calculated;
                }
                break :blk2 if (config.resources) |r| (r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES)) else @as(f64, core.constants.DEFAULT_CPU_CORES);
            } else if (config.resources) |r| (r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES)) else @as(f64, core.constants.DEFAULT_CPU_CORES);
            // Ensure minimum of 1 core even after calculation
            const final_cores = if (c < 1.0) 1.0 else c;
            const ci: u32 = @intFromFloat(final_cores);
            break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{ci});
        };
        defer self.allocator.free(cores_str);
        try args_builder.appendSlice(&[_][]const u8{ "--cores", cores_str });

        const default_bridge = self.config.default_bridge orelse core.constants.DEFAULT_BRIDGE_NAME;
        const config_bridge = if (config.network) |net| net.bridge else null;
        const fallback_bridge = config_bridge orelse default_bridge;

        var net_runtime = std.array_list.Managed(NetDeviceRuntimeInfo).init(self.allocator);
        defer net_runtime.deinit();

        const bundle_net_devices = if (bundle_config) |*bc| bc.net_devices else null;
        if (bundle_net_devices) |devices| {
            if (devices.len > 0) {
                for (devices, 0..) |device, idx| {
                    const alias = device.alias;
                    const host_link = device.name;
                    const resolved_bridge = host_link orelse fallback_bridge;

                    const net_flag = try std.fmt.allocPrint(self.allocator, "--net{d}", .{idx});
                    try allocated_args.append(net_flag);
                    try args_builder.append(net_flag);

                    const net_value = try std.fmt.allocPrint(self.allocator, "name={s},bridge={s},ip=dhcp", .{ alias, resolved_bridge });
                    try allocated_args.append(net_value);
                    try args_builder.append(net_value);

                    try net_runtime.append(NetDeviceRuntimeInfo{
                        .alias = alias,
                        .bridge = resolved_bridge,
                        .host_name = host_link,
                    });
                }
            } else {
                const net_value = try std.fmt.allocPrint(self.allocator, "name=eth0,bridge={s},ip=dhcp", .{fallback_bridge});
                try allocated_args.append(net_value);
                try args_builder.appendSlice(&[_][]const u8{ "--net0", net_value });
                try net_runtime.append(NetDeviceRuntimeInfo{ .alias = "eth0", .bridge = fallback_bridge, .host_name = null });
            }
        } else {
            const net_value = try std.fmt.allocPrint(self.allocator, "name=eth0,bridge={s},ip=dhcp", .{fallback_bridge});
            try allocated_args.append(net_value);
            try args_builder.appendSlice(&[_][]const u8{ "--net0", net_value });
            try net_runtime.append(NetDeviceRuntimeInfo{ .alias = "eth0", .bridge = fallback_bridge, .host_name = null });
        }

        const ostype = self.config.default_ostype orelse "ubuntu";
        const unprivileged_str = if (self.config.default_unprivileged) |u| if (u) "1" else "0" else "0";
        try args_builder.appendSlice(&[_][]const u8{ "--ostype", ostype, "--unprivileged", unprivileged_str });

        if (zfs_dataset) |dataset| {
            try args_builder.appendSlice(&[_][]const u8{ "--rootfs", dataset });
        }

        const args = args_builder.items;

        if (self.logger) |log| {
            log.debug("Proxmox LXC create: Creating container with pct create", .{}) catch {};
        }

        // Debug: print all arguments (only in debug mode)
        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: pct create arguments:\n");
            for (args, 0..) |arg, i| {
                try stdout.writeAll("[DRIVER]   args[");
                const idx_str = try std.fmt.allocPrint(self.allocator, "{d}", .{i});
                defer self.allocator.free(idx_str);
                try stdout.writeAll(idx_str);
                try stdout.writeAll("] = '");
                try stdout.writeAll(arg);
                try stdout.writeAll("'\n");
            }
        }

        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Executing pct create command\n");
        const result = try self.runCommand(args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: pct create command completed\n");

        // Debug output (only in debug mode)
        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: pct create result:\n");
            try stdout.writeAll("[DRIVER]   exit_code: ");
            const exit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{result.exit_code});
            defer self.allocator.free(exit_str);
            try stdout.writeAll(exit_str);
            try stdout.writeAll("\n[DRIVER]   stdout: ");
            try stdout.writeAll(result.stdout);
            try stdout.writeAll("\n[DRIVER]   stderr: ");
            try stdout.writeAll(result.stderr);
            try stdout.writeAll("\n");
        }

        if (result.exit_code != 0) {
            if (self.debug_mode) {
                try stdout.writeAll("[DRIVER] create: ERROR: pct create failed\n");
                try stdout.writeAll("[DRIVER] create: Exit code: ");
                const exit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{result.exit_code});
                defer self.allocator.free(exit_str);
                try stdout.writeAll(exit_str);
                try stdout.writeAll("\n");
                try stdout.writeAll("[DRIVER] create: stderr: ");
                try stdout.writeAll(result.stderr);
                try stdout.writeAll("\n");
                try stdout.writeAll("[DRIVER] create: stdout: ");
                try stdout.writeAll(result.stdout);
                try stdout.writeAll("\n");
            }

            // On failure, do not delete dataset; rename with -failed suffix
            if (zfs_dataset) |dataset| {
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Renaming ZFS dataset with -failed suffix\n");
                const failed = std.mem.concat(self.allocator, u8, &.{ dataset, "-failed" }) catch null;
                if (failed) |new_name| {
                    defer self.allocator.free(new_name);
                    const rn = [_][]const u8{ "zfs", "rename", "-r", dataset, new_name };
                    const rn_res = self.runCommand(&rn) catch null;
                    if (rn_res) |resx| {
                        self.allocator.free(resx.stdout);
                        self.allocator.free(resx.stderr);
                    }
                }
            }

            if (self.logger) |log| log.err("Failed to create Proxmox LXC via pct: {s}", .{result.stderr}) catch {};

            // Check if container was actually created despite non-zero exit code
            // Some pct warnings still result in successful creation
            if (std.mem.indexOf(u8, result.stderr, "already exists") != null) {
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Container already exists, treating as success\n");
                // Continue - container exists, that's okay
            } else {
                return self.mapPctError(result.exit_code, result.stderr);
            }
        }

        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: pct create succeeded\n");

        // Apply mounts from bundle into /etc/pve/lxc/<vmid>.conf and verify via pct config
        if (oci_bundle_path) |bundle_for_mounts| {
            if (self.debug_mode) {
                try stdout.writeAll("[DRIVER] create: Applying mounts from OCI bundle: '");
                try stdout.writeAll(bundle_for_mounts);
                try stdout.writeAll("'\n");
            }
            if (self.logger) |log| log.info("Applying mounts from OCI bundle: {s}", .{bundle_for_mounts}) catch {};
            try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
            try self.verifyMountsInConfig(vmid);
            if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Mounts applied and verified\n");
        }

        // Apply namespaces from bundle (if available)
        if (bundle_config) |bc| {
            if (bc.namespaces) |namespaces| {
                if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Applying namespaces from OCI bundle\n");
                if (self.logger) |log| log.info("Applying {d} namespaces from OCI bundle", .{namespaces.len}) catch {};
                try self.applyNamespacesToLxcConfig(vmid, namespaces);
            }
        }

        const bundle_ptr: ?*const oci_bundle.OciBundleConfig = if (bundle_config) |*bc| bc else null;
        try self.persistRuntimeMetadata(config.name, vmid, bundle_ptr, net_runtime.items);

        // Cleanup bundle config after use (moved to defer at declaration)

        if (self.debug_mode) {
            try stdout.writeAll("[DRIVER] create: Container created successfully\n");
            try stdout.writeAll("[DRIVER] create: VMID: ");
            try stdout.writeAll(vmid);
            try stdout.writeAll(", Name: ");
            try stdout.writeAll(config.name);
            try stdout.writeAll("\n");
        }

        if (self.logger) |log| log.info("Proxmox LXC container created via pct: {s} (vmid {s})", .{ config.name, vmid }) catch {};
        // Persist OCI-compatible state file: /run/nexcage/<container_id>/state.json
        {
            const state_dir = "/run/nexcage";
            std.fs.cwd().makePath(state_dir) catch {};
            const container_dir = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ state_dir, config.name }) catch null;
            if (container_dir) |cdir| {
                defer self.allocator.free(cdir);
                std.fs.cwd().makePath(cdir) catch {};
                const state_path = std.fmt.allocPrint(self.allocator, "{s}/state.json", .{cdir}) catch null;
                if (state_path) |spath| {
                    defer self.allocator.free(spath);
                    const file = std.fs.cwd().createFile(spath, .{ .truncate = true, .read = false }) catch null;
                    if (file) |f| {
                        defer f.close();
                        // Determine bundle from oci_bundle_path if present
                        const bundle_json = if (oci_bundle_path) |bp| std.fmt.allocPrint(self.allocator, "\"{s}\"", .{bp}) catch null else null;
                        if (bundle_json) |bj| {
                            defer self.allocator.free(bj);
                            const content = std.fmt.allocPrint(
                                self.allocator,
                                "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"created\",\n  \"pid\": {d},\n  \"bundle\": {s},\n  \"annotations\": {{}}\n}}\n",
                                .{ config.name, 0, bj },
                            ) catch null;
                            if (content) |json| {
                                defer self.allocator.free(json);
                                _ = f.writeAll(json) catch {};
                            }
                        } else {
                            const content = std.fmt.allocPrint(
                                self.allocator,
                                "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"created\",\n  \"pid\": {d},\n  \"bundle\": null,\n  \"annotations\": {{}}\n}}\n",
                                .{ config.name, 0 },
                            ) catch null;
                            if (content) |json| {
                                defer self.allocator.free(json);
                                _ = f.writeAll(json) catch {};
                            }
                        }
                    }
                }
            }
        }

        if (self.debug_mode) try stdout.writeAll("[DRIVER] create: Finished\n");
    }

    fn persistRuntimeMetadata(
        self: *Self,
        container_name: []const u8,
        vmid: []const u8,
        bundle_config: ?*const oci_bundle.OciBundleConfig,
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
        var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        // Iterate mounts (if present)
        if (cfg.mounts) |mounts| {
            for (mounts) |*m| {
                const src_opt = m.source;
                if (src_opt == null) continue;
                const src = src_opt.?;

                // If looks like storage reference: <storage>:<path>
                if (std.mem.indexOfScalar(u8, src, ':')) |colon_idx| {
                    const storage = src[0..colon_idx];
                    const rest = std.mem.trim(u8, src[colon_idx + 1 ..], " \t\r\n");
                    if (storage.len > 0 and rest.len > 0 and storage[0] != '/') {
                        if (!(try self.storageHasPath(storage, rest))) {
                            if (self.logger) |log| log.err("Storage volume not found: {s}:{s}", .{ storage, rest }) catch {};
                            return core.Error.NotFound;
                        }
                        continue;
                    }
                }

                // Otherwise treat as host path (absolute)
                if (std.fs.cwd().access(src, .{})) |_| {
                    // ok
                } else |err| {
                    if (self.logger) |log| log.err("Host path for mount not accessible: {s} ({})", .{ src, err }) catch {};
                    return core.Error.NotFound;
                }
            }
        }
    }

    /// Check if Proxmox storage contains given path via `pvesm list <storage>`
    fn storageHasPath(self: *Self, storage: []const u8, entry: []const u8) !bool {
        const args = [_][]const u8{ "pvesm", "list", storage };
        const res = self.runCommand(&args) catch return false;
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return false;
        return std.mem.indexOf(u8, res.stdout, entry) != null;
    }

    /// Append mounts from bundle config to /etc/pve/lxc/<vmid>.conf using mpX syntax
    fn applyMountsToLxcConfig(self: *Self, vmid: []const u8, bundle_path: []const u8) !void {
        if (self.logger) |log| log.info("Parsing bundle for mounts: {s}", .{bundle_path}) catch {};

        var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        if (cfg.mounts == null) {
            if (self.logger) |log| log.info("No mounts found in bundle config", .{}) catch {};
            return;
        }
        const mounts = cfg.mounts.?;

        if (self.logger) |log| log.info("Found {d} mounts in bundle", .{mounts.len}) catch {};

        const conf_path = try std.fmt.allocPrint(self.allocator, "/etc/pve/lxc/{s}.conf", .{vmid});
        defer self.allocator.free(conf_path);

        // Read existing to determine next mp index
        const existing_data = try self.readFileAll(conf_path);
        defer if (existing_data) |buf| self.allocator.free(buf);
        var next_idx: u32 = 0;
        if (existing_data) |buf| {
            next_idx = self.findNextMpIndex(buf);
        }

        // Open config for append
        var file = try std.fs.openFileAbsolute(conf_path, .{ .mode = .read_write });
        defer file.close();
        try file.seekFromEnd(0);

        var i: u32 = 0;
        while (i < mounts.len) : (i += 1) {
            const m = mounts[i];
            if (m.destination == null) {
                if (self.logger) |log| log.warn("Mount {d} has no destination, skipping", .{i}) catch {};
                continue;
            }
            const dest = m.destination.?;

            const src_opt = m.source;
            if (src_opt == null) {
                if (self.logger) |log| log.warn("Mount {d} has no source, skipping", .{i}) catch {};
                continue;
            }
            const src = src_opt.?;

            // Build mp line
            const mp_line = try self.buildMpLine(next_idx, src, dest, m.options);
            defer self.allocator.free(mp_line);

            if (self.logger) |log| log.info("Adding mp{d}: {s}", .{ next_idx, mp_line }) catch {};
            try file.writeAll(mp_line);
            try file.writeAll("\n");
            next_idx += 1;
        }
    }

    /// Apply namespaces from OCI bundle to LXC container via pct set --features
    /// Maps OCI namespace types to LXC features where applicable
    fn applyNamespacesToLxcConfig(self: *Self, vmid: []const u8, namespaces: []const oci_bundle.NamespaceConfig) !void {
        if (self.logger) |log| log.info("Applying {d} namespaces to LXC container {s}", .{ namespaces.len, vmid }) catch {};

        // Build features list based on namespaces
        // Use ArrayListUnmanaged for slice elements as per Zig 0.15.1
        var features = std.ArrayListUnmanaged([]const u8){};
        errdefer {
            for (features.items) |feat| self.allocator.free(feat);
            features.deinit(self.allocator);
        }
        defer {
            for (features.items) |feat| self.allocator.free(feat);
            features.deinit(self.allocator);
        }

        // Track which namespaces we've seen
        var has_user_ns = false;

        // Parse namespaces and determine LXC features
        for (namespaces) |ns| {
            if (std.mem.eql(u8, ns.type, "user")) {
                has_user_ns = true;
                // user namespace typically means unprivileged (already set in pct create)
                if (self.logger) |log| log.info("Found user namespace - unprivileged mode already enabled", .{}) catch {};
            }
            // Other namespaces (pid, network, ipc, uts, mount, cgroup) are default in LXC
        }

        // Add LXC-specific features based on namespace requirements
        // If container needs nesting (e.g., for Docker-in-LXC or podman)
        // We enable nesting if user namespace is present (common for container runtimes)
        if (has_user_ns) {
            try features.append(self.allocator, try self.allocator.dupe(u8, "nesting=1"));
            try features.append(self.allocator, try self.allocator.dupe(u8, "keyctl=1"));
        } else {
            // Default minimal features for proper isolation
            try features.append(self.allocator, try self.allocator.dupe(u8, "keyctl=1"));
        }

        // Build features string: "nesting=1,keyctl=1"
        var features_str = std.ArrayListUnmanaged(u8){};
        defer features_str.deinit(self.allocator);

        for (features.items, 0..) |feat, i| {
            if (i > 0) try features_str.append(self.allocator, ',');
            try features_str.appendSlice(self.allocator, feat);
        }

        // Apply features via pct set
        const vmid_str = try std.fmt.allocPrint(self.allocator, "{s}", .{vmid});
        defer self.allocator.free(vmid_str);

        const features_str_owned = try features_str.toOwnedSlice(self.allocator);
        defer self.allocator.free(features_str_owned);

        const args = [_][]const u8{ "pct", "set", vmid_str, "--features", features_str_owned };

        if (self.debug_mode) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("[DRIVER] applyNamespacesToLxcConfig: Running: pct set ");
            try stdout.writeAll(vmid_str);
            try stdout.writeAll(" --features ");
            try stdout.writeAll(features_str_owned);
            try stdout.writeAll("\n");
        }

        const result = try self.runCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                log.err("Failed to apply namespaces/features to container {s}: {s}", .{ vmid_str, result.stderr }) catch {};
            }
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            log.info("Successfully applied features to container {s}: {s}", .{ vmid_str, features_str_owned }) catch {};
        }

        if (self.debug_mode) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("[DRIVER] applyNamespacesToLxcConfig: Features applied successfully\n");
        }
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

    /// Build mpX line from src/dest/options
    fn buildMpLine(self: *Self, idx: u32, src: []const u8, dest: []const u8, options: ?[]const u8) ![]u8 {
        // If src looks like storage ref (<storage>:<path> and not absolute path)
        const is_storage = (std.mem.indexOfScalar(u8, src, ':') != null) and (src.len > 0 and src[0] != '/');
        const opt = options orelse "";
        if (is_storage) {
            return std.fmt.allocPrint(self.allocator, "mp{d}: {s},mp={s}{s}{s}", .{ idx, src, dest, if (opt.len > 0) "," else "", opt });
        } else {
            return std.fmt.allocPrint(self.allocator, "mp{d}: {s},mp={s}{s}{s}", .{ idx, src, dest, if (opt.len > 0) "," else "", opt });
        }
    }

    /// Read file to memory (optional)
    fn readFileAll(self: *Self, path: []const u8) !?[]u8 {
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();
        const stat = try file.stat();
        var buf = try self.allocator.alloc(u8, @intCast(stat.size));
        const n = try file.readAll(buf);
        return buf[0..n];
    }

    /// Find next mp index from existing config content
    fn findNextMpIndex(self: *Self, data: []const u8) u32 {
        _ = self;
        var max_idx: u32 = 0;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len < 4) continue;
            if (line[0] == 'm' and line[1] == 'p') {
                // parse digits until ':'
                var j: usize = 2;
                var val: u32 = 0;
                var ok = false;
                while (j < line.len and line[j] >= '0' and line[j] <= '9') : (j += 1) {
                    val = val * 10 + @as(u32, @intCast(line[j] - '0'));
                    ok = true;
                }
                if (ok and j < line.len and line[j] == ':') {
                    if (val + 1 > max_idx) max_idx = val + 1;
                }
            }
        }
        return max_idx;
    }

    /// Start LXC container using pct command
    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            log.info("Starting Proxmox LXC container: {s}", .{container_id}) catch {};
        }

        // Resolve VMID by name via pct list
        if (self.logger) |log| log.info("Looking up VMID for container: {s}", .{container_id}) catch {};
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct start command
        const args = [_][]const u8{ "pct", "start", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| log.err("Failed to start Proxmox LXC container {s}: {s}", .{ container_id, result.stderr }) catch {};
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            log.info("Proxmox LXC container started successfully: {s}", .{container_id}) catch {};
        }

        // Determine init pid inside container and update OCI state
        var init_pid: i32 = 0;
        if (self.getInitPid(vmid)) |p| init_pid = p;
        self.writeOciState(container_id, "running", init_pid) catch {};
    }

    /// Stop LXC container using pct command
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            log.info("Stopping Proxmox LXC container: {s}", .{container_id}) catch {};
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct stop command
        const args = [_][]const u8{ "pct", "stop", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| log.err("Failed to stop Proxmox LXC container {s}: {s}", .{ container_id, result.stderr }) catch {};
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            log.info("Proxmox LXC container stopped successfully: {s}", .{container_id}) catch {};
        }

        // Update OCI state file to stopped (pid=0)
        self.writeOciState(container_id, "stopped", 0) catch {};
    }

    /// Delete LXC container using pct command
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            log.info("Deleting Proxmox LXC container: {s}", .{container_id}) catch {};
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct destroy command
        const args = [_][]const u8{ "pct", "destroy", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| log.err("Failed to delete Proxmox LXC container {s}: {s}", .{ container_id, result.stderr }) catch {};
            return self.mapPctError(result.exit_code, result.stderr);
        }

        // If ZFS used, rename dataset with -delete suffix instead of destroying
        if (self.zfs_pool) |pool| {
            const dataset_name = std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ pool, container_id, vmid }) catch null;
            if (dataset_name) |ds| {
                defer self.allocator.free(ds);
                const new_name = std.mem.concat(self.allocator, u8, &.{ ds, "-delete" }) catch null;
                if (new_name) |nn| {
                    defer self.allocator.free(nn);
                    const rn = [_][]const u8{ "zfs", "rename", "-r", ds, nn };
                    const rn_res = self.runCommand(&rn) catch null;
                    if (rn_res) |resx| {
                        self.allocator.free(resx.stdout);
                        self.allocator.free(resx.stderr);
                    }
                }
            }
        }

        if (self.logger) |log| {
            log.info("Proxmox LXC container deleted successfully: {s}", .{container_id}) catch {};
        }
    }

    /// Write minimal OCI state.json into /run/nexcage/<container_id>/state.json
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
        const json = try std.fmt.allocPrint(
            self.allocator,
            "{{\n  \"ociVersion\": \"1.0.0\",\n  \"id\": \"{s}\",\n  \"status\": \"{s}\",\n  \"pid\": {d},\n  \"bundle\": null,\n  \"annotations\": {{}}\n}}\n",
            .{ container_id, status, pid },
        );
        defer self.allocator.free(json);
        try file.writeAll(json);
    }

    /// Get PID 1 inside container by reading /proc/1/stat via pct exec
    fn getInitPid(self: *Self, vmid: []const u8) ?i32 {
        const args = [_][]const u8{ "pct", "exec", vmid, "--", "cat", "/proc/1/stat" };
        const res = self.runCommand(&args) catch return null;
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return null;
        const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
        var it = std.mem.splitScalar(u8, trimmed, ' ');
        if (it.next()) |first| {
            const p = std.fmt.parseInt(i32, first, 10) catch return null;
            return p;
        }
        return null;
    }

    /// Send signal to container using pct exec kill
    pub fn kill(self: *Self, container_id: []const u8, signal: []const u8) !void {
        if (self.logger) |log| {
            log.info("Sending signal {s} to Proxmox LXC container: {s}", .{ signal, container_id }) catch {};
        }

        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Check if container is already stopped - if so, kill is a no-op success
        {
            const st_args = [_][]const u8{ "pct", "status", vmid };
            const st_res = self.runCommand(&st_args) catch null;
            if (st_res) |r| {
                defer self.allocator.free(r.stdout);
                defer self.allocator.free(r.stderr);
                if (r.exit_code == 0) {
                    const trimmed = std.mem.trim(u8, r.stdout, " \t\r\n");
                    if (self.debug_mode) {
                        _ = std.fs.File.stdout().writeAll("[KILL] pre-check status=") catch {};
                        _ = std.fs.File.stdout().writeAll(trimmed) catch {};
                        _ = std.fs.File.stdout().writeAll("\n") catch {};
                    }
                    if (std.mem.indexOf(u8, trimmed, "stopped") != null) {
                        // Container already stopped, no-op success
                        if (self.logger) |log| log.info("Container {s} already stopped, kill is no-op", .{container_id}) catch {};
                        return;
                    }
                }
            }
        }

        // Try multiple ways to send SIG to PID 1 inside container; consider success if container transitions to stopped.
        var success = false;
        // Attempt 1: kill from PATH
        {
            const a = [_][]const u8{ "pct", "exec", vmid, "--", "kill", "-s", signal, "1" };
            const r = self.runCommand(&a) catch null;
            if (r) |res| {
                if (self.debug_mode) {
                    _ = std.fs.File.stdout().writeAll("[KILL] attempt1 rc=\n") catch {};
                }
                defer self.allocator.free(res.stdout);
                defer self.allocator.free(res.stderr);
                if (self.debug_mode) {
                    _ = std.fs.File.stdout().writeAll("[KILL] attempt1 stdout=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stdout) catch {};
                    _ = std.fs.File.stdout().writeAll("\n[KILL] attempt1 stderr=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stderr) catch {};
                    _ = std.fs.File.stdout().writeAll("\n") catch {};
                }
                if (res.exit_code == 0) success = true;
            }
        }
        // Attempt 2: /bin/kill
        if (!success) {
            const a = [_][]const u8{ "pct", "exec", vmid, "--", "/bin/kill", "-s", signal, "1" };
            const r = self.runCommand(&a) catch null;
            if (r) |res| {
                defer self.allocator.free(res.stdout);
                defer self.allocator.free(res.stderr);
                if (self.debug_mode) {
                    _ = std.fs.File.stdout().writeAll("[KILL] attempt2 stdout=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stdout) catch {};
                    _ = std.fs.File.stdout().writeAll("\n[KILL] attempt2 stderr=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stderr) catch {};
                    _ = std.fs.File.stdout().writeAll("\n") catch {};
                }
                if (res.exit_code == 0) success = true;
            }
        }
        // Attempt 3: /usr/bin/kill
        if (!success) {
            const a = [_][]const u8{ "pct", "exec", vmid, "--", "/usr/bin/kill", "-s", signal, "1" };
            const r = self.runCommand(&a) catch null;
            if (r) |res| {
                defer self.allocator.free(res.stdout);
                defer self.allocator.free(res.stderr);
                if (self.debug_mode) {
                    _ = std.fs.File.stdout().writeAll("[KILL] attempt3 stdout=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stdout) catch {};
                    _ = std.fs.File.stdout().writeAll("\n[KILL] attempt3 stderr=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stderr) catch {};
                    _ = std.fs.File.stdout().writeAll("\n") catch {};
                }
                if (res.exit_code == 0) success = true;
            }
        }
        // Attempt 4: shell fallback ignores failure
        if (!success) {
            const a = [_][]const u8{ "pct", "exec", vmid, "--", "/bin/sh", "-c", "kill -s TERM 1 || true" };
            const r = self.runCommand(&a) catch null;
            if (r) |res| {
                defer self.allocator.free(res.stdout);
                defer self.allocator.free(res.stderr);
                if (self.debug_mode) {
                    _ = std.fs.File.stdout().writeAll("[KILL] attempt4 stdout=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stdout) catch {};
                    _ = std.fs.File.stdout().writeAll("\n[KILL] attempt4 stderr=\n") catch {};
                    _ = std.fs.File.stdout().writeAll(res.stderr) catch {};
                    _ = std.fs.File.stdout().writeAll("\n") catch {};
                }
                success = true;
            }
        }
        // If direct attempts failed, poll status a few times and accept success if container is stopped
        if (!success) {
            var tries: usize = 0;
            while (tries < 10 and !success) : (tries += 1) {
                const st_args = [_][]const u8{ "pct", "status", vmid };
                const st_res = self.runCommand(&st_args) catch null;
                if (st_res) |r| {
                    defer self.allocator.free(r.stdout);
                    defer self.allocator.free(r.stderr);
                    if (r.exit_code == 0) {
                        const trimmed = std.mem.trim(u8, r.stdout, " \t\r\n");
                        if (self.debug_mode) {
                            _ = std.fs.File.stdout().writeAll("[KILL] poll status=\n") catch {};
                            _ = std.fs.File.stdout().writeAll(trimmed) catch {};
                            _ = std.fs.File.stdout().writeAll("\n") catch {};
                        }
                        if (std.mem.indexOf(u8, trimmed, "stopped") != null) {
                            success = true;
                            break;
                        }
                    }
                }
            }
        }
        if (!success) {
            if (self.logger) |log| log.err("Failed to send signal {s} to {s}", .{ signal, container_id }) catch {};
            return core.Error.OperationFailed;
        }
    }

    /// Find an available template for container creation
    fn findAvailableTemplate(self: *Self) ![]const u8 {
        // First, try to list available templates
        const list_args = [_][]const u8{ "pveam", "available" };
        const list_result = self.runCommand(&list_args) catch |err| {
            if (self.logger) |log| log.warn("Failed to list available templates: {}", .{err}) catch {};
            return self.getDefaultTemplate();
        };
        defer self.allocator.free(list_result.stdout);
        defer self.allocator.free(list_result.stderr);

        if (list_result.exit_code != 0) {
            if (self.logger) |log| log.warn("pveam available failed: {s}", .{list_result.stderr}) catch {};
            return self.getDefaultTemplate();
        }

        // Parse available templates and find a suitable one
        var lines = std.mem.splitScalar(u8, list_result.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "ubuntu") != null and std.mem.indexOf(u8, line, "standard") != null) {
                // Extract template name from line (format: "system ubuntu-22.04-standard_22.04-1_amd64.tar.zst")
                var fields = std.mem.splitScalar(u8, line, ' ');
                _ = fields.next(); // Skip "system"
                if (fields.next()) |template_name| {
                    const full_template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{template_name});
                    if (self.logger) |log| log.info("Found available template: {s}", .{full_template}) catch {};
                    return full_template;
                }
            }
        }

        // Fallback to default template
        if (self.logger) |log| log.warn("No suitable template found, using default", .{}) catch {};
        return self.getDefaultTemplate();
    }

    /// Get default template (fallback)
    fn getDefaultTemplate(self: *Self) ![]const u8 {
        // Try common template names (updated with correct extensions)
        const templates = [_][]const u8{
            "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
            "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst",
            "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst",
            "local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz",
        };

        for (templates) |template| {
            // Check if template exists
            const check_args = [_][]const u8{ "pveam", "list", "local:vztmpl" };
            const check_result = self.runCommand(&check_args) catch continue;
            defer self.allocator.free(check_result.stdout);
            defer self.allocator.free(check_result.stderr);

            if (check_result.exit_code == 0 and std.mem.indexOf(u8, check_result.stdout, template) != null) {
                if (self.logger) |log| log.info("Using default template: {s}", .{template}) catch {};
                return self.allocator.dupe(u8, template);
            }
        }

        // Last resort - return a basic template
        if (self.logger) |log| log.warn("No templates found, using basic template", .{}) catch {};
        return self.allocator.dupe(u8, "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst");
    }

    /// Parse bundle config.json to get image reference (annotations or rootfs.image)
    fn parseBundleImage(self: *Self, bundle_dir: std.fs.Dir) !?[]u8 {
        const file = bundle_dir.openFile("config.json", .{}) catch return null;
        defer file.close();

        // Read small chunk (best-effort, we only need to find a line with image)
        var buf: [8192]u8 = undefined;
        const n = try file.readAll(&buf);
        const data = buf[0..n];

        // Try to find annotation like: "org.opencontainers.image.ref.name": "ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
        if (std.mem.indexOf(u8, data, "org.opencontainers.image.ref.name")) |idx| {
            // naive extract value between quotes after colon
            const slice = data[idx..];
            if (std.mem.indexOf(u8, slice, ":")) |colon| {
                const after = std.mem.trim(u8, slice[colon + 1 ..], " \t\r\n");
                if (after.len >= 2) {
                    // find first quote
                    if (std.mem.indexOfScalar(u8, after, '"')) |q1| {
                        const rest = after[q1 + 1 ..];
                        if (std.mem.indexOfScalar(u8, rest, '"')) |q2| {
                            const val = rest[0..q2];
                            return try self.allocator.dupe(u8, val);
                        }
                    }
                }
            }
        }

        // Fallback: try to find "image": "..."
        if (std.mem.indexOf(u8, data, "\"image\"")) |idx2| {
            const slice2 = data[idx2..];
            if (std.mem.indexOf(u8, slice2, ":")) |colon2| {
                const after2 = std.mem.trim(u8, slice2[colon2 + 1 ..], " \t\r\n");
                if (after2.len >= 2) {
                    if (std.mem.indexOfScalar(u8, after2, '"')) |q1b| {
                        const rest2 = after2[q1b + 1 ..];
                        if (std.mem.indexOfScalar(u8, rest2, '"')) |q2b| {
                            const val2 = rest2[0..q2b];
                            return try self.allocator.dupe(u8, val2);
                        }
                    }
                }
            }
        }

        return null;
    }

    /// Check if given template exists on node (either downloaded or available to download)
    fn templateExists(self: *Self, template_name: []const u8) !bool {
        // First, check downloaded templates
        const list_downloaded = [_][]const u8{ "pveam", "list", "local:vztmpl" };
        const res1 = self.runCommand(&list_downloaded) catch return false;
        defer self.allocator.free(res1.stdout);
        defer self.allocator.free(res1.stderr);
        if (res1.exit_code == 0 and std.mem.indexOf(u8, res1.stdout, template_name) != null) return true;

        // Then, check available templates
        const list_available = [_][]const u8{ "pveam", "available" };
        const res2 = self.runCommand(&list_available) catch return false;
        defer self.allocator.free(res2.stdout);
        defer self.allocator.free(res2.stderr);
        if (res2.exit_code == 0 and std.mem.indexOf(u8, res2.stdout, template_name) != null) return true;

        return false;
    }
    /// Check if VMID already exists in Proxmox
    fn vmidExists(self: *Self, vmid: []const u8) !bool {
        const pct_args = [_][]const u8{ "pct", "list" };
        const pct_res = self.runCommand(&pct_args) catch return false;
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (pct_res.exit_code != 0) return false;

        // Parse pct list output to find VMID
        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (first) {
                first = false;
                continue; // Skip header
            }
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len < 20) continue; // Skip short lines

            // Extract VMID (first 10 characters)
            const vmid_str = std.mem.trim(u8, trimmed[0..10], " \t");

            if (std.mem.eql(u8, vmid_str, vmid)) {
                return true;
            }
        }

        return false;
    }

    /// Get VMID by container name
    fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        if (self.debug_mode) std.debug.print("DEBUG: getVmidByName() called with name: {s}\n", .{name});

        const pct_args = [_][]const u8{ "pct", "list" };
        if (self.logger) |log| log.info("Running pct list command", .{}) catch {};
        if (self.debug_mode) std.debug.print("DEBUG: About to run pct list\n", .{});

        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (self.logger) |log| log.info("pct list result: exit_code={d}, stdout='{s}', stderr='{s}'", .{ pct_res.exit_code, pct_res.stdout, pct_res.stderr }) catch {};
        if (self.debug_mode) std.debug.print("DEBUG: pct list result: exit_code={d}, stdout='{s}', stderr='{s}'\n", .{ pct_res.exit_code, pct_res.stdout, pct_res.stderr });

        if (pct_res.exit_code != 0) {
            if (self.debug_mode) std.debug.print("DEBUG: pct list failed with exit_code={d}\n", .{pct_res.exit_code});
            return core.Error.NotFound;
        }

        // Parse pct list output to find VMID by name
        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var first = true;
        while (lines.next()) |line| {
            if (first) {
                first = false;
                continue; // Skip header
            }
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Parse fixed-width columns from pct list output
            // Format: "VMID       Status     Lock         Name"
            // Example: "101        stopped                 container-1"
            if (self.debug_mode) std.debug.print("DEBUG: Processing line: '{s}' (len={d})\n", .{ trimmed, trimmed.len });
            if (trimmed.len < 20) continue; // Skip short lines

            // Extract VMID (first 10 characters)
            const vmid_str = std.mem.trim(u8, trimmed[0..10], " \t");
            if (vmid_str.len == 0) continue;

            // Extract Name (last column, starting from position 33)
            // Name column starts around position 33 in pct list output
            const name_start = @min(33, trimmed.len);
            const name_str = std.mem.trim(u8, trimmed[name_start..], " \t");

            if (self.logger) |log| log.info("Checking: vmid='{s}', name='{s}', looking for='{s}'", .{ vmid_str, name_str, name }) catch {};
            if (self.debug_mode) std.debug.print("DEBUG: Checking: vmid='{s}', name='{s}', looking for='{s}'\n", .{ vmid_str, name_str, name });

            if (std.mem.eql(u8, name_str, name)) {
                if (self.logger) |log| log.info("Found match: vmid='{s}', name='{s}'", .{ vmid_str, name_str }) catch {};
                if (self.debug_mode) std.debug.print("DEBUG: Found match: vmid='{s}', name='{s}'\n", .{ vmid_str, name_str });
                return self.allocator.dupe(u8, vmid_str);
            }
        }

        return core.Error.NotFound;
    }

    /// Run a command and return result
    fn runCommand(self: *Self, args: []const []const u8) !CommandResult {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024, // 1MB
        }) catch |err| {
            if (self.logger) |log| log.err("Failed to run command: {}", .{err}) catch {};
            return core.Error.OperationFailed;
        };

        const exit_code = switch (result.term) {
            .Exited => |code| @as(u8, @intCast(@abs(code))),
            else => 1,
        };

        return CommandResult{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .exit_code = exit_code,
        };
    }

    /// Map pct command errors to core errors with enhanced error messages
    fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
        _ = exit_code;
        const s = stderr;

        // Extract and log detailed error information
        if (self.logger) |log| {
            log.err("pct command failed: {s}", .{stderr}) catch {};
        }

        // Comprehensive error mapping with detailed messages
        if (std.mem.indexOf(u8, s, "already exists") != null) {
            if (self.logger) |log| {
                log.warn("Container with this name already exists. Consider using a different name or delete the existing container.", .{}) catch {};
            }
            return core.Error.OperationFailed; // Already exists
        }

        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null)
        {
            return core.Error.NotFound;
        }

        if (std.mem.indexOf(u8, s, "Permission denied") != null or
            std.mem.indexOf(u8, s, "permission denied") != null)
        {
            return core.Error.PermissionDenied;
        }

        if (std.mem.indexOf(u8, s, "timeout") != null or
            std.mem.indexOf(u8, s, "Timed out") != null)
        {
            return core.Error.Timeout;
        }

        if (std.mem.indexOf(u8, s, "Resource temporarily unavailable") != null) {
            return core.Error.OperationFailed;
        }

        if (std.mem.indexOf(u8, s, "Invalid argument") != null or
            std.mem.indexOf(u8, s, "invalid") != null)
        {
            return core.Error.InvalidInput;
        }

        if (std.mem.indexOf(u8, s, "cannot connect") != null or
            std.mem.indexOf(u8, s, "Connection refused") != null)
        {
            return core.Error.NetworkError;
        }

        // Default to OperationFailed for all other errors
        return core.Error.OperationFailed;
    }

    /// List LXC containers using pct command
    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        if (self.logger) |log| {
            log.info("Listing LXC containers via pct command", .{}) catch {};
        }

        const pct_args = [_][]const u8{ "pct", "list" };
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (pct_res.exit_code != 0) {
            return core.Error.OperationFailed;
        }

        // Parse pct list output
        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        defer {
            for (containers.items) |*c| {
                c.deinit();
            }
            containers.deinit(allocator);
        }

        var first = true;
        while (lines.next()) |line| {
            if (first) {
                first = false;
                continue; // Skip header
            }
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Split by whitespace columns
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid_str = it.next() orelse continue;
            const status_str = it.next() orelse "unknown";
            const name_str = it.next() orelse "unknown";

            const container = core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, vmid_str),
                .name = try allocator.dupe(u8, name_str),
                .status = try allocator.dupe(u8, status_str),
                .backend_type = try allocator.dupe(u8, "proxmox-lxc"),
                .runtime = try allocator.dupe(u8, "pct"),
            };

            try containers.append(allocator, container);
        }

        return containers.toOwnedSlice(allocator);
    }
};
