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

    pub fn parseBundleImageFromConfig(self: *const Self, config: *const bundle.OciBundleConfig) !?[]const u8 {
        if (config.annotations) |annotations| {
            if (annotations.get("org.opencontainers.image.ref.name")) |image_ref| {
                return try self.allocator.dupe(u8, image_ref.string);
            }
        }
        return null;
    }

    /// What a bundle's linux.resources ask of pct create. Read once the
    /// bundle is parsed, so a value nexcage cannot give pct is refused before
    /// anything is packed or created.
    pub const Resources = struct {
        /// --memory in bytes; null when the bundle sets no limit
        memory: ?u64 = null,
        /// memory.limit -1, the runtime-spec's "no limit". Proxmox has no
        /// unlimited memory for a container, so --memory is left out and pct
        /// gives the container its own default, as for a template created
        /// without one.
        memory_unlimited: bool = false,
        /// --cores; null when the bundle sets no shares
        cores: ?u32 = null,
    };

    /// The kernel's ceiling for cgroup v1 cpu.shares
    pub const max_cpu_shares = 262144;

    pub fn bundleResources(self: *const Self, cfg: *const bundle.OciBundleConfig) core.Error!Resources {
        var res = Resources{};
        if (cfg.memory_limit) |limit| {
            // runc reads 0 as no value at all, and -1 as no limit
            if (limit == -1) {
                res.memory_unlimited = true;
            } else if (limit > 0) {
                res.memory = @intCast(limit);
            } else if (limit < 0) {
                if (self.logger) |log| log.err("linux.resources.memory.limit {d} in the bundle is not a limit: it is bytes, or -1 for none", .{limit}) catch {};
                return core.Error.InvalidInput;
            }
        }
        if (cfg.cpu_shares) |shares| {
            // Read as 1024 shares to a core, as this backend always has. The
            // value was divided as a float and cast to u32 unchecked, which
            // trapped -- a root-process abort -- on shares past 4 * 10^12.
            if (shares > max_cpu_shares) {
                if (self.logger) |log| log.err("linux.resources.cpu.shares {d} in the bundle is past the kernel's maximum of {d}", .{ shares, max_cpu_shares }) catch {};
                return core.Error.InvalidInput;
            }
            if (shares > 0) res.cores = @intCast(@max(1, shares / 1024));
        }
        return res;
    }

    /// The mount points a bundle's mounts become: one pct property string
    /// each, `<source>,mp=<destination>` and what the mount's options ask
    /// for (`ro=1`, `mountoptions=`), for `pct set --mpN`. Checked once
    /// the bundle is parsed, so a mount nexcage cannot express is refused
    /// before anything is packed or created; the caller frees the strings.
    ///
    /// These were appended as raw lines to /etc/pve/lxc/<vmid>.conf, so a
    /// newline in a destination added any line the bundle liked to the
    /// container's config -- lxc.* keys and `unprivileged: 0` included --
    /// and a comma added mp properties. A path now has to be absolute and
    /// normalised, with no control character, ',' or '='.
    ///
    /// A bind mount of a host directory is what Proxmox can express. The
    /// kernel filesystems a runtime-spec bundle mounts at their usual places
    /// (proc at /proc, a tmpfs at /dev, ...) are the container's own, which
    /// LXC and the container's init set up, so they are left out. Any other
    /// mount is refused.
    pub fn bundleMountPoints(self: *const Self, mounts: []const bundle.MountConfig) core.Error![][]u8 {
        var specs = std.ArrayListUnmanaged([]u8){};
        errdefer {
            for (specs.items) |s| self.allocator.free(s);
            specs.deinit(self.allocator);
        }
        for (mounts, 0..) |m, i| {
            const dest = m.destination orelse {
                if (self.logger) |log| log.err("mounts[{d}] in the bundle has no destination", .{i}) catch {};
                return core.Error.InvalidInput;
            };
            if (!isBindMount(m)) {
                const kind = std.zig.fmtString(m.type orelse "no type");
                if (isContainerOwnMount(dest)) {
                    if (self.logger) |log| log.debug("mounts[{d}] ({f} at {s}) is the container's own; LXC and its init mount it", .{ i, kind, dest }) catch {};
                    continue;
                }
                if (self.logger) |log| log.err("mounts[{d}] in the bundle ({f} at \"{f}\"): the Proxmox LXC backend can only bind-mount a host directory into a container", .{ i, kind, std.zig.fmtString(dest) }) catch {};
                return core.Error.InvalidInput;
            }
            const source = m.source orelse {
                if (self.logger) |log| log.err("mounts[{d}] in the bundle is a bind mount with no source", .{i}) catch {};
                return core.Error.InvalidInput;
            };
            try self.checkMountPath(i, "source", source);
            try self.checkMountPath(i, "destination", dest);
            if (std.mem.eql(u8, dest, "/")) {
                if (self.logger) |log| log.err("mounts[{d}] in the bundle would cover the container's root", .{i}) catch {};
                return core.Error.InvalidInput;
            }
            // Proxmox takes a source under /dev/ for a block device and
            // mounts the filesystem on it, which is not a bind mount.
            if (std.mem.startsWith(u8, source, "/dev/")) {
                if (self.logger) |log| log.err("mounts[{d}] binds {s}; Proxmox mounts a source under /dev/ as a device's filesystem, not as a bind mount", .{ i, source }) catch {};
                return core.Error.InvalidInput;
            }
            const spec = try self.mountPointSpec(i, source, dest, m.options orelse &.{});
            errdefer self.allocator.free(spec);
            try specs.append(self.allocator, spec);
        }
        return specs.toOwnedSlice(self.allocator);
    }

    /// One mount point's property string, with what its options ask for.
    /// Proxmox mounts a bind mount point with `mount -o bind`, remounts it
    /// read-only for `ro=1` and checks that it is, and passes `mountoptions`
    /// from nosuid, nodev, noexec and noatime (pve-container's
    /// mountpoint_mount). An option it has nothing for is refused rather
    /// than dropped: dropping them made a mount the bundle asked to be
    /// read-only and nosuid writable and setuid.
    fn mountPointSpec(self: *const Self, i: usize, source: []const u8, dest: []const u8, options: []const []const u8) core.Error![]u8 {
        var read_only = false;
        var flags: [bind_flags.len][]const u8 = undefined;
        var n_flags: usize = 0;
        for (options) |opt| {
            switch (bindOption(opt) orelse {
                if (self.logger) |log| log.err("mounts[{d}] in the bundle asks for \"{f}\", which a Proxmox bind mount cannot do: it takes ro, nosuid, nodev, noexec and noatime", .{ i, std.zig.fmtString(opt) }) catch {};
                return core.Error.InvalidInput;
            }) {
                .none => {},
                .read_only => read_only = true,
                .flag => |f| {
                    for (flags[0..n_flags]) |have| {
                        if (std.mem.eql(u8, have, f)) break;
                    } else {
                        flags[n_flags] = f;
                        n_flags += 1;
                    }
                },
            }
        }
        var out = std.ArrayListUnmanaged(u8){};
        errdefer out.deinit(self.allocator);
        const w = out.writer(self.allocator);
        try w.print("{s},mp={s}", .{ source, dest });
        if (read_only) try w.writeAll(",ro=1");
        for (flags[0..n_flags], 0..) |f, n| try w.print("{s}{s}", .{ if (n == 0) ",mountoptions=" else ";", f });
        return out.toOwnedSlice(self.allocator);
    }

    fn checkMountPath(self: *const Self, i: usize, which: []const u8, path: []const u8) core.Error!void {
        const problem = mountPathProblem(path) orelse return;
        if (self.logger) |log| log.err("mounts[{d}] in the bundle: the {s} \"{f}\" {s}", .{ i, which, std.zig.fmtString(path), problem }) catch {};
        return core.Error.InvalidInput;
    }

    /// Gives a container created from a bundle its mount points, with one
    /// `pct set`: Proxmox checks each property string as its API does and
    /// writes the config itself. Not on pct create: Proxmox mounts every
    /// mount point before it unpacks the template (mount_all in create_vm),
    /// so the rootfs would be unpacked into the host's directories.
    pub fn applyMountPoints(self: *const Self, vmid: []const u8, specs: []const []const u8) !void {
        if (specs.len == 0) return;
        var args = std.ArrayListUnmanaged([]const u8){};
        defer args.deinit(self.allocator);
        var flags = std.ArrayListUnmanaged([]u8){};
        defer {
            for (flags.items) |f| self.allocator.free(f);
            flags.deinit(self.allocator);
        }
        try args.appendSlice(self.allocator, &.{ "pct", "set", vmid });
        for (specs, 0..) |spec, i| {
            const flag = try std.fmt.allocPrint(self.allocator, "--mp{d}", .{i});
            flags.append(self.allocator, flag) catch |err| {
                self.allocator.free(flag);
                return err;
            };
            try args.appendSlice(self.allocator, &.{ flag, spec });
        }
        const res = try common.runCommand(self.allocator, self.logger, args.items);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("pct set {s} refused the bundle's mount points: {s}", .{ vmid, std.mem.trim(u8, res.stderr, " \t\r\n") }) catch {};
            return core.Error.OperationFailed;
        }
    }
};

