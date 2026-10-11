const std = @import("std");
const core = @import("core");
const validation = @import("core").validation;
const ffi = @import("libcrun_ffi.zig");
const c_stdio = @cImport({
    @cInclude("stdio.h");
});
const c_string = @cImport({
    @cInclude("string.h");
});

/// Crun backend driver using libcrun ABI (not CLI)
pub const CrunDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    /// Where libcrun keeps container state. crun's own default is /run/crun,
    /// and a container engine always passes its own directory with --root; the
    /// default is kept for a caller that gives none.
    state_root: []const u8 = "/run/crun",
    /// --console-socket and --pid-file, as the caller gave them. Borrowed for
    /// the length of the command; initContext copies them NUL-terminated.
    console_socket: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    /// --systemd-cgroup: libcrun's context has the field; containerd sends the
    /// flag when it is configured with SystemdCgroup.
    systemd_cgroup: bool = false,
    /// The isolation profile create applies (ADR-005): the bundle's spec is
    /// narrowed and marked with its name before libcrun sees it.
    profile: ?*const core.profile.Profile = null,
    /// `exec --detach`: libcrun returns once the process is started instead of
    /// waiting for it. An engine sends it together with --console-socket.
    detach: bool = false,
    /// What shapes the process spec `exec` writes when the command came from a
    /// command line rather than from `--process <file>`.
    exec_tty: bool = false,
    exec_cwd: ?[]const u8 = null,
    exec_user: ?[]const u8 = null,
    exec_env: ?[]const []const u8 = null,
    _console_socket_z: ?[:0]u8 = null,
    _pid_file_z: ?[:0]u8 = null,
    // Stored strings and context to keep them valid during usage
    _state_root_z: ?[:0]u8 = null,
    _bundle_z: ?[:0]u8 = null,
    _id_z: ?[:0]u8 = null,
    _context: ?*ffi.Libcrun.Context = null,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .state_root = core.state_root.crun(),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._context) |ctx| self.allocator.destroy(ctx);
        if (self._state_root_z) |s| self.allocator.free(s);
        if (self._console_socket_z) |cs| self.allocator.free(cs);
        if (self._pid_file_z) |pf| self.allocator.free(pf);
        if (self._bundle_z) |b| self.allocator.free(b);
        if (self._id_z) |i| self.allocator.free(i);
    }

    /// Initialize libcrun context with stored strings (reuses context if available)
    fn initContext(self: *Self, bundle_path: []const u8, container_id: []const u8) !*ffi.Libcrun.Context {
        // Reuse or create context
        const ctx = if (self._context) |existing_ctx| existing_ctx else blk: {
            const new_ctx = try self.allocator.create(ffi.Libcrun.Context);
            self._context = new_ctx;
            break :blk new_ctx;
        };

        // Zero-initialize context
        ctx.* = std.mem.zeroes(ffi.Libcrun.Context);

        // allocPrintSentinel, not allocPrint plus a re-slice: writing the NUL
        // by hand allocates one more byte than the slice that was kept, so
        // freeing it in deinit aborted with "Allocation size N does not match
        // free size N-1". Nothing reached this code until the crun backend was
        // actually run, so the mismatch sat here unseen.
        if (self._state_root_z == null) {
            self._state_root_z = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{self.state_root}, 0);
        }
        ctx.state_root = self._state_root_z.?.ptr;

        if (bundle_path.len > 0) {
            if (self._bundle_z) |b| self.allocator.free(b);
            self._bundle_z = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{bundle_path}, 0);
            ctx.bundle = self._bundle_z.?.ptr;
        } else {
            ctx.bundle = null;
        }

        if (self._id_z) |i| self.allocator.free(i);
        self._id_z = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        ctx.id = self._id_z.?.ptr;

        // A spec with process.terminal set cannot be created without a console
        // socket: libcrun answers "use --console-socket with create when a
        // terminal is used". The fields were already in the context struct and
        // simply never filled in.
        if (self.console_socket) |path| {
            if (self._console_socket_z) |cs| self.allocator.free(cs);
            self._console_socket_z = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{path}, 0);
            ctx.console_socket = self._console_socket_z.?.ptr;
        } else {
            ctx.console_socket = null;
        }

        if (self.pid_file) |path| {
            if (self._pid_file_z) |pf| self.allocator.free(pf);
            self._pid_file_z = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{path}, 0);
            ctx.pid_file = self._pid_file_z.?.ptr;
        } else {
            ctx.pid_file = null;
        }

        ctx.systemd_cgroup = self.systemd_cgroup;
        ctx.detach = self.detach;

        // Initialize optional fields (already zeroed by zeroes, which sets pointers to null)
        // Additional initialization not needed - zeroed context is sufficient

        return ctx;
    }

    /// Log what libcrun actually said, then release the error.
    ///
    /// This used to report every failure as "libcrun <operation> failed",
    /// because the error struct was declared opaque in the FFI: the message
    /// libcrun had written was released unread. It is bound now, so the reason
    /// reaches the caller — which is the difference between "create failed"
    /// and "the container already exists".
    fn handleError(self: *Self, err_ptr: *?*ffi.Libcrun.Error, operation: []const u8) !void {
        if (err_ptr.*) |e| {
            const message: []const u8 = if (e.msg != null) std.mem.span(@as([*:0]const u8, @ptrCast(e.msg))) else "";
            if (self.logger) |log| {
                if (message.len == 0) {
                    log.err("libcrun {s} failed", .{operation}) catch {};
                } else if (e.status != 0) {
                    // crun prints "msg: strerror(status)"; status is an errno
                    const reason = std.mem.span(c_string.strerror(e.status));
                    log.err("libcrun {s}: {s}: {s}", .{ operation, message, reason }) catch {};
                } else {
                    log.err("libcrun {s}: {s}", .{ operation, message }) catch {};
                }
            }
            // Frees the message as well, so nothing may read it after this
            _ = ffi.Libcrun.libcrun_error_release(err_ptr);
            // Always OperationFailed, and the message above carries the
            // reason. Mapping e.status onto a specific error looked tempting
            // and is not reliable: crun_error_wrap keeps whatever status the
            // innermost error set, and several paths format the errno into the
            // message and leave status at 0 — "container `x` does not exist:
            // open `/run/crun/x/status`: No such file or directory" arrives
            // with status 0. An OCI runtime exits 1 on failure anyway.
            return core.Error.OperationFailed;
        }
        if (self.logger) |log| log.err("libcrun {s} failed without an error", .{operation}) catch {};
        return core.Error.OperationFailed;
    }

    /// The CVE-2019-5736 protection, for the commands that need it: before
    /// nexcage makes a container's process (create) or joins a container
    /// (exec), it re-executes from a sealed copy of its own binary, so that a
    /// process in the container that gets hold of /proc/<pid>/exe finds the
    /// copy and not the file on the host. libcrun did this from a constructor,
    /// before main, on every run of the binary, so `version`, `--help` and
    /// every Proxmox LXC command needed /proc and open_tree, a bind mount or
    /// an executable memfd as well, and died without a word under a seccomp
    /// filter that kills on open_tree. build.zig compiles that constructor out
    /// and this calls the same function, first, before the command has done
    /// anything a second run would repeat. It does not return the first time;
    /// the second, from the copy, it returns at once.
    fn runFromSealedCopy(self: *Self) core.Error!void {
        const ret = ffi.Libcrun.ensure_cloned_binary();
        if (ret >= 0) return;
        const errno: i64 = -@as(i64, ret);
        const cause = switch (errno) {
            @intFromEnum(std.posix.E.NOTRECOVERABLE) => "/proc/self/exe cannot be opened; is /proc mounted?",
            @intFromEnum(std.posix.E.INVAL) => "/proc/self/cmdline cannot be read; is /proc mounted?",
            @intFromEnum(std.posix.E.IO) => "no sealed copy of the binary could be made: open_tree, a bind mount and an executable memfd were all refused",
            @intFromEnum(std.posix.E.NOEXEC) => "the sealed copy could not be executed (vm.memfd_noexec, or a filter on execveat)",
            else => "it failed in a way libcrun does not name",
        };
        if (self.logger) |log| log.err("cannot run from a sealed copy of nexcage before touching a container (the CVE-2019-5736 protection): {s}", .{cause}) catch {};
        return core.Error.OperationFailed;
    }

    /// Create an OCI container using libcrun
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        try self.runFromSealedCopy();
        if (self.logger) |log| {
            try log.info("Creating OCI container with libcrun: {s}", .{config.name});
        }

        // Validate container name
        try validation.SecurityValidation.validateContainerId(config.name);

        // The bundle the caller named. A container engine passes its own
        // directory — containerd keeps one per task under
        // /run/containerd/… — so deriving the path from the container id, as
        // this did, looked in a place nothing had written.
        const requested = config.image orelse {
            if (self.logger) |log| {
                try log.err("crun needs a bundle: nexcage create {s} --bundle <dir>", .{config.name});
            }
            return core.Error.InvalidInput;
        };
        // validateBundlePath returns a fresh path and does not own its input,
        // so pass the borrowed one: the allocPrint this used to hand it was
        // never freed.
        const bundle_path = try validation.PathSecurity.validateBundlePath(requested, self.allocator);
        defer self.allocator.free(bundle_path);

        var bundle_dir = std.fs.cwd().openDir(bundle_path, .{ .iterate = false }) catch |err| {
            if (self.logger) |log| {
                try log.err("Bundle directory missing for {s}: {}", .{ bundle_path, err });
            }
            return core.Error.FileNotFound;
        };
        defer bundle_dir.close();

        const config_path = try validation.PathSecurity.secureJoin(self.allocator, bundle_path, "config.json");
        defer self.allocator.free(config_path);

        const spec = std.fs.cwd().readFileAlloc(self.allocator, config_path, 16 * 1024 * 1024) catch |err| {
            if (self.logger) |log| {
                try log.err("config.json not found for {s}: {}", .{ config.name, err });
            }
            return core.Error.FileNotFound;
        };
        defer self.allocator.free(spec);

        const config_path_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{config_path}, 0);
        defer self.allocator.free(config_path_c);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        // Without a profile libcrun reads the file. With one, it is given the
        // spec the profile narrowed, which it keeps as the container's
        // config.json, so `state` reports the profile from it. Either way a
        // bundle that claims a profile is refused (ADR-005).
        var why: core.profile.Refusal = .{};
        const narrowed = core.profile.prepare(self.allocator, spec, self.profile, &why) catch |err| switch (err) {
            // The bundle, not the command line: "invalid input", not a
            // pointer to --help.
            error.ProfileRefused => {
                if (self.logger) |log| log.err("{s}", .{why.text()}) catch {};
                return core.Error.ValidationError;
            },
            else => return err,
        };
        defer if (narrowed) |n| self.allocator.free(n);
        // The spec libcrun is about to be given, before it does arithmetic on
        // its memory values (checkMemory).
        try self.checkMemoryJson("the bundle's config.json", narrowed orelse spec, .spec);
        const container = if (narrowed) |n| blk: {
            const narrowed_z = try self.allocator.dupeZ(u8, n);
            defer self.allocator.free(narrowed_z);
            break :blk ffi.Libcrun.libcrun_container_load_from_memory(narrowed_z.ptr, &err_ptr) orelse {
                try self.handleError(&err_ptr, "container_load_from_memory");
                return;
            };
        } else ffi.Libcrun.libcrun_container_load_from_file(config_path_c.ptr, &err_ptr) orelse {
            try self.handleError(&err_ptr, "container_load_from_file");
            return;
        };
        defer ffi.Libcrun.libcrun_container_free(container);

        // crun and runc both chdir into the bundle before they create a
        // container, and libcrun needs them to: an OCI spec's root.path is
        // normally relative ("rootfs"), and it is resolved against the working
        // directory rather than against the bundle in the context.
        // containerd's shim serves a whole pod, so it runs the runtime from
        // the *sandbox's* directory while --bundle names the container's own.
        // Without this the container's rootfs was looked for inside the
        // sandbox's, where /bin/sh really is absent: only /pause lives there.
        bundle_dir.setAsCwd() catch |err| {
            if (self.logger) |log| {
                try log.err("Cannot enter bundle {s}: {}", .{ bundle_path, err });
            }
            return core.Error.OperationFailed;
        };

        // Initialize context (context and strings cleaned up in deinit)
        const ctx = try self.initContext(bundle_path, config.name);

        // Create container using libcrun API
        var err_ptr2: ?*ffi.Libcrun.Error = null;
        const ret = ffi.Libcrun.libcrun_container_create(ctx, container, 0, &err_ptr2);
        if (ret != 0) {
            try self.handleError(&err_ptr2, "container_create");
            return;
        }

        if (self.logger) |log| {
            try log.info("Successfully created OCI container with libcrun: {s}", .{config.name});
        }
    }

    pub fn run(self: *Self, config: core.types.SandboxConfig) !void {
        try self.create(config);
        errdefer self.delete(config.name) catch {};
        try self.start(config.name);
    }

    /// Start an OCI container using libcrun
    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting OCI container with libcrun: {s}", .{container_id});
        }

        // Validate container ID
        try validation.SecurityValidation.validateContainerId(container_id);

        // Initialize minimal context (only state_root and id needed for start)
        const ctx = try self.initContext("", container_id);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        // Start container using libcrun API
        const ret = ffi.Libcrun.libcrun_container_start(ctx, id_c.ptr, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_start");
            return;
        }

        if (self.logger) |log| {
            try log.info("Successfully started OCI container with libcrun: {s}", .{container_id});
        }
    }

    /// Stop an OCI container using libcrun (sends SIGTERM to the init)
    pub fn stop(self: *Self, container_id: []const u8) !void {
        try self.kill(container_id, "TERM", false);
        if (self.logger) |log| {
            try log.info("Successfully stopped OCI container with libcrun: {s}", .{container_id});
        }
    }

    /// Kill an OCI container using libcrun
    pub fn kill(self: *Self, container_id: []const u8, signal: []const u8, all: bool) !void {
        if (self.logger) |log| {
            try log.info("Killing OCI container with libcrun: {s} signal {s}", .{ container_id, signal });
        }

        try validation.SecurityValidation.validateContainerId(container_id);

        // Initialize minimal context
        const ctx = try self.initContext("", container_id);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        // libcrun parses the text again, with rules of its own: names only in
        // upper case, and numbers with strtol, which stops at the first
        // character that is not a digit. So it is given the number nexcage
        // validated, in decimal, which both read the same way; a name in any
        // case, as the help promises, reaches it as that number.
        const signo = core.signals.parse(signal) orelse {
            if (self.logger) |log| log.err("unknown signal '{s}'; use a name such as TERM or SIGKILL, or a number from 1 to {d}", .{ signal, core.signals.max }) catch {};
            return core.Error.InvalidInput;
        };
        const signal_c = try std.fmt.allocPrintSentinel(self.allocator, "{d}", .{signo}, 0);
        defer self.allocator.free(signal_c);

        // --all is libcrun_container_killall: every process in the cgroup
        // rather than the init alone. It used to be dropped before it reached
        // here, so `kill --all` signalled only init and said nothing about it.
        const ret = if (all)
            ffi.Libcrun.libcrun_container_killall(ctx, id_c.ptr, signal_c.ptr, &err_ptr)
        else
            ffi.Libcrun.libcrun_container_kill(ctx, id_c.ptr, signal_c.ptr, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, if (all) "container_killall" else "container_kill");
            return;
        }
    }

    /// Delete an OCI container using libcrun
    pub fn delete(self: *Self, container_id: []const u8, force: bool) !void {
        if (self.logger) |log| {
            try log.info("Deleting OCI container with libcrun: {s}", .{container_id});
        }

        try validation.SecurityValidation.validateContainerId(container_id);

        // Initialize minimal context
        const ctx = try self.initContext("", container_id);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        // Asked before libcrun removes the state directory, which is the only
        // record of how far a create got.
        const unfinished = force and self.createDidNotFinish(container_id);

        // force was hardcoded false, so `delete --force` was accepted and
        // then not forced. libcrun takes it as the fourth argument.
        const ret = ffi.Libcrun.libcrun_container_delete(ctx, null, id_c.ptr, force, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_delete");
            return;
        }
        if (unfinished) self.removeLeftoverCgroup(container_id);

        if (self.logger) |log| {
            try log.info("Successfully deleted OCI container with libcrun: {s}", .{container_id});
        }
    }

    /// Whether libcrun began to create this container and never finished: a
    /// create killed half way (SIGKILL, OOM, a UBSan trap) leaves the state
    /// directory without the status file create writes last, and libcrun's
    /// delete then removes the directory and nothing else, so the cgroup it
    /// had made stayed, one per attempt. Only the cgroup that is certainly
    /// this container's is in question: the default one libcrun's cgroupfs
    /// manager makes, /sys/fs/cgroup/<id> on cgroup v2, which needs a
    /// config.json kept in the state directory that names no cgroupsPath
    /// and no --systemd-cgroup.
    fn createDidNotFinish(self: *Self, container_id: []const u8) bool {
        if (self.systemd_cgroup) return false;
        var dir = std.fs.cwd().openDir(self.state_root, .{}) catch return false;
        defer dir.close();
        var kept_dir = dir.openDir(container_id, .{ .no_follow = true }) catch return false;
        defer kept_dir.close();
        // The status file is the last thing create writes.
        if (kept_dir.access("status", .{})) |_| return false else |err| if (err != error.FileNotFound) return false;
        const kept = kept_dir.readFileAlloc(self.allocator, "config.json", 16 * 1024 * 1024) catch return false;
        defer self.allocator.free(kept);
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, kept, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        const linux = parsed.value.object.get("linux") orelse return true;
        if (linux != .object) return false;
        const path = linux.object.get("cgroupsPath") orelse return true;
        return path == .null;
    }

    /// rmdir of the cgroup an unfinished create left, and nothing more: no
    /// recursion and no kill. The kernel refuses to remove a cgroup that
    /// still has processes or child cgroups, and that one is left in place
    /// and named, since nothing here can prove they are this container's.
    fn removeLeftoverCgroup(self: *Self, container_id: []const u8) void {
        std.fs.cwd().access("/sys/fs/cgroup/cgroup.controllers", .{}) catch return;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "/sys/fs/cgroup/{s}", .{container_id}) catch return;
        std.posix.rmdir(path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => {
                if (self.logger) |log| log.warn("'{s}' was never fully created, and its cgroup {s} could not be removed ({s}); it is left in place", .{ container_id, path, @errorName(err) }) catch {};
                return;
            },
        };
        if (self.logger) |log| log.info("removed {s}, the cgroup an unfinished create of '{s}' left behind", .{ path, container_id }) catch {};
    }

    /// Execute a command in a running container (best-effort; may be limited by libcrun API)
    /// Print the container's OCI state, as the runtime-spec defines it.
    ///
    /// libcrun writes the JSON itself, to a FILE*, so the output is what
    /// `crun state` gives for the same container rather than a second
    /// rendering of the same fields that could drift from it. The LXC backend
    /// has to compose its own because pct has no such call.
    pub fn state(self: *Self, container_id: []const u8) !void {
        try validation.SecurityValidation.validateContainerId(container_id);

        const ctx = try self.initContext("", container_id);

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        var err_ptr: ?*ffi.Libcrun.Error = null;
        const out: ?*anyopaque = @ptrCast(c_stdio.stdout);
        const ret = ffi.Libcrun.libcrun_container_state(ctx, id_c.ptr, out, &err_ptr);
        // libcrun buffers through the FILE*; without this the JSON can arrive
        // after whatever the process writes next, or not at all on exit.
        _ = c_stdio.fflush(c_stdio.stdout);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_state");
            return;
        }
    }

    /// The features document for this build, as the runtime-spec defines it.
    /// The caller owns the bytes.
    ///
    /// Every value in it comes from `libcrun_container_get_features`, which is
    /// where `crun features` gets its own answer. Writing the document by hand
    /// was the alternative, and a features document is a set of promises to a
    /// kubelet: each line would have been an assertion about someone else's
    /// compile-time configuration, free to drift from it without a sound.
    ///
    /// The field order and shapes follow crun's own output, down to the two
    /// checkpoint annotations being strings rather than booleans, so that a
    /// caller which special-cases crun's document sees no difference.
    pub fn featuresJson(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const ctx = try self.initContext("", "");

        var err_ptr: ?*ffi.Libcrun.Error = null;
        var info_ptr: ?*ffi.Libcrun.FeaturesInfo = null;
        const ret = ffi.Libcrun.libcrun_container_get_features(ctx, &info_ptr, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_get_features");
            return core.Error.OperationFailed;
        }
        const info = info_ptr orelse {
            if (self.logger) |log| {
                try log.err("libcrun reported no features and no error", .{});
            }
            return core.Error.OperationFailed;
        };
        defer freeFeatures(info);

        // FeaturesInfo is a hand-written mirror of a C layout, so it is only
        // correct for the crun it was written against. A wrong layout shows up
        // as rubbish in the first string read, and a features document full of
        // rubbish is worse for a caller than no command at all.
        const version_min = cSpan(info.oci_version_min) orelse "";
        if (version_min.len == 0 or !std.ascii.isDigit(version_min[0])) {
            if (self.logger) |log| {
                try log.err("libcrun's features do not start with a version: the vendored crun and libcrun_ffi.zig's struct_features_info_s have diverged", .{});
            }
            return core.Error.OperationFailed;
        }

        var out = std.ArrayListUnmanaged(u8){};
        errdefer out.deinit(allocator);
        const w = out.writer(allocator);

        try w.writeAll("{\n  \"ociVersionMin\": ");
        try core.json.writeString(w, version_min);
        try w.writeAll(",\n  \"ociVersionMax\": ");
        try core.json.writeString(w, cSpan(info.oci_version_max) orelse "");
        try w.writeAll(",\n  \"hooks\": ");
        try writeCStrArray(w, info.hooks);
        try w.writeAll(",\n  \"mountOptions\": ");
        try writeCStrArray(w, info.mount_options);

        const lx = info.linux;
        try w.writeAll(",\n  \"linux\": {\n    \"namespaces\": ");
        try writeCStrArray(w, lx.namespaces);
        try w.writeAll(",\n    \"capabilities\": ");
        try writeCStrArray(w, lx.capabilities);
        try w.print(
            ",\n    \"cgroup\": {{ \"v1\": {}, \"v2\": {}, \"systemd\": {}, \"systemdUser\": {} }}",
            .{ lx.cgroup.v1, lx.cgroup.v2, lx.cgroup.systemd, lx.cgroup.systemd_user },
        );
        try w.print(",\n    \"seccomp\": {{ \"enabled\": {}", .{lx.seccomp.enabled});
        // crun emits actions and operators only when it has them, and leaves
        // archs out of the document altogether. Both are copied rather than
        // improved on: this is meant to be crun's answer, not a second one.
        if (lx.seccomp.actions != null) {
            try w.writeAll(", \"actions\": ");
            try writeCStrArray(w, lx.seccomp.actions);
        }
        if (lx.seccomp.operators != null) {
            try w.writeAll(", \"operators\": ");
            try writeCStrArray(w, lx.seccomp.operators);
        }
        try w.writeAll(" }");
        try w.print(",\n    \"apparmor\": {{ \"enabled\": {} }}", .{lx.apparmor.enabled});
        try w.print(",\n    \"selinux\": {{ \"enabled\": {} }}", .{lx.selinux.enabled});
        try w.print(",\n    \"mountExtensions\": {{ \"idmap\": {{ \"enabled\": {} }} }}", .{lx.mount_ext.idmap.enabled});
        try w.print(",\n    \"intelRdt\": {{ \"enabled\": {} }}", .{lx.intel_rdt.enabled});
        try w.print(",\n    \"netDevices\": {{ \"enabled\": {} }}", .{lx.net_devices.enabled});
        // memoryPolicy is the vendored fork's own addition, and it emits the
        // two arrays only when it has them.
        try w.writeAll(",\n    \"memoryPolicy\": {");
        if (lx.memory_policy.mode != null) {
            try w.writeAll(" \"modes\": ");
            try writeCStrArray(w, lx.memory_policy.mode);
        }
        if (lx.memory_policy.flags != null) {
            if (lx.memory_policy.mode != null) try w.writeAll(",");
            try w.writeAll(" \"flags\": ");
            try writeCStrArray(w, lx.memory_policy.flags);
        }
        try w.writeAll(" }");
        try w.writeAll("\n  }");

        const ann = info.annotations;
        try w.writeAll(",\n  \"annotations\": {");
        var first_annotation = true;
        if (cSpan(ann.io_github_seccomp_libseccomp_version)) |v| {
            if (v.len > 0) try writeAnnotation(w, &first_annotation, "io.github.seccomp.libseccomp.version", v);
        }
        const checkpoint = if (ann.run_oci_crun_checkpoint_enabled) "true" else "false";
        try writeAnnotation(w, &first_annotation, "org.opencontainers.runc.checkpoint.enabled", checkpoint);
        try writeAnnotation(w, &first_annotation, "run.oci.crun.checkpoint.enabled", checkpoint);
        if (cSpan(ann.run_oci_crun_commit)) |v| try writeAnnotation(w, &first_annotation, "run.oci.crun.commit", v);
        if (cSpan(ann.run_oci_crun_version)) |v| try writeAnnotation(w, &first_annotation, "run.oci.crun.version", v);
        try writeAnnotation(w, &first_annotation, "run.oci.crun.wasm", if (ann.run_oci_crun_wasm) "true" else "false");
        // Which binary answered, and through which backend. A caller that
        // finds crun's version here should still be able to tell that it is
        // talking to nexcage.
        try writeAnnotation(w, &first_annotation, "io.cageforge.nexcage.version", core.version.getVersion());
        try writeAnnotation(w, &first_annotation, "io.cageforge.nexcage.backend", "crun");
        try w.writeAll("\n  }");

        try w.writeAll(",\n  \"potentiallyUnsafeConfigAnnotations\": ");
        try writeCStrArray(w, info.potentially_unsafe_annotations);
        try w.writeAll("\n}\n");

        return out.toOwnedSlice(allocator);
    }

    /// Freeze every process in the container, and thaw them again. This is the
    /// cgroup freezer: the processes stay in memory exactly where they were,
    /// which is what the runtime-spec means by paused -- not a checkpoint.
    pub fn pause(self: *Self, container_id: []const u8) !void {
        return self.freeze(container_id, true);
    }

    pub fn resume_(self: *Self, container_id: []const u8) !void {
        return self.freeze(container_id, false);
    }

    /// Change a running container's resource limits: a runtime-spec
    /// linux.resources document, which is what a container engine sends and
    /// libcrun reads itself, or the settings a command line named, handed
    /// over in crun's own section/name form.
    pub fn update(self: *Self, container_id: []const u8, resources_json: ?[]const u8, values: []const core.types.ResourceUpdate) !void {
        try validation.SecurityValidation.validateContainerId(container_id);
        try self.holdToProfile(container_id, resources_json, values);
        if (resources_json) |doc| {
            try self.checkMemoryJson("the resources document", doc, .resources);
        } else {
            var m: [3]MemoryValue = .{ .absent, .absent, .absent };
            for (values) |v| {
                if (!std.mem.eql(u8, v.section, "memory")) continue;
                for (memory_fields, 0..) |name, i| {
                    if (std.mem.eql(u8, v.name, name)) m[i] = MemoryValue.ofText(v.value);
                }
            }
            try self.checkMemory("the update", m);
        }

        const ctx = try self.initContext("", container_id);
        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);
        var err_ptr: ?*ffi.Libcrun.Error = null;

        if (resources_json) |doc| {
            // libcrun strlen()s the document and ignores the length: it gets a
            // copy that ends in NUL (see the binding).
            const doc_z = try self.allocator.dupeZ(u8, doc);
            defer self.allocator.free(doc_z);
            const ret = ffi.Libcrun.libcrun_container_update(ctx, id_c.ptr, doc_z.ptr, doc_z.len, &err_ptr);
            if (ret < 0) {
                try self.handleError(&err_ptr, "container_update");
                return core.Error.OperationFailed;
            }
            return;
        }

        // One C string per field, alive until the call has returned.
        var strings = std.ArrayListUnmanaged([:0]u8){};
        defer {
            for (strings.items) |str| self.allocator.free(str);
            strings.deinit(self.allocator);
        }
        const c_values = try self.allocator.alloc(ffi.Libcrun.UpdateValue, values.len);
        defer self.allocator.free(c_values);
        for (values, 0..) |v, i| {
            const section = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{v.section}, 0);
            try strings.append(self.allocator, section);
            const name = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{v.name}, 0);
            try strings.append(self.allocator, name);
            const value = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{v.value}, 0);
            try strings.append(self.allocator, value);
            c_values[i] = .{ .section = section.ptr, .name = name.ptr, .numeric = v.numeric, .value = value.ptr };
        }
        const ret = ffi.Libcrun.libcrun_container_update_from_values(ctx, id_c.ptr, c_values.ptr, c_values.len, &err_ptr);
        if (ret < 0) {
            try self.handleError(&err_ptr, "container_update_from_values");
            return core.Error.OperationFailed;
        }
    }

    /// An update of a container made under an isolation profile stays within
    /// the caps the profile had at create (core.profile.boundUpdate). The
    /// container's stored config.json is where they are recorded; read here
    /// the way boundProcessFile reads it for exec.
    fn holdToProfile(self: *Self, container_id: []const u8, resources_json: ?[]const u8, values: []const core.types.ResourceUpdate) !void {
        const stored_path = try std.fs.path.join(self.allocator, &.{ self.state_root, container_id, "config.json" });
        defer self.allocator.free(stored_path);
        // No stored config is no container, which is libcrun's to report.
        const stored = std.fs.cwd().readFileAlloc(self.allocator, stored_path, 16 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return self.cannotRead(stored_path, err),
        };
        defer self.allocator.free(stored);

        var why: core.profile.Refusal = .{};
        core.profile.boundUpdate(self.allocator, stored, resources_json, values, &why) catch |err| switch (err) {
            error.ProfileRefused => {
                if (self.logger) |log| log.err("{s}", .{why.text()}) catch {};
                return core.Error.ValidationError;
            },
            else => return err,
        };
    }

    /// memory.limit, swap and reservation as libcrun is about to be given
    /// them, checked before it does arithmetic on them. libcrun is compiled
    /// with UBSan in trap mode (see build.zig), so an int64 overflow in it is
    /// SIGILL in the root process, and write_memory_swap computes `swap -
    /// limit` once swap is positive and no less than the limit: a bundle with
    /// a limit of -9223372036854775808 and swap 1 killed create half way,
    /// leaving a cgroup behind, and the same document killed update after
    /// memory.max had been rewritten. -1 is no limit and 0 or more a number of
    /// bytes; anything else is refused, and so is a limit and swap whose
    /// difference does not fit in 64 bits, which -1 and the largest swap is.
    /// `m` is limit, swap and reservation, in memory_fields' order.
    fn checkMemory(self: *Self, what: []const u8, m: [3]MemoryValue) core.Error!void {
        for (m, memory_fields) |v, name| switch (v) {
            .absent => {},
            .whole => |n| if (n < -1) {
                if (self.logger) |log| log.err("{s}: memory.{s} is {d}; a memory value is a number of bytes, or -1 for no limit", .{ what, name, n }) catch {};
                return core.Error.ValidationError;
            },
            .other => {
                if (self.logger) |log| log.err("{s}: memory.{s} is not a whole number that fits in 64 bits", .{ what, name }) catch {};
                return core.Error.ValidationError;
            },
        };
        if (m[0] == .whole and m[1] == .whole) {
            const limit = m[0].whole;
            const swap = m[1].whole;
            if (swap > 0 and swap >= limit) _ = std.math.sub(i64, swap, limit) catch {
                if (self.logger) |log| log.err("{s}: memory.swap {d} less memory.limit {d} does not fit in 64 bits", .{ what, swap, limit }) catch {};
                return core.Error.ValidationError;
            };
        }
    }

    /// checkMemory on a JSON document: the linux.resources object itself, as
    /// update sends it, or a whole spec, as create hands it over.
    fn checkMemoryJson(self: *Self, what: []const u8, json: []const u8, shape: enum { resources, spec }) core.Error!void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json, .{}) catch |err| switch (err) {
            error.OutOfMemory => return core.Error.OutOfMemory,
            else => {
                if (self.logger) |log| log.err("{s} is not valid JSON ({s})", .{ what, @errorName(err) }) catch {};
                return core.Error.ValidationError;
            },
        };
        defer parsed.deinit();
        var resources = parsed.value;
        if (shape == .spec) for ([_][]const u8{ "linux", "resources" }) |key| {
            if (resources != .object) return;
            resources = resources.object.get(key) orelse return;
        };
        if (resources != .object) return;
        const memory = resources.object.get("memory") orelse return;
        // Not an object: libcrun's parser refuses that itself.
        if (memory != .object) return;
        var m: [3]MemoryValue = undefined;
        for (memory_fields, 0..) |name, i| m[i] = MemoryValue.ofJson(memory.object.get(name));
        return self.checkMemory(what, m);
    }

    fn freeze(self: *Self, container_id: []const u8, on: bool) !void {
        try validation.SecurityValidation.validateContainerId(container_id);

        const ctx = try self.initContext("", container_id);
        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        var err_ptr: ?*ffi.Libcrun.Error = null;
        const ret = if (on)
            ffi.Libcrun.libcrun_container_pause(ctx, id_c.ptr, &err_ptr)
        else
            ffi.Libcrun.libcrun_container_unpause(ctx, id_c.ptr, &err_ptr);
        if (ret < 0) {
            try self.handleError(&err_ptr, if (on) "container_pause" else "container_unpause");
            return core.Error.OperationFailed;
        }
    }

    /// The host PIDs of the processes in the container, as `crun ps` reports
    /// them: read from the container's cgroup, children included. The caller
    /// owns the slice.
    ///
    /// Kubernetes asks for this. On a node under k3s the kubelet's containerd
    /// sends `ps --format json <id>` for the task's PID list, gets
    /// `unknown command 'ps'`, and says nothing about it in the journal -- the
    /// pod runs regardless, which is why this went unnoticed until the command
    /// lines were recorded.
    pub fn pids(self: *Self, container_id: []const u8, allocator: std.mem.Allocator) ![]i32 {
        try validation.SecurityValidation.validateContainerId(container_id);

        const ctx = try self.initContext("", container_id);

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);

        var raw: [*c]c_int = null;
        var err_ptr: ?*ffi.Libcrun.Error = null;
        const ret = ffi.Libcrun.libcrun_container_read_pids(ctx, id_c.ptr, true, &raw, &err_ptr);
        if (ret < 0) {
            try self.handleError(&err_ptr, "container_read_pids");
            return core.Error.OperationFailed;
        }
        defer if (raw != null) std.c.free(@ptrCast(raw));

        // A 0 ends the array. A container whose cgroup holds nothing is an
        // empty list rather than an error: that is what a container being torn
        // down looks like, and crun answers the same way.
        var count: usize = 0;
        if (raw != null) {
            while (raw[count] != 0) : (count += 1) {}
        }

        const out = try allocator.alloc(i32, count);
        var i: usize = 0;
        while (i < count) : (i += 1) out[i] = raw[i];
        return out;
    }

    /// runc's `exec`, in both the shapes it comes in: `--process <file>` from a
    /// container engine, and a command typed after the container's name.
    ///
    /// Both end in libcrun_container_exec_process_file, which takes the path of
    /// a file holding the OCI process spec. For `--process` that is the
    /// caller's own file, handed over untouched; for a command line nexcage
    /// writes the same shape to a file of its own in the container's state
    /// directory and removes it afterwards (writeSpecFile). See the binding
    /// for why a path rather than the struct entry points.
    pub fn exec(self: *Self, container_id: []const u8, argv: []const []const u8, process_file: ?[]const u8) !void {
        // Before the process spec is written: a re-execution would leave it.
        try self.runFromSealedCopy();
        try validation.SecurityValidation.validateContainerId(container_id);

        var written: ?[]u8 = null;
        defer if (written) |path| {
            std.fs.cwd().deleteFile(path) catch {};
            self.allocator.free(path);
        };

        const spec_path = if (process_file) |given| blk: {
            const bounded = try self.boundProcessFile(container_id, given) orelse break :blk given;
            written = bounded;
            break :blk @as([]const u8, bounded);
        } else blk: {
            if (argv.len == 0) {
                if (self.logger) |log| {
                    try log.err("exec needs a command, or --process <file> with the process spec", .{});
                }
                return core.Error.InvalidInput;
            }
            const path = try self.writeProcessSpec(container_id, argv);
            written = path;
            break :blk @as([]const u8, path);
        };

        const ctx = try self.initContext("", container_id);

        const id_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{container_id}, 0);
        defer self.allocator.free(id_c);
        const path_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{spec_path}, 0);
        defer self.allocator.free(path_c);

        var err_ptr: ?*ffi.Libcrun.Error = null;
        const ret = ffi.Libcrun.libcrun_container_exec_process_file(ctx, id_c.ptr, path_c.ptr, &err_ptr);
        if (ret < 0) {
            try self.handleError(&err_ptr, "container_exec");
            return core.Error.OperationFailed;
        }

        // An OCI runtime's `exec` exits with the status of the command it ran,
        // and libcrun ends in wait_for_process, which returns exactly that. The
        // Proxmox LXC backend carries it out the same way.
        core.exit_status.propagated = if (ret > 255) 255 else @intCast(ret);
    }

    /// An engine's process file, cut to the bounding set of a container made
    /// under a profile (core.profile.boundExec) and written where libcrun can
    /// read it; null to hand the file over as it is. The caller owns and
    /// removes the path.
    fn boundProcessFile(self: *Self, container_id: []const u8, given: []const u8) !?[]u8 {
        const stored_path = try std.fs.path.join(self.allocator, &.{ self.state_root, container_id, "config.json" });
        defer self.allocator.free(stored_path);
        // Either file missing is libcrun's to report, as it does today.
        const stored = std.fs.cwd().readFileAlloc(self.allocator, stored_path, 16 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return self.cannotRead(stored_path, err),
        };
        defer self.allocator.free(stored);
        const process = std.fs.cwd().readFileAlloc(self.allocator, given, 16 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return null,
            else => return self.cannotRead(given, err),
        };
        defer self.allocator.free(process);

        var why: core.profile.Refusal = .{};
        const bounded = core.profile.boundExec(self.allocator, process, stored, &why) catch |err| switch (err) {
            error.ProfileRefused => {
                if (self.logger) |log| log.err("{s}", .{why.text()}) catch {};
                return core.Error.ValidationError;
            },
            else => return err,
        } orelse return null;
        defer self.allocator.free(bounded);
        return try self.writeSpecFile(container_id, bounded);
    }

    /// A file that could not be read, as an error of the command's own set.
    /// The command registry casts every error into core.types.Error, and one
    /// outside it -- IsDir, AccessDenied -- aborted the process with "invalid
    /// error code" instead of failing the command.
    fn cannotRead(self: *Self, path: []const u8, err: anyerror) core.Error {
        if (err == error.OutOfMemory) return core.Error.OutOfMemory;
        if (self.logger) |log| log.err("cannot read {s}: {s}", .{ path, @errorName(err) }) catch {};
        return core.Error.OperationFailed;
    }

    /// `bytes` in a new file in the container's own libcrun state directory,
    /// where libcrun reads it. The caller owns and removes the path.
    ///
    /// This used to be /tmp/nexcage-exec-<pid>.json. Anyone can make entries
    /// in /tmp and the next pids are easy to guess, so a local user who left
    /// directories under a few thousand of those names made every exec that
    /// drew one fail -- by aborting the root process, as removing the
    /// directory gave error.IsDir, which nothing expected. The state directory
    /// is libcrun's, made 0700 by root, and goes with the container, so even
    /// a file an exec killed half way leaves behind is removed with it. The
    /// name is random besides, the file is made with O_EXCL and O_NOFOLLOW,
    /// an entry that is already there is neither removed nor followed --
    /// another name is drawn -- and every failure is an error of the command's
    /// own set.
    fn writeSpecFile(self: *Self, container_id: []const u8, bytes: []const u8) ![]u8 {
        const dir_path = try std.fs.path.join(self.allocator, &.{ self.state_root, container_id });
        defer self.allocator.free(dir_path);
        var dir = std.fs.cwd().openDir(dir_path, .{ .no_follow = true }) catch |err| switch (err) {
            error.FileNotFound => {
                if (self.logger) |log| log.err("container '{s}' does not exist: there is no {s}", .{ container_id, dir_path }) catch {};
                return core.Error.NotFound;
            },
            else => {
                if (self.logger) |log| log.err("cannot open the container's state directory {s}: {s}", .{ dir_path, @errorName(err) }) catch {};
                return core.Error.OperationFailed;
            },
        };
        defer dir.close();

        var attempt: usize = 0;
        while (attempt < 16) : (attempt += 1) {
            var random: [8]u8 = undefined;
            std.crypto.random.bytes(&random);
            const path = try std.fmt.allocPrint(self.allocator, "{s}/nexcage-exec-{s}.json", .{ dir_path, &std.fmt.bytesToHex(random, .lower) });
            errdefer self.allocator.free(path);
            const name = path[dir_path.len + 1 ..];
            const flags: std.posix.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .NOFOLLOW = true, .CLOEXEC = true };
            const fd = std.posix.openat(dir.fd, name, flags, 0o600) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    self.allocator.free(path);
                    continue;
                },
                else => {
                    if (self.logger) |log| log.err("cannot create {s}: {s}", .{ path, @errorName(err) }) catch {};
                    return core.Error.OperationFailed;
                },
            };
            const file = std.fs.File{ .handle = fd };
            defer file.close();
            file.writeAll(bytes) catch |err| {
                // O_EXCL made it, in a directory only root writes to: ours.
                dir.deleteFile(name) catch {};
                if (self.logger) |log| log.err("cannot write {s}: {s}", .{ path, @errorName(err) }) catch {};
                return core.Error.OperationFailed;
            };
            return path;
        }
        if (self.logger) |log| log.err("no free name for the process spec in {s} after {d} tries", .{ dir_path, attempt }) catch {};
        return core.Error.OperationFailed;
    }

    /// The OCI process spec for a command given on the command line, written
    /// where libcrun can read it. The caller owns and removes the path.
    fn writeProcessSpec(self: *Self, container_id: []const u8, argv: []const []const u8) ![]u8 {
        var out = std.ArrayListUnmanaged(u8){};
        defer out.deinit(self.allocator);
        const w = out.writer(self.allocator);

        var uid: u32 = 0;
        var gid: u32 = 0;
        if (self.exec_user) |spec| {
            // runc's --user is uid[:gid]. An unparsable half is an error rather
            // than a silent 0: running as root when root was not asked for is
            // the kind of difference nobody notices until it matters.
            var parts = std.mem.splitScalar(u8, spec, ':');
            const uid_str = parts.next() orelse "";
            uid = std.fmt.parseInt(u32, uid_str, 10) catch {
                if (self.logger) |log| try log.err("--user wants uid[:gid], got '{s}'", .{spec});
                return core.Error.InvalidInput;
            };
            if (parts.next()) |gid_str| {
                gid = std.fmt.parseInt(u32, gid_str, 10) catch {
                    if (self.logger) |log| try log.err("--user wants uid[:gid], got '{s}'", .{spec});
                    return core.Error.InvalidInput;
                };
            }
        }

        try w.print("{{\"terminal\":{},\"user\":{{\"uid\":{d},\"gid\":{d}}},\"args\":[", .{ self.exec_tty, uid, gid });
        for (argv, 0..) |a, i| {
            if (i > 0) try w.writeAll(",");
            try core.json.writeString(w, a);
        }
        try w.writeAll("],\"env\":[");
        if (self.exec_env) |env| {
            for (env, 0..) |e, i| {
                if (i > 0) try w.writeAll(",");
                try core.json.writeString(w, e);
            }
        } else {
            // Without an env the exec'd process has no PATH, and `nexcage exec
            // c1 ls` fails with "executable file not found" on a container that
            // has ls. runc leaves it to the caller; a caller typing a command
            // has no way to know that is why.
            try core.json.writeString(w, "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        }
        try w.writeAll("],\"cwd\":");
        try core.json.writeString(w, self.exec_cwd orelse "/");
        try w.writeAll("}\n");

        return self.writeSpecFile(container_id, out.items);
    }

    /// Generate basic OCI config.json
    fn generateOciConfig(self: *Self, config: core.types.SandboxConfig, bundle_path: []const u8) !void {
        _ = config;

        // Validate bundle path
        const validated_bundle_path = try validation.PathSecurity.validateBundlePath(bundle_path, self.allocator);
        defer self.allocator.free(validated_bundle_path);

        const config_path = try validation.PathSecurity.secureJoin(self.allocator, validated_bundle_path, "config.json");
        defer self.allocator.free(config_path);

        const file = try std.fs.cwd().createFile(config_path, .{});
        defer file.close();

        // Minimal OCI config.json
        try file.writeAll("{\"ociVersion\":\"1.0.0\",\"process\":{\"terminal\":true,\"user\":{\"uid\":0,\"gid\":0},\"args\":[\"/bin/sh\"],\"env\":[\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"]},\"root\":{\"path\":\"rootfs\",\"readonly\":false},\"hostname\":\"container\",\"linux\":{\"namespaces\":[{\"type\":\"pid\"},{\"type\":\"network\"},{\"type\":\"ipc\"},{\"type\":\"uts\"},{\"type\":\"mount\"}]}}");
    }
};

