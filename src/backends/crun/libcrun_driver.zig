const std = @import("std");
const core = @import("core");
const validation = @import("core").validation;
const ffi = @import("libcrun_ffi.zig");
const c_stdio = @cImport({
    @cInclude("stdio.h");
});

/// Crun backend driver using libcrun ABI (not CLI)
pub const CrunDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    state_root: []const u8 = "/run/crun",
    // Stored strings and context to keep them valid during usage
    _state_root_z: ?[]u8 = null,
    _bundle_z: ?[]u8 = null,
    _id_z: ?[]u8 = null,
    _context: ?*ffi.Libcrun.Context = null,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._context) |ctx| self.allocator.destroy(ctx);
        if (self._state_root_z) |s| self.allocator.free(s);
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

        // Store strings to keep them valid
        if (self._state_root_z == null) {
            const state_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{self.state_root});
            self._state_root_z = state_z[0..state_z.len - 1 :0];
        }
        ctx.state_root = self._state_root_z.?.ptr;

        if (bundle_path.len > 0) {
            if (self._bundle_z) |b| self.allocator.free(b);
            const bundle_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{bundle_path});
            self._bundle_z = bundle_z[0..bundle_z.len - 1 :0];
            ctx.bundle = self._bundle_z.?.ptr;
        } else {
            ctx.bundle = null;
        }

        if (self._id_z) |i| self.allocator.free(i);
        const id_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{container_id});
        self._id_z = id_z[0..id_z.len - 1 :0];
        ctx.id = self._id_z.?.ptr;
        
        // Initialize optional fields (already zeroed by zeroes, which sets pointers to null)
        // Additional initialization not needed - zeroed context is sufficient

        return ctx;
    }

    /// Handle libcrun error and convert to Zig error
    fn handleError(self: *Self, err_ptr: *?*ffi.Libcrun.Error, operation: []const u8) !void {
        if (err_ptr.*) |_| {
            // Error structure is opaque, so we just log and release
            if (self.logger) |log| {
                log.err("libcrun {s} failed", .{operation}) catch {};
            }
            _ = ffi.Libcrun.libcrun_error_release(err_ptr);
            return core.Error.OperationFailed;
        }
        return core.Error.OperationFailed;
    }

    /// Create an OCI container using libcrun
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating OCI container with libcrun: {s}", .{config.name});
        }

        // Validate container name
        try validation.SecurityValidation.validateContainerId(config.name);

        // Create OCI bundle directory with path validation
        const bundle_path = try validation.PathSecurity.validateBundlePath(
            try std.fmt.allocPrint(self.allocator, "/var/lib/nexcage/bundles/{s}", .{config.name}),
            self.allocator
        );
        defer self.allocator.free(bundle_path);

        // Create bundle directory
        std.fs.cwd().makePath(bundle_path) catch |err| {
            if (self.logger) |log| {
                try log.err("Failed to create bundle directory {s}: {}", .{ bundle_path, err });
            }
            return err;
        };

        // Generate basic OCI config.json
        try self.generateOciConfig(config, bundle_path);

        // Create config.json path
        const config_path_cstr = try std.fmt.allocPrint(self.allocator, "{s}/config.json\x00", .{bundle_path});
        defer self.allocator.free(config_path_cstr);
        const config_path = config_path_cstr[0..config_path_cstr.len - 1 :0];

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        // Load container from config file
        const container = ffi.Libcrun.libcrun_container_load_from_file(config_path.ptr, &err_ptr) orelse {
            try self.handleError(&err_ptr, "container_load_from_file");
            return;
        };
        defer ffi.Libcrun.libcrun_container_free(container);

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

        const id_cstr = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{container_id});
        defer self.allocator.free(id_cstr);
        const id_c: [:0]const u8 = id_cstr[0..id_cstr.len - 1 :0];

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

    /// Stop an OCI container using libcrun (sends SIGTERM)
    pub fn stop(self: *Self, container_id: []const u8) !void {
        try self.kill(container_id, "TERM");
        if (self.logger) |log| {
            try log.info("Successfully stopped OCI container with libcrun: {s}", .{container_id});
        }
    }

    /// Kill an OCI container using libcrun
    pub fn kill(self: *Self, container_id: []const u8, signal: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Killing OCI container with libcrun: {s} signal {s}", .{ container_id, signal });
        }

        try validation.SecurityValidation.validateContainerId(container_id);

        // Initialize minimal context
        const ctx = try self.initContext("", container_id);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        const id_cstr = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{container_id});
        defer self.allocator.free(id_cstr);
        const id_c: [:0]const u8 = id_cstr[0..id_cstr.len - 1 :0];

        const signal_cstr = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{signal});
        defer self.allocator.free(signal_cstr);
        const signal_c: [:0]const u8 = signal_cstr[0..signal_cstr.len - 1 :0];

        // Kill container using libcrun API
        const ret = ffi.Libcrun.libcrun_container_kill(ctx, id_c.ptr, signal_c.ptr, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_kill");
            return;
        }
    }

    /// Delete an OCI container using libcrun
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting OCI container with libcrun: {s}", .{container_id});
        }

        try validation.SecurityValidation.validateContainerId(container_id);

        // Initialize minimal context
        const ctx = try self.initContext("", container_id);

        // Allocate error structure
        var err_ptr: ?*ffi.Libcrun.Error = null;

        const id_cstr = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{container_id});
        defer self.allocator.free(id_cstr);
        const id_c: [:0]const u8 = id_cstr[0..id_cstr.len - 1 :0];

        // Delete container using libcrun API (def can be null)
        const ret = ffi.Libcrun.libcrun_container_delete(ctx, null, id_c.ptr, false, &err_ptr);
        if (ret != 0) {
            try self.handleError(&err_ptr, "container_delete");
            return;
        }

        if (self.logger) |log| {
            try log.info("Successfully deleted OCI container with libcrun: {s}", .{container_id});
        }
    }

    /// Execute a command in a running container (best-effort; may be limited by libcrun API)
    pub fn exec(self: *Self, container_id: []const u8, argv: []const []const u8) !void {
        if (self.logger) |log| {
            try log.info("Exec in OCI container with libcrun: {s}", .{container_id});
        }

        // Validate
        try validation.SecurityValidation.validateContainerId(container_id);
        if (argv.len == 0) return core.Error.InvalidInput;

        // Initialize minimal context
        const ctx = try self.initContext("", container_id);

        // Build C argv (NULL-terminated)
        var tmp = std.ArrayListUnmanaged([]u8){};
        defer {
            if (tmp.items.len > 0) {
                for (tmp.items) |s| self.allocator.free(s);
                self.allocator.free(tmp.items);
            }
        }
        var c_argv = std.ArrayListUnmanaged([*:0]const u8){};
        defer if (c_argv.items.len > 0) self.allocator.free(c_argv.items);

        var i: usize = 0;
        while (i < argv.len) : (i += 1) {
            const s_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{argv[i]});
            try tmp.append(self.allocator, s_z);
            try c_argv.append(self.allocator, s_z[0..s_z.len - 1 :0].ptr);
        }
        try c_argv.append(self.allocator, null);

        // If libcrun exec API available, call it via FFI; otherwise return unsupported
        _ = ctx; // avoid unused if exec FFI not present
        if (self.logger) |log| try log.warn("libcrun exec not wired; skipping (no-op)", .{});
        return core.Error.OperationNotSupported;
    }

    /// Run: create then start a container from provided config
    pub fn run(self: *Self, config: core.types.SandboxConfig) !void {
        try self.create(config);
        try self.start(config.name);
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