/// A bind mount, as runc reads one: type "bind", or "bind" or "rbind" among
/// the options.
fn isBindMount(m: bundle.MountConfig) bool {
    if (m.type) |t| if (std.mem.eql(u8, t, "bind")) return true;
    for (m.options orelse &.{}) |opt| {
        if (std.mem.eql(u8, opt, "bind") or std.mem.eql(u8, opt, "rbind")) return true;
    }
    return false;
}

const BindOption = union(enum) {
    /// Nothing to add to the mount point
    none,
    /// ro=1
    read_only,
    /// One of mountoptions'
    flag: []const u8,
};

/// The mountoptions Proxmox applies to a bind mount, of the ones it takes
const bind_flags = [_][]const u8{ "nosuid", "nodev", "noexec", "noatime" };

/// What a bind mount's option means for its mount point, or null when
/// Proxmox has nothing for it. Proxmox binds non-recursively, so there are
/// no mounts below the source in the container: "rbind" shows less than it
/// asks for, never more, and each recursive form ("rro", "rnosuid", ...)
/// covers all the mount there is, the same as the plain one. LXC keeps a
/// container's mounts from propagating to the host, which is what the
/// private and slave modes ask for; shared ones would need the opposite.
fn bindOption(opt: []const u8) ?BindOption {
    const plain = [_][]const u8{ "bind", "rbind", "rw", "rrw", "private", "rprivate", "slave", "rslave" };
    for (plain) |p| if (std.mem.eql(u8, opt, p)) return .none;
    if (std.mem.eql(u8, opt, "ro") or std.mem.eql(u8, opt, "rro")) return .read_only;
    for (bind_flags) |f| {
        if (std.mem.eql(u8, opt, f)) return .{ .flag = f };
        if (opt.len == f.len + 1 and opt[0] == 'r' and std.mem.eql(u8, opt[1..], f)) return .{ .flag = f };
    }
    return null;
}