/// The memory fields checkMemory looks at, in the order it takes them.
const memory_fields = [_][]const u8{ "limit", "swap", "reservation" };

/// A memory value as libcrun would read it. Its parser takes only an integer
/// that fits in 64 bits; json-c clamps a larger negative one to the smallest
/// int64, so a value std.json cannot hold in an i64 is `other` and refused,
/// never passed over.
const MemoryValue = union(enum) {
    absent,
    whole: i64,
    other,

    fn ofJson(v: ?std.json.Value) MemoryValue {
        const value = v orelse return .absent;
        return switch (value) {
            .null => .absent,
            .integer => |n| .{ .whole = n },
            else => .other,
        };
    }

    /// A command line's value, which update.zig has already made decimal.
    fn ofText(text: []const u8) MemoryValue {
        const digits = if (text.len > 0 and text[0] == '-') text[1..] else text;
        if (digits.len == 0) return .other;
        for (digits) |c| if (!std.ascii.isDigit(c)) return .other;
        return .{ .whole = std.fmt.parseInt(i64, text, 10) catch return .other };
    }
};

/// A C string as a slice, or null when the pointer is null.
fn cSpan(p: [*c]u8) ?[]const u8 {
    if (p == null) return null;
    return std.mem.span(p);
}

/// A NULL-terminated array of C strings, as a JSON array.
fn writeCStrArray(w: anytype, arr: [*c][*c]u8) !void {
    try w.writeAll("[");
    if (arr != null) {
        var i: usize = 0;
        while (arr[i] != null) : (i += 1) {
            if (i > 0) try w.writeAll(", ");
            try core.json.writeString(w, std.mem.span(arr[i]));
        }
    }
    try w.writeAll("]");
}

