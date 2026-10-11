const std = @import("std");
const core = @import("core");
const common = @import("common.zig");
const oci_spec = @import("oci_spec");
const bundle = oci_spec.runtime.bundle;

/// A template archive packed from an OCI bundle's rootfs, for pct create.
///
/// It is made in a directory of its own, 0700 and named at random, under
/// $TMPDIR or /var/tmp: on disk, since a rootfs can be large, and out of the
/// template store. It used to be written to storage `local` as
/// nexcage-<name>-<time>.tar.zst with tar's umask, so 0644: while pct create
/// ran, and for good when nexcage was interrupted, any local user could read
/// files the image kept 0600, Proxmox users could create containers from it,
/// and `images` listed it. pct create takes a file path from root
/// (PVE::Storage::check_volume_access), so the store is not needed.
pub const BundleTemplate = struct {
    /// The private directory
    dir: []u8,
    /// The archive in it, the path pct create is given
    path: []u8,

    /// Deletes the archive and its directory once pct create has unpacked
    /// it, or failed to. A signal that ends nexcage first is handled by
    /// interrupt_cleanup, which stays armed until both are gone: disarmed
    /// first, a signal in between left the archive behind. One that comes
    /// after the deletes only unlinks what is no longer there.
    pub fn remove(self: *BundleTemplate, allocator: std.mem.Allocator, logger: ?*core.LogContext) void {
        removeArchive(self.dir, self.path, logger);
        interrupt_cleanup.disarm();
        allocator.free(self.dir);
        allocator.free(self.path);
    }
};

/// Deletes an archive and its private directory. What cannot be deleted is
/// said; it stays where only root can read it.
fn removeArchive(dir: []const u8, path: []const u8, logger: ?*core.LogContext) void {
    std.fs.deleteFileAbsolute(path) catch |err| if (err != error.FileNotFound) {
        if (logger) |log| log.warn("cannot remove the bundle's archive {s} ({s})", .{ path, @errorName(err) }) catch {};
    };
    std.fs.deleteDirAbsolute(dir) catch |err| if (err != error.FileNotFound) {
        if (logger) |log| log.warn("cannot remove {s} ({s})", .{ dir, @errorName(err) }) catch {};
    };
}

