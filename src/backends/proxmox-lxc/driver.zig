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
                if (std.mem.indexOfScalar(u8, line, '-') ) |dash_idx| {
                    const v = line[dash_idx+1..];
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
        if (!self.isZFSAvailable() or self.zfs_pool == null) {
            if (self.logger) |log| log.warn("ZFS not available, skipping dataset creation", .{}) catch {};
            return null;
        }

        const pool = self.zfs_pool.?;
        
        // Create dataset name: pool/containers/container_name-vmid
        const dataset_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ pool, container_name, vmid });
        defer self.allocator.free(dataset_name);

        if (self.logger) |log| log.info("Creating ZFS dataset for container: {s}", .{dataset_name}) catch {};

        // Create the dataset
        {
            const args = [_][]const u8{ "zfs", "create", dataset_name };
            const res = try self.runCommand(&args);
            defer self.allocator.free(res.stdout);
            defer self.allocator.free(res.stderr);
            if (res.exit_code != 0) return core.Error.OperationFailed;
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
        var template_info = try template_manager.TemplateInfo.init(
            self.allocator, 
            template_name, 
            0, // Size will be updated later
            .oci_bundle
        );
        
        // Extract metadata from OCI bundle if available
        var metadata_parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var metadata_cfg = metadata_parser.parseBundle(bundle_path) catch |err| {
            if (self.logger) |log| log.warn("Failed to parse bundle for metadata: {}", .{err}) catch {};
            try self.template_manager.addTemplate(template_name, template_info);
            return try self.allocator.dupe(u8, template_name);
        };
        defer metadata_cfg.deinit();
        
        // Create metadata from OCI bundle
        var metadata = template_manager.TemplateMetadata.init(self.allocator);
        if (metadata_cfg.image_name) |name| metadata.image_name = try self.allocator.dupe(u8, name);
        if (metadata_cfg.image_tag) |tag| metadata.image_tag = try self.allocator.dupe(u8, tag);
        if (metadata_cfg.entrypoint) |ep| {
            var entrypoint_array = try self.allocator.alloc([]const u8, ep.len);
            for (ep, 0..) |arg, i| {
                entrypoint_array[i] = try self.allocator.dupe(u8, arg);
            }
            metadata.entrypoint = entrypoint_array;
        }
        if (metadata_cfg.cmd) |cmd| {
            var cmd_array = try self.allocator.alloc([]const u8, cmd.len);
            for (cmd, 0..) |arg, i| {
                cmd_array[i] = try self.allocator.dupe(u8, arg);
            }
            metadata.cmd = cmd_array;
        }
        if (metadata_cfg.working_directory) |wd| metadata.working_directory = try self.allocator.dupe(u8, wd);
        
        template_info.metadata = metadata;
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
        if (self.logger) |log| {
            log.info("Creating Proxmox LXC container: {s}", .{config.name}) catch {};
        }
        
        // Process bundle image if provided (bundle path with config.json)
        var template_name: ?[]const u8 = null;
        defer if (template_name) |tname| self.allocator.free(tname);
        
        // Keep track of original OCI bundle path for mounts
        var oci_bundle_path: ?[]const u8 = null;
        
        if (config.image) |image_path| {
            // Check if it's a Proxmox template (ends with .tar.zst or contains :)
            if (std.mem.endsWith(u8, image_path, ".tar.zst") or std.mem.indexOf(u8, image_path, ":") != null) {
                // It's a Proxmox template, use it directly
                template_name = try self.allocator.dupe(u8, image_path);
            } else {
                // It's an OCI bundle - ensure bundle directory exists
                var bundle_dir = std.fs.cwd().openDir(image_path, .{}) catch |err| {
                    if (self.logger) |log| log.err("Bundle path not found: {s} ({})", .{ image_path, err }) catch {};
                    return core.Error.FileNotFound;
                };
                defer bundle_dir.close();

                // Ensure config.json exists in the bundle
                bundle_dir.access("config.json", .{}) catch |err| {
                    if (self.logger) |log| log.err("config.json not found in bundle: {s} ({})", .{ image_path, err }) catch {};
                    return core.Error.FileNotFound;
                };

                // Save OCI bundle path for mounts processing
                oci_bundle_path = image_path;
                
                // Process OCI bundle - convert to template if needed
                template_name = try self.processOciBundle(image_path, config.name);
            }
        }

        // Generate VMID from name (Proxmox requires numeric vmid)
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(config.name);
        const vmid_num: u32 = @truncate(hasher.final());
        const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
        const vmid = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
        defer self.allocator.free(vmid);
        
        // Validate VMID uniqueness - check if container with this VMID already exists
        if (try self.vmidExists(vmid)) {
            if (self.logger) |log| {
                log.err("Container with VMID {s} already exists. Try a different container name.", .{vmid}) catch {};
            }
            return core.Error.OperationFailed; // Already exists
        }

        // Resolve template to use: prefer converted template or find available one
        var template: []u8 = undefined;
        if (template_name) |tname| {
            // Check if template already has storage prefix (contains :)
            if (std.mem.indexOf(u8, tname, ":") != null) {
                // Template already has storage prefix, use as is
                template = try self.allocator.dupe(u8, tname);
            } else {
                // Template is just a name, add storage prefix
                template = try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}.tar.zst", .{tname});
            }
        } else {
            const t = try self.findAvailableTemplate();
            template = try self.allocator.dupe(u8, t);
            self.allocator.free(t);
        }
        defer self.allocator.free(template);

        // Create ZFS dataset for container if ZFS is available
        var zfs_dataset: ?[]const u8 = null;
        defer if (zfs_dataset) |dataset| self.allocator.free(dataset);
        
        if (self.isZFSAvailable()) {
            zfs_dataset = try self.createContainerDataset(config.name, vmid);
            if (zfs_dataset) |dataset| {
                if (self.logger) |log| log.info("Created ZFS dataset for container: {s}", .{dataset}) catch {};
            }
        }

        // Use pct create command
        var args: []const []const u8 = undefined;
        
        // Build dynamic args from config and defaults
        const mem_mb_str = blk: {
            const mem_bytes = if (config.resources) |r| r.memory orelse (core.constants.DEFAULT_MEMORY_BYTES) else core.constants.DEFAULT_MEMORY_BYTES;
            const mb: u64 = mem_bytes / (1024 * 1024);
            break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{mb});
        };
        defer self.allocator.free(mem_mb_str);

        const cores_str = blk: {
            const c: f64 = if (config.resources) |r| (r.cpu orelse @as(f64, core.constants.DEFAULT_CPU_CORES)) else @as(f64, core.constants.DEFAULT_CPU_CORES);
            const ci: u32 = @intFromFloat(c);
            break :blk try std.fmt.allocPrint(self.allocator, "{d}", .{ci});
        };
        defer self.allocator.free(cores_str);

        const bridge = blk: {
            if (config.network) |net| {
                if (net.bridge) |b| break :blk b;
            }
            break :blk core.constants.DEFAULT_BRIDGE_NAME;
        };
        const net0 = try std.fmt.allocPrint(self.allocator, "name=eth0,bridge={s},ip=dhcp", .{bridge});
        defer self.allocator.free(net0);

        const ostype = self.config.default_ostype orelse "ubuntu";
        const unprivileged_str = if (self.config.default_unprivileged) |u| if (u) "1" else "0" else "0";

        if (zfs_dataset) |dataset| {
            args = &[_][]const u8{
                "pct", "create", vmid, template,
                "--hostname", config.name,
                "--memory", mem_mb_str,
                "--cores", cores_str,
                "--net0", net0,
                "--ostype", ostype,
                "--unprivileged", unprivileged_str,
                "--rootfs", dataset,
            };
        } else {
            args = &[_][]const u8{
                "pct", "create", vmid, template,
                "--hostname", config.name,
                "--memory", mem_mb_str,
                "--cores", cores_str,
                "--net0", net0,
                "--ostype", ostype,
                "--unprivileged", unprivileged_str,
            };
        }

        if (self.logger) |log| {
            log.debug("Proxmox LXC create: Creating container with pct create", .{}) catch {};
        }
        
        // Debug: print template name (only in debug mode)
        if (self.debug_mode) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("DEBUG: template = '");
            try stdout.writeAll(template);
            try stdout.writeAll("'\n");
        }

        const result = try self.runCommand(args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        // Debug output (only in debug mode)
        if (self.debug_mode) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("DEBUG: pct create result - exit_code: ");
            try stdout.writeAll(std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{result.exit_code}) catch "unknown");
            try stdout.writeAll(", stdout: ");
            try stdout.writeAll(result.stdout);
            try stdout.writeAll(", stderr: ");
            try stdout.writeAll(result.stderr);
            try stdout.writeAll("\n");
        }
        
        if (result.exit_code != 0) {
            // On failure, do not delete dataset; rename with -failed suffix
            if (zfs_dataset) |dataset| {
                const failed = std.mem.concat(self.allocator, u8, &.{ dataset, "-failed" }) catch null;
                if (failed) |new_name| {
                    defer self.allocator.free(new_name);
                    const rn = [_][]const u8{ "zfs", "rename", "-r", dataset, new_name };
                    const rn_res = self.runCommand(&rn) catch null;
                    if (rn_res) |resx| { self.allocator.free(resx.stdout); self.allocator.free(resx.stderr); }
                }
            }
            
            if (self.logger) |log| log.err("Failed to create Proxmox LXC via pct: {s}", .{result.stderr}) catch {};
            return self.mapPctError(result.exit_code, result.stderr);
        }

        // Apply mounts from bundle into /etc/pve/lxc/<vmid>.conf and verify via pct config
        if (oci_bundle_path) |bundle_for_mounts| {
            if (self.logger) |log| log.info("Applying mounts from OCI bundle: {s}", .{bundle_for_mounts}) catch {};
            try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
            try self.verifyMountsInConfig(vmid);
        }

        if (self.logger) |log| log.info("Proxmox LXC container created via pct: {s} (vmid {s})", .{ config.name, vmid }) catch {};
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
                const rest = std.mem.trim(u8, src[colon_idx+1..], " \t\r\n");
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
                    if (rn_res) |resx| { self.allocator.free(resx.stdout); self.allocator.free(resx.stderr); }
                }
            }
        }

        if (self.logger) |log| {
            log.info("Proxmox LXC container deleted successfully: {s}", .{container_id}) catch {};
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
        if (std.mem.indexOf(u8, data, "org.opencontainers.image.ref.name") ) |idx| {
            // naive extract value between quotes after colon
            const slice = data[idx..];
            if (std.mem.indexOf(u8, slice, ":") ) |colon| {
                const after = std.mem.trim(u8, slice[colon+1..], " \t\r\n");
                if (after.len >= 2) {
                    // find first quote
                    if (std.mem.indexOfScalar(u8, after, '"')) |q1| {
                        const rest = after[q1+1..];
                        if (std.mem.indexOfScalar(u8, rest, '"')) |q2| {
                            const val = rest[0..q2];
                            return try self.allocator.dupe(u8, val);
                        }
                    }
                }
            }
        }

        // Fallback: try to find "image": "..."
        if (std.mem.indexOf(u8, data, "\"image\"") ) |idx2| {
            const slice2 = data[idx2..];
            if (std.mem.indexOf(u8, slice2, ":") ) |colon2| {
                const after2 = std.mem.trim(u8, slice2[colon2+1..], " \t\r\n");
                if (after2.len >= 2) {
                    if (std.mem.indexOfScalar(u8, after2, '"')) |q1b| {
                        const rest2 = after2[q1b+1..];
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