/// One `"key": "value"` of the annotations object, with the comma the previous
/// one needs. Every annotation in a features document is a string, including
/// the ones that hold "true" and "false".
fn writeAnnotation(w: anytype, first: *bool, key: []const u8, value: []const u8) !void {
    if (!first.*) try w.writeAll(",");
    first.* = false;
    try w.writeAll("\n    ");
    try core.json.writeString(w, key);
    try w.writeAll(": ");
    try core.json.writeString(w, value);
}

/// Release what libcrun_container_get_features allocated.
///
/// This is `cleanup_struct_features_free` from crun's container.h, which is a
/// static inline and so is not a symbol nexcage can call. It is copied field
/// for field on purpose, including what it does *not* free: seccomp.archs, the
/// annotation strings and potentiallyUnsafeConfigAnnotations are left alone
/// there, and freeing them here would be a guess about their ownership that
/// crun's own code does not make.
fn freeFeatures(info: *ffi.Libcrun.FeaturesInfo) void {
    freeCStr(info.oci_version_min);
    freeCStr(info.oci_version_max);
    freeCStrArray(info.hooks);
    freeCStrArray(info.mount_options);
    freeCStrArray(info.linux.namespaces);
    freeCStrArray(info.linux.capabilities);
    freeCStrArray(info.linux.seccomp.actions);
    freeCStrArray(info.linux.seccomp.operators);
    std.c.free(info);
}