/// Removes the bundle's archive when SIGINT, SIGTERM or SIGHUP ends nexcage
/// while the archive is packed or read: a Zig defer runs on return, not on
/// a signal. SIGKILL cannot be caught; what it leaves is in a directory
/// only root can enter, and systemd-tmpfiles ages /var/tmp out.
const interrupt_cleanup = struct {
    const signals = [_]u8{ std.posix.SIG.INT, std.posix.SIG.TERM, std.posix.SIG.HUP };
    var file_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var dir_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    var previous: [signals.len]std.posix.Sigaction = undefined;
    var armed = std.atomic.Value(bool).init(false);

    fn arm(dir: []const u8, file: []const u8) error{NameTooLong}!void {
        if (dir.len >= dir_buf.len or file.len >= file_buf.len) return error.NameTooLong;
        @memcpy(dir_buf[0..dir.len], dir);
        dir_buf[dir.len] = 0;
        @memcpy(file_buf[0..file.len], file);
        file_buf[file.len] = 0;
        armed.store(true, .seq_cst);
        const act = std.posix.Sigaction{ .handler = .{ .handler = handle }, .mask = std.posix.sigemptyset(), .flags = 0 };
        for (signals, 0..) |sig, i| {
            std.posix.sigaction(sig, &act, &previous[i]);
            // A signal the caller ignores -- SIGINT for a background job of
            // a shell -- stays ignored rather than starting to end nexcage
            if (previous[i].handler.handler == std.posix.SIG.IGN) std.posix.sigaction(sig, &previous[i], null);
        }
    }

    fn disarm() void {
        if (!armed.swap(false, .seq_cst)) return;
        for (signals, 0..) |sig, i| std.posix.sigaction(sig, &previous[i], null);
    }

    fn handle(sig: i32) callconv(.c) void {
        if (armed.swap(false, .seq_cst)) {
            _ = std.posix.system.unlink(&file_buf);
            _ = std.posix.system.rmdir(&dir_buf);
        }
        // End the way the signal would have ended nexcage without this. Should
        // raise fail, create goes on and fails on the archive it no longer has.
        const default = std.posix.Sigaction{ .handler = .{ .handler = std.posix.SIG.DFL }, .mask = std.posix.sigemptyset(), .flags = 0 };
        std.posix.sigaction(@intCast(sig), &default, null);
        std.posix.raise(@intCast(sig)) catch {};
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

    /// Packs a bundle's rootfs into an archive for pct create, in a private
    /// directory (see BundleTemplate). The rootfs is used as it is, so it has
    /// to boot as a system container, init included.
    ///
    /// Before this, create logged "Successfully converted OCI bundle to
    /// template" and gave pct a template name that nothing had written.
    pub fn createTemplateFromBundle(self: *Self, rootfs_path: []const u8, container_name: []const u8) !BundleTemplate {
        const dir = try self.makePrivateDir(try self.archiveBase(), container_name);
        errdefer self.allocator.free(dir);
        const path = try std.fs.path.join(self.allocator, &.{ dir, "rootfs.tar.zst" });
        errdefer self.allocator.free(path);
        interrupt_cleanup.arm(dir, path) catch {
            removeArchive(dir, path, self.logger);
            if (self.logger) |log| log.err("{s} is too long a path for the bundle's archive", .{path}) catch {};
            return core.Error.InvalidInput;
        };
        // On an error below these run in reverse: the archive is deleted
        // before the handler is disarmed, as in BundleTemplate.remove
        errdefer interrupt_cleanup.disarm();
        errdefer removeArchive(dir, path, self.logger);

        // Made here, new and 0600, in a directory no one else can enter; tar
        // truncates it and keeps the mode
        const fd = std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true }, 0o600) catch |err| {
            if (self.logger) |log| log.err("cannot create {s} ({s})", .{ path, @errorName(err) }) catch {};
            return core.Error.OperationFailed;
        };
        std.posix.close(fd);

        if (self.logger) |log| log.info("Packing OCI bundle rootfs {s} into {s}", .{ rootfs_path, path }) catch {};

        // tar keeps modes, ownership, symlinks and device nodes
        const tar_res = try common.runCommand(self.allocator, self.logger, &.{ "tar", "--zstd", "--numeric-owner", "-cpf", path, "-C", rootfs_path, "." });
        defer {
            self.allocator.free(tar_res.stdout);
            self.allocator.free(tar_res.stderr);
        }
        if (tar_res.exit_code != 0) {
            if (self.logger) |log| log.err("Packing {s} failed: {s}", .{ rootfs_path, std.mem.trim(u8, tar_res.stderr, " \t\r\n") }) catch {};
            return core.Error.OperationFailed;
        }

        return .{ .dir = dir, .path = path };
    }

    /// Where the archive's directory is made: $TMPDIR, as tar and mktemp
    /// read it, else /var/tmp. Only a directory no one else can swap things
    /// in -- owned by root or by nexcage's user, and sticky if others may
    /// write to it -- since root writes the archive there by path.
    fn archiveBase(self: *const Self) ![]const u8 {
        const tmpdir = std.posix.getenv("TMPDIR") orelse "";
        const base = if (tmpdir.len > 0) tmpdir else "/var/tmp";
        const st = std.posix.fstatat(std.posix.AT.FDCWD, base, 0) catch |err| {
            if (self.logger) |log| log.err("{s}, where the bundle's archive is packed, cannot be used ({s}); TMPDIR names another", .{ base, @errorName(err) }) catch {};
            return core.Error.OperationFailed;
        };
        const others_write = st.mode & 0o022 != 0;
        const sticky = st.mode & 0o1000 != 0;
        if (!std.fs.path.isAbsolute(base) or !std.posix.S.ISDIR(st.mode) or
            (st.uid != 0 and st.uid != std.posix.geteuid()) or (others_write and !sticky))
        {
            if (self.logger) |log| log.err("{s} is not a safe place for the bundle's archive: it has to be an absolute directory owned by root, and sticky if others can write to it (TMPDIR names another)", .{base}) catch {};
            return core.Error.OperationFailed;
        }
        return base;
    }

    /// A new directory, 0700, under `base`, named for the container and 64
    /// random bits. mkdir fails rather than reuse what is already there, a
    /// symlink included.
    fn makePrivateDir(self: *const Self, base: []const u8, container_name: []const u8) ![]u8 {
        var attempts: usize = 0;
        while (true) : (attempts += 1) {
            var random: [8]u8 = undefined;
            std.crypto.random.bytes(&random);
            const dir = try std.fmt.allocPrint(self.allocator, "{s}/nexcage-bundle-{s}-{s}", .{ base, container_name, std.fmt.bytesToHex(random, .lower) });
            std.posix.mkdir(dir, 0o700) catch |err| {
                self.allocator.free(dir);
                if (err == error.PathAlreadyExists and attempts < 8) continue;
                if (self.logger) |log| log.err("cannot make a directory for the bundle's archive under {s} ({s})", .{ base, @errorName(err) }) catch {};
                return core.Error.OperationFailed;
            };
            return dir;
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

    /// Says, in one warning, which of the confinement a bundle asks for this
    /// backend does not apply. Proxmox confines every container with its own
    /// AppArmor profile, capability set, seccomp filter and device rules, and
    /// pct has no way to take a bundle's instead; the container was created
    /// as if the bundle's had been applied, and nothing said otherwise. Not
    /// refused: `runc spec` writes capabilities, masked paths and
    /// noNewPrivileges into every bundle, so refusing would refuse them all.
    pub fn warnUnappliedConfinement(self: *const Self, bundle_path: []const u8, asked: bundle.Confinement) !void {
        const names = try unappliedConfinement(self.allocator, asked) orelse return;
        defer self.allocator.free(names);
        if (self.logger) |log| log.warn("{s} in {s}/config.json: not applied on the Proxmox LXC backend, which confines the container with Proxmox's own AppArmor profile, capabilities, seccomp filter and device rules instead. --runtime crun applies a bundle's own", .{ names, bundle_path }) catch {};
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

/// The fields of `asked` that ask for something, comma-separated, or null
/// when none does.
fn unappliedConfinement(allocator: std.mem.Allocator, asked: bundle.Confinement) !?[]u8 {
    var names = std.ArrayListUnmanaged(u8){};
    errdefer names.deinit(allocator);
    inline for (std.meta.fields(bundle.Confinement)) |f| {
        if (@field(asked, f.name)) {
            if (names.items.len > 0) try names.appendSlice(allocator, ", ");
            try names.appendSlice(allocator, f.name);
        }
    }
    if (names.items.len == 0) return null;
    return try names.toOwnedSlice(allocator);
}

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

test "the confinement a bundle asks for is named, and a bundle that asks for none gets no list" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try testBundle(&tmp,
        \\{"root":{"path":"rootfs","readonly":true},
        \\ "process":{"args":["/bin/sh"],"capabilities":{"bounding":["CAP_KILL"]},"noNewPrivileges":true,"apparmorProfile":"","rlimits":[]},
        \\ "linux":{"seccomp":{"defaultAction":"SCMP_ACT_ERRNO"},"maskedPaths":["/proc/kcore"],"readonlyPaths":[],
        \\  "resources":{"devices":[{"allow":false,"access":"rwm"}]}}}
    );
    defer std.testing.allocator.free(path);
    var parser = bundle.OciBundleParser.init(std.testing.allocator, null);
    var cfg = try parser.parseBundle(path);
    defer cfg.deinit();
    const names = (try unappliedConfinement(std.testing.allocator, cfg.confinement)).?;
    defer std.testing.allocator.free(names);
    // An empty profile, list or false asks for nothing, and is not named
    try std.testing.expectEqualStrings("process.capabilities, process.noNewPrivileges, root.readonly, linux.seccomp, linux.maskedPaths, linux.resources.devices", names);

    try std.testing.expectEqual(@as(?[]u8, null), try unappliedConfinement(std.testing.allocator, .{}));
}
