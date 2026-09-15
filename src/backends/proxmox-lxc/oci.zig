const std = @import("std");
const core = @import("core");
const common = @import("common.zig");
const oci_spec = @import("oci_spec");
const bundle = oci_spec.runtime.bundle;
/// A template archive packed from an OCI bundle's rootfs.
pub const BundleTemplate = struct {
    /// Volume ID for pct create: local:vztmpl/nexcage-<name>-<timestamp>.tar.zst
    volid: []u8,
    /// The archive on the host
    path: []u8,

    /// Deletes the archive. pct create has unpacked it by then, and names
    /// with a timestamp would otherwise pile up in the template list.
    pub fn remove(self: *BundleTemplate, allocator: std.mem.Allocator) void {
        std.fs.deleteFileAbsolute(self.path) catch {};
        allocator.free(self.volid);
        allocator.free(self.path);
    }
};

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

    /// Packs a bundle's rootfs into a template archive on storage `local` for
    /// pct create. The rootfs is used as it is, so it has to boot as a system
    /// container, init included.
    ///
    /// Before this, create logged "Successfully converted OCI bundle to
    /// template" and gave pct a template name that nothing had written.
    pub fn createTemplateFromBundle(self: *Self, rootfs_path: []const u8, container_name: []const u8) !BundleTemplate {
        const volid = try std.fmt.allocPrint(self.allocator, "local:vztmpl/nexcage-{s}-{d}.tar.zst", .{ container_name, std.time.timestamp() });
        errdefer self.allocator.free(volid);

        // The storage decides where its templates live. `pvesm path` only
        // computes the path, so the file does not have to exist yet.
        const path_res = try common.runCommand(self.allocator, self.logger, &.{ "pvesm", "path", volid });
        defer {
            self.allocator.free(path_res.stdout);
            self.allocator.free(path_res.stderr);
        }
        const path = std.mem.trim(u8, path_res.stdout, " \t\r\n");
        if (path_res.exit_code != 0 or !std.fs.path.isAbsolute(path)) {
            if (self.logger) |log| log.err("Cannot place a template on storage 'local' (pvesm path {s}): {s}", .{ volid, std.mem.trim(u8, path_res.stderr, " \t\r\n") }) catch {};
            return core.Error.OperationFailed;
        }
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        if (self.logger) |log| log.info("Packing OCI bundle rootfs {s} into {s}", .{ rootfs_path, volid }) catch {};

        // tar keeps modes, ownership, symlinks and device nodes
        const tar_res = try common.runCommand(self.allocator, self.logger, &.{ "tar", "--zstd", "--numeric-owner", "-cpf", owned_path, "-C", rootfs_path, "." });
        defer {
            self.allocator.free(tar_res.stdout);
            self.allocator.free(tar_res.stderr);
        }
        if (tar_res.exit_code != 0) {
            std.fs.deleteFileAbsolute(owned_path) catch {};
            if (self.logger) |log| log.err("Packing {s} failed: {s}", .{ rootfs_path, std.mem.trim(u8, tar_res.stderr, " \t\r\n") }) catch {};
            return core.Error.OperationFailed;
        }

        return .{ .volid = volid, .path = owned_path };
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
