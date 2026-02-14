const std = @import("std");
const core = @import("core");
const common = @import("common.zig");
const oci_spec = @import("oci_spec");
const bundle = oci_spec.runtime.bundle;
const template_manager = @import("template_manager.zig");
const utils = @import("utils");
const lxc_converter = utils.lxc_converter;

pub const OciProcessor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    config: core.types.ProxmoxLxcBackendConfig,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext, config: core.types.ProxmoxLxcBackendConfig) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .config = config,
        };
    }

    fn getBundleLogger(self: *const Self) ?bundle.Logger {
        if (self.logger) |log| return @as(?bundle.Logger, @ptrCast(log));
        return null;
    }

    pub fn processOciBundle(self: *Self, bundle_path: []const u8, container_name: []const u8, template_mgr: *template_manager.TemplateManager) !?[]const u8 {
        if (self.logger) |log| try log.info("Processing OCI bundle: {s}", .{bundle_path});

        var parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        const maybe_image = try self.parseBundleImageFromConfig(&cfg);
        if (maybe_image) |image_ref| {
            defer self.allocator.free(image_ref);
            if (template_mgr.getTemplate(image_ref) != null) return image_ref;
        }

        const template_name = try std.fmt.allocPrint(self.allocator, "{s}-{d}", .{ container_name, std.time.timestamp() });
        defer self.allocator.free(template_name);

        if (self.logger) |log| try log.info("Successfully converted OCI bundle to template: {s}", .{template_name});

        var template_info = try template_manager.TemplateInfo.init(self.allocator, template_name, 0, .oci_bundle);
        errdefer template_info.deinit(self.allocator);

        var metadata_parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
        var metadata_cfg = metadata_parser.parseBundle(bundle_path) catch |err| {
            if (self.logger) |log| log.warn("Failed to parse bundle for metadata: {}", .{err}) catch {};
            try template_mgr.addTemplate(template_name, template_info);
            return try self.allocator.dupe(u8, template_name);
        };
        defer metadata_cfg.deinit();

        var metadata = template_manager.TemplateMetadata.init(self.allocator);
        errdefer metadata.deinit(self.allocator);

        if (metadata_cfg.image_name) |name| metadata.image_name = try self.allocator.dupe(u8, name);
        if (metadata_cfg.image_tag) |tag| metadata.image_tag = try self.allocator.dupe(u8, tag);

        if (metadata_cfg.entrypoint) |ep| {
            var entrypoint_array = try self.allocator.alloc([]const u8, ep.len);
            errdefer {
                for (0..ep.len) |idx| self.allocator.free(entrypoint_array[idx]);
                self.allocator.free(entrypoint_array);
            }
            for (ep, 0..) |arg, i| entrypoint_array[i] = try self.allocator.dupe(u8, arg);
            metadata.entrypoint = entrypoint_array;
        }

        if (metadata_cfg.cmd) |cmd| {
            var cmd_array = try self.allocator.alloc([]const u8, cmd.len);
            errdefer {
                for (0..cmd.len) |idx| self.allocator.free(cmd_array[idx]);
                self.allocator.free(cmd_array);
            }
            for (cmd, 0..) |arg, i| cmd_array[i] = try self.allocator.dupe(u8, arg);
            metadata.cmd = cmd_array;
        }

        if (metadata_cfg.working_directory) |wd| metadata.working_directory = try self.allocator.dupe(u8, wd);

        if (metadata_cfg.net_devices) |devices| {
            var device_meta = try self.allocator.alloc(template_manager.TemplateMetadata.NetDeviceMetadata, devices.len);
            errdefer {
                for (device_meta) |dev| {
                    self.allocator.free(dev.alias);
                    self.allocator.free(dev.bridge);
                    if (dev.host_name) |hn| self.allocator.free(hn);
                }
                self.allocator.free(device_meta);
            }
            for (devices, 0..) |device, i| {
                device_meta[i] = .{};
                device_meta[i].alias = try self.allocator.dupe(u8, device.alias);
                const bridge_ref = device.name orelse (self.config.default_bridge orelse core.constants.DEFAULT_BRIDGE_NAME);
                device_meta[i].bridge = try self.allocator.dupe(u8, bridge_ref);
                if (device.name) |name| device_meta[i].host_name = try self.allocator.dupe(u8, name);
            }
            metadata.net_devices = device_meta;
        }

        template_info.metadata = metadata;
        try template_mgr.addTemplate(template_name, template_info);

        return try self.allocator.dupe(u8, template_name);
    }

    pub fn validateBundleVolumes(self: *Self, bundle_path: []const u8, pve_client: *const common.PveClient) !void {
        _ = pve_client; // Not used in this version but kept for consistency
        var parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        if (cfg.mounts) |mounts| {
            for (mounts) |m| {
                const src = m.source orelse continue;
                if (std.mem.indexOfScalar(u8, src, ':')) |colon_idx| {
                    const storage = src[0..colon_idx];
                    if (storage.len > 0 and storage[0] != '/') continue; // assume storage ref for now
                }
                std.fs.cwd().access(src, .{}) catch |err| {
                    if (self.logger) |log| log.err("Host path for mount not accessible: {s} ({})", .{ src, err }) catch {};
                    return core.Error.NotFound;
                };
            }
        }
    }

    pub fn parseBundleImageFromConfig(self: *const Self, config: *const bundle.OciBundleConfig) !?[]const u8 {
        if (config.annotations) |annotations| {
            if (annotations.get("org.opencontainers.image.ref.name")) |image_ref| {
                return try self.allocator.dupe(u8, image_ref.string);
            }
        }
        return null;
    }

    pub fn applyMountsToLxcConfig(self: *const Self, vmid: []const u8, bundle_path: []const u8) !void {
        var parser = bundle.OciBundleParser.init(self.allocator, self.getBundleLogger());
        var cfg = try parser.parseBundle(bundle_path);
        defer cfg.deinit();

        if (cfg.mounts) |mounts| {
            const conf_path = try std.fmt.allocPrint(self.allocator, "/etc/pve/lxc/{s}.conf", .{vmid});
            defer self.allocator.free(conf_path);

            const existing_data = try self.readFileAll(conf_path);
            defer if (existing_data) |buf| self.allocator.free(buf);
            var next_idx: u32 = if (existing_data) |buf| self.findNextMpIndex(buf) else 0;

            var file = try std.fs.openFileAbsolute(conf_path, .{ .mode = .read_write });
            defer file.close();
            try file.seekFromEnd(0);

            for (mounts) |m| {
                const dest = m.destination orelse continue;
                const src = m.source orelse continue;

                const mp_line = try std.fmt.allocPrint(self.allocator, "mp{d}: {s},mp={s}{s}{s}\n", .{ next_idx, src, dest, if (m.options) |opt| if (opt.len > 0) "," else "" else "", m.options orelse "" });
                defer self.allocator.free(mp_line);
                try file.writeAll(mp_line);
                next_idx += 1;
            }
        }
    }

    pub fn applyNamespacesToLxcConfig(self: *const Self, vmid: []const u8, namespaces: []const bundle.NamespaceConfig) !void {
        var features = std.ArrayListUnmanaged(u8){};
        defer features.deinit(self.allocator);

        var has_user_ns = false;
        for (namespaces) |ns| {
            if (std.mem.eql(u8, ns.type, "user")) has_user_ns = true;
        }

        if (has_user_ns) {
            try features.appendSlice(self.allocator, "nesting=1,keyctl=1");
        } else {
            try features.appendSlice(self.allocator, "keyctl=1");
        }

        const args = [_][]const u8{ "pct", "set", vmid, "--features", features.items };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.RuntimeError;
    }

    fn readFileAll(self: *const Self, path: []const u8) !?[]u8 {
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();
        const stat = try file.stat();
        var buf = try self.allocator.alloc(u8, @intCast(stat.size));
        const n = try file.readAll(buf);
        return buf[0..n];
    }

    fn findNextMpIndex(_: *const Self, data: []const u8) u32 {
        var max_idx: u32 = 0;
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len < 4) continue;
            if (line[0] == 'm' and line[1] == 'p') {
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
};