/// Where a runtime-spec bundle mounts the container's own kernel
/// filesystems. A system container gets these from LXC (/proc, /sys, its
/// cgroups, /dev and /dev/pts) and from its init (/dev/shm, /dev/mqueue).
fn isContainerOwnMount(dest: []const u8) bool {
    const own = [_][]const u8{ "/proc", "/sys", "/sys/fs/cgroup", "/dev", "/dev/pts", "/dev/shm", "/dev/mqueue" };
    for (own) |p| if (std.mem.eql(u8, dest, p)) return true;
    return false;
}

/// Why `path` cannot go into a pct mount-point property string, or null
/// when it can. It has to be absolute and normalised -- no empty, "." or
/// ".." component and no trailing slash -- and free of control characters,
/// and of ',' and '=', which separate the property string's keys.
fn mountPathProblem(path: []const u8) ?[]const u8 {
    if (path.len == 0 or path[0] != '/') return "is not an absolute path";
    for (path) |c| {
        if (c < 0x20 or c == 0x7f) return "contains a control character";
        if (c == ',' or c == '=') return "contains ',' or '=', which pct would read as another property";
    }
    if (path.len == 1) return null;
    var it = std.mem.splitScalar(u8, path[1..], '/');
    while (it.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, ".."))
            return "is not a normalised path: an empty, '.' or '..' component, or a trailing '/'";
    }
    return null;
}

