const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const oci_bundle = @import("oci_bundle.zig");
const image_converter = @import("image_converter.zig");

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

    pub fn init(allocator: std.mem.Allocator, config: core.types.ProxmoxLxcBackendConfig) !*Self {
        const driver = try allocator.alloc(Self, 1);
        driver[0] = Self{
            .allocator = allocator,
            .config = config,
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
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

    /// Process OCI bundle - convert to template if needed, return template name
    fn processOciBundle(self: *Self, bundle_path: []const u8, container_name: []const u8) !?[]const u8 {
        if (self.logger) |log| try log.info("Processing OCI bundle: {s}", .{bundle_path});
        if (self.logger) |log| try log.info("Logger is working in processOciBundle", .{});

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
                if (self.logger) |log| try log.info("Using existing template: {s}", .{image_ref});
                return image_ref;
            }
        }

        // If no existing template found, convert OCI bundle to template
        const template_name = try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ container_name, std.time.timestamp() });
        defer self.allocator.free(template_name);
        
        if (self.logger) |log| try log.info("Converting OCI bundle to template: {s}", .{template_name});
        
        var converter = image_converter.ImageConverter.init(self.allocator, self.logger);
        try converter.convertOciToProxmoxTemplate(bundle_path, template_name, "local");

        if (self.logger) |log| try log.info("Successfully converted OCI bundle to template: {s}", .{template_name});
        
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
            try log.info("Creating Proxmox LXC container: {s}", .{config.name});
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
                    if (self.logger) |log| try log.err("Bundle path not found: {s} ({})", .{ image_path, err });
                    return core.Error.FileNotFound;
                };
                defer bundle_dir.close();

                // Ensure config.json exists in the bundle
                bundle_dir.access("config.json", .{}) catch |err| {
                    if (self.logger) |log| try log.err("config.json not found in bundle: {s} ({})", .{ image_path, err });
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

        // Use pct create command
        const args = [_][]const u8{
            "pct",
            "create",
            vmid,
            template,
            "--hostname", config.name,
            "--memory", "512",
            "--cores", "1",
            "--net0", "name=eth0,bridge=vmbr0,ip=dhcp",
            "--ostype", "ubuntu",
            "--unprivileged", "0",
        };

        if (self.logger) |log| {
            try log.debug("Proxmox LXC create: Creating container with pct create", .{});
        }
        
        // Debug: print template name (only in debug mode)
        if (self.debug_mode) {
            const stdout = std.fs.File.stdout();
            try stdout.writeAll("DEBUG: template = '");
            try stdout.writeAll(template);
            try stdout.writeAll("'\n");
        }

        const result = try self.runCommand(&args);
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
            if (self.logger) |log| try log.err("Failed to create Proxmox LXC via pct: {s}", .{result.stderr});
            return self.mapPctError(result.exit_code, result.stderr);
        }

        // Apply mounts from bundle into /etc/pve/lxc/<vmid>.conf and verify via pct config
        if (oci_bundle_path) |bundle_for_mounts| {
            if (self.logger) |log| try log.info("Applying mounts from OCI bundle: {s}", .{bundle_for_mounts});
            try self.applyMountsToLxcConfig(vmid, bundle_for_mounts);
            try self.verifyMountsInConfig(vmid);
        }

        if (self.logger) |log| try log.info("Proxmox LXC container created via pct: {s} (vmid {s})", .{ config.name, vmid });
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
                        if (self.logger) |log| try log.err("Storage volume not found: {s}:{s}", .{ storage, rest });
                        return core.Error.NotFound;
                    }
                    continue;
                }
            }

                // Otherwise treat as host path (absolute)
                if (std.fs.cwd().access(src, .{})) |_| {
                    // ok
                } else |err| {
                    if (self.logger) |log| try log.err("Host path for mount not accessible: {s} ({})", .{ src, err });
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
        if (self.logger) |log| try log.info("Parsing bundle for mounts: {s}", .{bundle_path});
        
        var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        if (cfg.mounts == null) {
            if (self.logger) |log| try log.info("No mounts found in bundle config", .{});
            return;
        }
        const mounts = cfg.mounts.?;
        
        if (self.logger) |log| try log.info("Found {d} mounts in bundle", .{mounts.len});

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
                if (self.logger) |log| try log.warn("Mount {d} has no destination, skipping", .{i});
                continue;
            }
            const dest = m.destination.?;

            const src_opt = m.source;
            if (src_opt == null) {
                if (self.logger) |log| try log.warn("Mount {d} has no source, skipping", .{i});
                continue;
            }
            const src = src_opt.?;

            // Build mp line
            const mp_line = try self.buildMpLine(next_idx, src, dest, m.options);
            defer self.allocator.free(mp_line);
            
            if (self.logger) |log| try log.info("Adding mp{d}: {s}", .{ next_idx, mp_line });
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
            if (self.logger) |log| try log.warn("No mp entries visible in pct config after update", .{});
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
            try log.info("Starting Proxmox LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        if (self.logger) |log| try log.info("Looking up VMID for container: {s}", .{container_id});
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct start command
        const args = [_][]const u8{ "pct", "start", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to start Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container started successfully: {s}", .{container_id});
        }
    }

    /// Stop LXC container using pct command
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping Proxmox LXC container: {s}", .{container_id});
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
            if (self.logger) |log| try log.err("Failed to stop Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container stopped successfully: {s}", .{container_id});
        }
    }

    /// Delete LXC container using pct command
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting Proxmox LXC container: {s}", .{container_id});
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
            if (self.logger) |log| try log.err("Failed to delete Proxmox LXC container {s}: {s}", .{ container_id, result.stderr });
            return self.mapPctError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("Proxmox LXC container deleted successfully: {s}", .{container_id});
        }
    }

    /// Find an available template for container creation
    fn findAvailableTemplate(self: *Self) ![]const u8 {
        // First, try to list available templates
        const list_args = [_][]const u8{ "pveam", "available" };
        const list_result = self.runCommand(&list_args) catch |err| {
            if (self.logger) |log| try log.warn("Failed to list available templates: {}", .{err});
            return self.getDefaultTemplate();
        };
        defer self.allocator.free(list_result.stdout);
        defer self.allocator.free(list_result.stderr);

        if (list_result.exit_code != 0) {
            if (self.logger) |log| try log.warn("pveam available failed: {s}", .{list_result.stderr});
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
                    if (self.logger) |log| try log.info("Found available template: {s}", .{full_template});
                    return full_template;
                }
            }
        }

        // Fallback to default template
        if (self.logger) |log| try log.warn("No suitable template found, using default", .{});
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
                if (self.logger) |log| try log.info("Using default template: {s}", .{template});
                return self.allocator.dupe(u8, template);
            }
        }

        // Last resort - return a basic template
        if (self.logger) |log| try log.warn("No templates found, using basic template", .{});
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
    /// Get VMID by container name
    fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        if (self.debug_mode) std.debug.print("DEBUG: getVmidByName() called with name: {s}\n", .{name});
        
        const pct_args = [_][]const u8{ "pct", "list" };
        if (self.logger) |log| try log.info("Running pct list command", .{});
        if (self.debug_mode) std.debug.print("DEBUG: About to run pct list\n", .{});
        
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);

        if (self.logger) |log| try log.info("pct list result: exit_code={d}, stdout='{s}', stderr='{s}'", .{ pct_res.exit_code, pct_res.stdout, pct_res.stderr });
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

            if (self.logger) |log| try log.info("Checking: vmid='{s}', name='{s}', looking for='{s}'", .{ vmid_str, name_str, name });
            if (self.debug_mode) std.debug.print("DEBUG: Checking: vmid='{s}', name='{s}', looking for='{s}'\n", .{ vmid_str, name_str, name });

            if (std.mem.eql(u8, name_str, name)) {
                if (self.logger) |log| try log.info("Found match: vmid='{s}', name='{s}'", .{ vmid_str, name_str });
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
            if (self.logger) |log| try log.err("Failed to run command: {}", .{err});
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

    /// Map pct command errors to core errors
    fn mapPctError(self: *Self, exit_code: u8, stderr: []const u8) core.Error {
        _ = self;
        _ = exit_code;
        const s = stderr;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null)
        {
            return core.Error.NotFound;
        }
        if (std.mem.indexOf(u8, s, "Permission denied") != null) {
            return core.Error.PermissionDenied;
        }
        if (std.mem.indexOf(u8, s, "already exists") != null) {
            return core.Error.OperationFailed;
        }
        if (std.mem.indexOf(u8, s, "timeout") != null) {
            return core.Error.Timeout;
        }
        return core.Error.OperationFailed;
    }

    /// List LXC containers using pct command
    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        if (self.logger) |log| {
            try log.info("Listing LXC containers via pct command", .{});
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