fn freeCStr(p: [*c]u8) void {
    if (p != null) std.c.free(p);
}

fn freeCStrArray(arr: [*c][*c]u8) void {
    if (arr == null) return;
    var i: usize = 0;
    while (arr[i] != null) : (i += 1) std.c.free(arr[i]);
    // The array itself is a double pointer, which does not coerce to the
    // anyopaque free() takes; each element above does.
    std.c.free(@ptrCast(arr));
}

test "exec's process spec is a new 0600 file in the container's own state directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makeDir("c1");
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var driver = CrunDriver{ .allocator = allocator, .state_root = root };
    defer driver.deinit();

    const a = try driver.writeSpecFile("c1", "{\"args\":[\"true\"]}");
    defer allocator.free(a);
    const b = try driver.writeSpecFile("c1", "{}");
    defer allocator.free(b);
    // Not a name anyone can work out in advance: two writes, two names.
    try std.testing.expect(!std.mem.eql(u8, a, b));
    const dir = try std.fs.path.join(allocator, &.{ root, "c1" });
    defer allocator.free(dir);
    try std.testing.expectEqualStrings(dir, std.fs.path.dirname(a).?);
    const st = try std.fs.cwd().statFile(a);
    try std.testing.expectEqual(@as(std.fs.File.Mode, 0o600), st.mode & 0o777);
    const back = try std.fs.cwd().readFileAlloc(allocator, a, 1024);
    defer allocator.free(back);
    try std.testing.expectEqualStrings("{\"args\":[\"true\"]}", back);

    // No container, no state directory: an error of the command's own set,
    // and no file anywhere else.
    try std.testing.expectError(core.Error.NotFound, driver.writeSpecFile("c2", "{}"));
}