/// A bundle directory under a test's tmpDir holding `config_json` and an
/// empty rootfs/; returns its absolute path, which the caller frees.
fn testBundle(tmp: *std.testing.TmpDir, config_json: []const u8) ![]u8 {
    try tmp.dir.makePath("rootfs");
    try tmp.dir.writeFile(.{ .sub_path = "config.json", .data = config_json });
    return tmp.dir.realpathAlloc(std.testing.allocator, ".");
}

test "a config.json with a mount, arg or env entry of the wrong type is refused, not crashed on" {
    const cases = [_][]const u8{
        \\{"root":{"path":"rootfs"},"mounts":[1]}
        ,
        \\{"root":{"path":"rootfs"},"mounts":[{"destination":"/a","source":"/b","type":"bind"},"x"]}
        ,
        \\{"root":{"path":"rootfs"},"mounts":[null]}
        ,
        \\{"root":{"path":"rootfs"},"mounts":[{"destination":5,"source":"/b"}]}
        ,
        \\{"root":{"path":"rootfs"},"process":{"args":["/bin/sh",1]}}
        ,
        \\{"root":{"path":"rootfs"},"process":{"env":["A=1",{}]}}
        ,
    };
    for (cases) |json| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const path = try testBundle(&tmp, json);
        defer std.testing.allocator.free(path);
        var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
        try std.testing.expectError(error.InvalidConfigFormat, parser.parseBundle(path));
    }
}

test "well-formed mounts still parse, and free what they hold" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testBundle(&tmp,
        \\{"root":{"path":"rootfs"},"process":{"args":["/sbin/init"],"env":["A=1"]},
        \\ "mounts":[{"destination":"/proc","type":"proc","source":"proc"},{"destination":"/data","type":"bind","source":"/srv/data"}]}
    );
    defer std.testing.allocator.free(path);
    var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
    var cfg = try parser.parseBundle(path);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(usize, 2), cfg.mounts.?.len);
    try std.testing.expectEqualStrings("/srv/data", cfg.mounts.?[1].source.?);
    try std.testing.expectEqualStrings("/sbin/init", cfg.process_args.?[0]);
}

fn testProcessor() OciProcessor {
    return OciProcessor.init(std.testing.allocator, null, .{ .allocator = std.testing.allocator });
}

test "memory.limit -1 is no limit, and leaves --memory out; another negative is refused" {
    const proc = testProcessor();
    var cfg = bundle.OciBundleConfig{ .allocator = std.testing.allocator, .rootfs_path = "" };

    cfg.memory_limit = -1;
    const unlimited = try proc.bundleResources(&cfg);
    try std.testing.expect(unlimited.memory_unlimited and unlimited.memory == null);

    cfg.memory_limit = 1 << 30;
    try std.testing.expectEqual(@as(?u64, 1 << 30), (try proc.bundleResources(&cfg)).memory);

    // runc reads 0 as no value
    cfg.memory_limit = 0;
    const zero = try proc.bundleResources(&cfg);
    try std.testing.expect(!zero.memory_unlimited and zero.memory == null);

    cfg.memory_limit = -5;
    try std.testing.expectError(core.Error.InvalidInput, proc.bundleResources(&cfg));
}

