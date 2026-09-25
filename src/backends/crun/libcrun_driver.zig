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
            // An explicit --root wins; without one this stays crun's default
            // rather than nexcage's, because the state here is libcrun's.
            .state_root = if (core.state_root.isDefault()) "/run/crun" else core.state_root.get(),
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

    /// Create an OCI container using libcrun
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
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

        const config_file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
            if (self.logger) |log| {
                try log.err("config.json not found for {s}: {}", .{ config.name, err });
            }
            return core.Error.FileNotFound;
        };
        config_file.close();

        const config_path_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{config_path}, 0);
        defer self.allocator.free(config_path_c);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        // Load container from config file
        const container = ffi.Libcrun.libcrun_container_load_from_file(config_path_c.ptr, &err_ptr) orelse {
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

        const signal_c = try std.fmt.allocPrintSentinel(self.allocator, "{s}", .{signal}, 0);
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

        // force was hardcoded false, so `delete --force` was accepted and
        // then not forced. libcrun takes it as the fourth argument.
        const ret = ffi.Libcrun.libcrun_container_delete(ctx, null, id_c.ptr, force, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_delete");
            return;
        }

        if (self.logger) |log| {
            try log.info("Successfully deleted OCI container with libcrun: {s}", .{container_id});
        }
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

    /// Not implemented. libcrun exposes an exec entry point, but no binding
    /// for it exists in libcrun_ffi.zig, so there is nothing to call. This
    /// used to build a C argv, discard it and return OperationNotSupported
    /// after logging "not wired"; the argv construction also did not compile
    /// once anything reached it, because a null cannot go into a list of
    /// non-optional pointers.
    pub fn exec(self: *Self, container_id: []const u8, argv: []const []const u8) !void {
        _ = argv;
        if (self.logger) |log| {
            log.err("exec is not implemented for the crun backend ({s}): libcrun's exec is not bound", .{container_id}) catch {};
        }
        return core.Error.UnsupportedOperation;
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