test "memory values libcrun would overflow on are refused before it sees them" {
    var driver = CrunDriver{ .allocator = std.testing.allocator };
    const refused = [_][]const u8{
        "{\"memory\":{\"limit\":-9223372036854775808,\"swap\":1}}",
        // json-c clamps this one to the smallest int64; std.json cannot hold it
        "{\"memory\":{\"limit\":-9223372036854775809,\"swap\":1}}",
        "{\"memory\":{\"limit\":-2}}",
        "{\"memory\":{\"reservation\":-5}}",
        "{\"memory\":{\"limit\":-1,\"swap\":9223372036854775807}}",
        "{\"memory\":{\"swap\":1.5}}",
        "{\"memory\":{\"limit\":\"64M\"}}",
    };
    for (refused) |doc| {
        driver.checkMemoryJson("t", doc, .resources) catch |err| {
            try std.testing.expectEqual(core.Error.ValidationError, err);
            continue;
        };
        std.debug.print("let through: {s}\n", .{doc});
        return error.TestExpectedRefusal;
    }
    const ok = [_][]const u8{
        "{\"memory\":{\"limit\":-1,\"swap\":-1}}",
        "{\"memory\":{\"limit\":67108864,\"swap\":134217728,\"reservation\":0}}",
        "{\"memory\":{\"limit\":null}}",
        "{\"cpu\":{\"quota\":-1}}",
        "{}",
    };
    for (ok) |doc| try driver.checkMemoryJson("t", doc, .resources);

    // A whole spec, as create hands it over.
    try std.testing.expectError(core.Error.ValidationError, driver.checkMemoryJson("t", "{\"linux\":{\"resources\":{\"memory\":{\"limit\":-9223372036854775808,\"swap\":1}}}}", .spec));
    try driver.checkMemoryJson("t", "{\"ociVersion\":\"1.0.0\",\"linux\":{\"resources\":{\"memory\":{\"limit\":1073741824}}}}", .spec);
    try driver.checkMemoryJson("t", "{\"ociVersion\":\"1.0.0\"}", .spec);

    // The command line's values.
    try std.testing.expectError(core.Error.ValidationError, driver.checkMemory("t", .{ MemoryValue.ofText("-1"), MemoryValue.ofText("9223372036854775807"), .absent }));
    try std.testing.expectError(core.Error.ValidationError, driver.checkMemory("t", .{ MemoryValue.ofText("1_0"), .absent, .absent }));
    try driver.checkMemory("t", .{ MemoryValue.ofText("67108864"), MemoryValue.ofText("201326592"), .absent });
}