test "cpu.shares past the kernel's maximum is refused, not cast" {
    const proc = testProcessor();
    var cfg = bundle.OciBundleConfig{ .allocator = std.testing.allocator, .rootfs_path = "" };

    cfg.cpu_shares = 5_000_000_000_000;
    try std.testing.expectError(core.Error.InvalidInput, proc.bundleResources(&cfg));
    cfg.cpu_shares = std.math.maxInt(u64);
    try std.testing.expectError(core.Error.InvalidInput, proc.bundleResources(&cfg));

    cfg.cpu_shares = OciProcessor.max_cpu_shares;
    try std.testing.expectEqual(@as(?u32, 256), (try proc.bundleResources(&cfg)).cores);
    cfg.cpu_shares = 2;
    try std.testing.expectEqual(@as(?u32, 1), (try proc.bundleResources(&cfg)).cores);
    cfg.cpu_shares = 0;
    try std.testing.expectEqual(@as(?u32, null), (try proc.bundleResources(&cfg)).cores);
}

test "memory.limit and cpu.shares of the wrong type are refused, not dropped" {
    const cases = [_][]const u8{
        \\{"root":{"path":"rootfs"},"linux":{"resources":{"memory":{"limit":1.5e9}}}}
        ,
        \\{"root":{"path":"rootfs"},"linux":{"resources":{"memory":{"limit":"1G"}}}}
        ,
        \\{"root":{"path":"rootfs"},"linux":{"resources":{"cpu":{"shares":-2}}}}
        ,
        \\{"root":{"path":"rootfs"},"linux":{"resources":{"cpu":{"shares":36893488147419103232}}}}
        ,
    };
    for (cases) |json| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const path = try testBundle(&tmp, json);
        defer std.testing.allocator.free(path);
        var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
        try std.testing.expectError(error.InvalidConfigFormat, parser.parseBundle(path));
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testBundle(&tmp,
        \\{"root":{"path":"rootfs"},"linux":{"resources":{"memory":{"limit":-1},"cpu":{"shares":18446744073709551615}}}}
    );
    defer std.testing.allocator.free(path);
    var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
    var cfg = try parser.parseBundle(path);
    defer cfg.deinit();
    try std.testing.expectEqual(@as(?i64, -1), cfg.memory_limit);
    try std.testing.expectEqual(@as(?u64, std.math.maxInt(u64)), cfg.cpu_shares);
}

test "a mount path goes into a pct property string only when absolute, normalised and free of separators" {
    for ([_][]const u8{ "/", "/srv/data", "/srv/my data", "/a:b" }) |ok| {
        try std.testing.expectEqual(@as(?[]const u8, null), mountPathProblem(ok));
    }
    for ([_][]const u8{ "", "srv/data", "/srv/", "//srv", "/srv//data", "/srv/./data", "/srv/..", "/srv/../etc", "/x\nlxc.hook.pre-start: /bin/sh", "/x\r", "/x\x7f", "/srv/a,ro=0", "/srv/a=b" }) |bad| {
        try std.testing.expect(mountPathProblem(bad) != null);
    }
}

test "a bundle's bind mounts become pct property strings; its own kernel filesystems are left out" {
    const proc = testProcessor();
    const mounts = [_]bundle.MountConfig{
        .{ .allocator = std.testing.allocator, .destination = "/proc", .type = "proc", .source = "proc" },
        .{ .allocator = std.testing.allocator, .destination = "/dev/pts", .type = "devpts", .source = "devpts" },
        .{ .allocator = std.testing.allocator, .destination = "/data", .type = "bind", .source = "/srv/data" },
        .{ .allocator = std.testing.allocator, .destination = "/srv/logs", .type = "bind", .source = "/var/log/app" },
    };
    const specs = try proc.bundleMountPoints(&mounts);
    defer {
        for (specs) |s| std.testing.allocator.free(s);
        std.testing.allocator.free(specs);
    }
    try std.testing.expectEqual(@as(usize, 2), specs.len);
    try std.testing.expectEqualStrings("/srv/data,mp=/data", specs[0]);
    try std.testing.expectEqualStrings("/var/log/app,mp=/srv/logs", specs[1]);
}

test "a mount pct cannot take as a bind mount is refused, and nothing leaks" {
    const proc = testProcessor();
    const a = std.testing.allocator;
    const cases = [_][2]bundle.MountConfig{
        // the second mount is bad, so the first one's string has to be freed
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/x\nunprivileged: 0", .type = "bind", .source = "/srv/b" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/b", .type = "bind", .source = "/srv/b,mp=/etc" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/data", .type = "tmpfs", .source = "tmpfs" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/disk", .type = "bind", .source = "/dev/sda1" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/", .type = "bind", .source = "/srv/root" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .type = "bind", .source = "/srv/b" } },
        .{ .{ .allocator = a, .destination = "/a", .type = "bind", .source = "/srv/a" }, .{ .allocator = a, .destination = "/b", .type = "bind" } },
    };
    for (cases) |mounts| {
        try std.testing.expectError(core.Error.InvalidInput, proc.bundleMountPoints(&mounts));
    }
}

test "a bind mount's ro, nosuid, nodev and noexec reach its mount point" {
    const proc = testProcessor();
    const a = std.testing.allocator;
    const Case = struct { opts: []const []const u8, want: []const u8, type: ?[]const u8 = "bind" };
    const cases = [_]Case{
        .{ .opts = &.{ "rbind", "ro", "nosuid", "nodev", "noexec" }, .want = "/srv/a,mp=/a,ro=1,mountoptions=nosuid;nodev;noexec" },
        .{ .opts = &.{ "rbind", "rprivate" }, .want = "/srv/a,mp=/a" },
        .{ .opts = &.{ "rw", "noatime" }, .want = "/srv/a,mp=/a,mountoptions=noatime" },
        // "bind" among the options makes it a bind mount whatever the type
        .{ .opts = &.{ "bind", "rro", "rnosuid", "nosuid" }, .want = "/srv/a,mp=/a,ro=1,mountoptions=nosuid", .type = "none" },
        .{ .opts = &.{"rbind"}, .want = "/srv/a,mp=/a", .type = null },
    };
    for (cases) |c| {
        const mounts = [_]bundle.MountConfig{.{ .allocator = a, .destination = "/a", .type = c.type, .source = "/srv/a", .options = c.opts }};
        const specs = try proc.bundleMountPoints(&mounts);
        defer {
            for (specs) |s| a.free(s);
            a.free(specs);
        }
        try std.testing.expectEqualStrings(c.want, specs[0]);
    }
}

test "a bind mount option Proxmox has nothing for is refused, not dropped" {
    const proc = testProcessor();
    for ([_][]const u8{ "rshared", "shared", "unbindable", "strictatime", "relatime", "suid", "exec", "dev", "size=1m", "nosymfollow", "idmap", "ro\n" }) |opt| {
        const opts = [_][]const u8{ "rbind", opt };
        const mounts = [_]bundle.MountConfig{.{ .allocator = std.testing.allocator, .destination = "/a", .type = "bind", .source = "/srv/a", .options = &opts }};
        try std.testing.expectError(core.Error.InvalidInput, proc.bundleMountPoints(&mounts));
    }
}

test "mount options are parsed from config.json, and a malformed list is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testBundle(&tmp,
        \\{"root":{"path":"rootfs"},"mounts":[{"destination":"/a","type":"bind","source":"/srv/a","options":["rbind","ro","nosuid"]}]}
    );
    defer std.testing.allocator.free(path);
    var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
    var cfg = try parser.parseBundle(path);
    defer cfg.deinit();
    const opts = cfg.mounts.?[0].options.?;
    try std.testing.expectEqual(@as(usize, 3), opts.len);
    try std.testing.expectEqualStrings("ro", opts[1]);

    for ([_][]const u8{
        \\{"root":{"path":"rootfs"},"mounts":[{"destination":"/a","source":"/b","options":"ro"}]}
        ,
        \\{"root":{"path":"rootfs"},"mounts":[{"destination":"/a","source":"/b","options":["ro",1]}]}
        ,
    }) |json| {
        var bad = std.testing.tmpDir(.{});
        defer bad.cleanup();
        const bad_path = try testBundle(&bad, json);
        defer std.testing.allocator.free(bad_path);
        try std.testing.expectError(error.InvalidConfigFormat, parser.parseBundle(bad_path));
    }
}