test "an unfinished create has state without a status file and a config naming no cgroup path" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const cases = [_]struct { id: []const u8, config: ?[]const u8, status: bool, unfinished: bool }{
        .{ .id = "plain", .config = "{\"linux\":{\"namespaces\":[]}}", .status = false, .unfinished = true },
        .{ .id = "nulled", .config = "{\"linux\":{\"cgroupsPath\":null}}", .status = false, .unfinished = true },
        .{ .id = "finished", .config = "{\"linux\":{}}", .status = true, .unfinished = false },
        .{ .id = "elsewhere", .config = "{\"linux\":{\"cgroupsPath\":\"/kubepods/x\"}}", .status = false, .unfinished = false },
        .{ .id = "noconfig", .config = null, .status = false, .unfinished = false },
    };
    for (cases) |c| {
        var dir = try tmp.dir.makeOpenPath(c.id, .{});
        defer dir.close();
        if (c.config) |text| try dir.writeFile(.{ .sub_path = "config.json", .data = text });
        if (c.status) try dir.writeFile(.{ .sub_path = "status", .data = "{}" });
    }
    const root = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root);
    var driver = CrunDriver{ .allocator = allocator, .state_root = root };
    for (cases) |c| {
        if (driver.createDidNotFinish(c.id) != c.unfinished) {
            std.debug.print("{s}: expected {}\n", .{ c.id, c.unfinished });
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expect(!driver.createDidNotFinish("missing"));
    driver.systemd_cgroup = true;
    try std.testing.expect(!driver.createDidNotFinish("plain"));
}
