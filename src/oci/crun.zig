const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const OciSpec = @import("runtime_types").OciSpec;

// Import C headers for libcrun
pub const c = @cImport({
    @cInclude("crun.h");
    @cInclude("libcrun/container.h");
    @cInclude("libcrun/error.h");
    @cInclude("libcrun/context.h");
});

// Error types for crun operations
pub const CrunError = error{
    ContainerCreateFailed,
    ContainerStartFailed,
    ContainerDeleteFailed,
    ContainerRunFailed,
    ContainerNotFound,
    InvalidConfiguration,
    RuntimeError,
    OutOfMemory,
    InvalidContainerId,
    InvalidBundlePath,
    ContextInitFailed,
    ContainerLoadFailed,
};

// Container state enum
pub const ContainerState = enum {
    created,
    running,
    stopped,
    paused,
    unknown,
};

// Container status structure
pub const ContainerStatus = struct {
    id: []const u8,
    state: ContainerState,
    pid: ?u32,
    exit_code: ?u32,
    created_at: ?[]const u8,
    started_at: ?[]const u8,
    finished_at: ?[]const u8,

    pub fn deinit(self: *ContainerStatus, allocator: Allocator) void {
        allocator.free(self.id);
        if (self.created_at) |time| allocator.free(time);
        if (self.started_at) |time| allocator.free(time);
        if (self.finished_at) |time| allocator.free(time);
    }
};

// Main CrunManager struct
pub const CrunManager = struct {
    allocator: Allocator,
    logger: *Logger,
    root_path: ?[]const u8,
    log_path: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .root_path = null,
            .log_path = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.root_path) |path| self.allocator.free(path);
        if (self.log_path) |path| self.allocator.free(path);
        self.allocator.destroy(self);
    }

    // Set root path for containers
    pub fn setRootPath(self: *Self, root_path: []const u8) !void {
        if (self.root_path) |old_path| self.allocator.free(old_path);
        self.root_path = try self.allocator.dupe(u8, root_path);
    }

    // Set log path
    pub fn setLogPath(self: *Self, log_path: []const u8) !void {
        if (self.log_path) |old_path| self.allocator.free(old_path);
        self.log_path = try self.allocator.dupe(u8, log_path);
    }

    // Create a new container
    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, _: ?*const OciSpec) !void {
        try self.logger.info("Creating crun container: {s} in bundle: {s}", .{ container_id, bundle_path });

        // Validate inputs
        if (container_id.len == 0) return CrunError.InvalidContainerId;
        if (bundle_path.len == 0) return CrunError.InvalidBundlePath;

        // Initialize libcrun context
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        // Set context parameters
        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = bundle_path.ptr;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Load container configuration
        var container: *c.libcrun_container_t = null;
        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/config.json",
            .{bundle_path},
        );
        defer self.allocator.free(config_path);

        const load_ret = c.libcrun_container_load_from_file(config_path.ptr, &err);
        if (load_ret == null) {
            try self.logger.err("Failed to load container config: {s}", .{bundle_path});
            return CrunError.ContainerLoadFailed;
        }
        container = load_ret;

        defer c.libcrun_container_free(container);

        // Create container
        const create_ret = c.libcrun_container_create(&context, container, 0, &err);
        if (create_ret != 0) {
            try self.logger.err("Failed to create container: {s}", .{container_id});
            return CrunError.ContainerCreateFailed;
        }

        try self.logger.info("Successfully created crun container: {s}", .{container_id});
    }

    // Start a container
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting crun container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Initialize context
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = null;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Start container
        const start_ret = c.libcrun_container_start(&context, container_id.ptr, &err);
        if (start_ret != 0) {
            try self.logger.err("Failed to start container: {s}", .{container_id});
            return CrunError.ContainerStartFailed;
        }

        try self.logger.info("Successfully started crun container: {s}", .{container_id});
    }

    // Delete a container
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting crun container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Initialize context
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = null;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Load container definition (needed for delete)
        var container: *c.libcrun_container_t = null;
        const load_ret = c.libcrun_container_load_from_file("", &err); // Empty path for state-only
        if (load_ret == null) {
            try self.logger.err("Failed to load container for deletion: {s}", .{container_id});
            return CrunError.ContainerLoadFailed;
        }
        container = load_ret;

        defer c.libcrun_container_free(container);

        // Delete container
        const delete_ret = c.libcrun_container_delete(&context, container.*.container_def, &err);
        if (delete_ret != 0) {
            try self.logger.err("Failed to delete container: {s}", .{container_id});
            return CrunError.ContainerDeleteFailed;
        }

        try self.logger.info("Successfully deleted crun container: {s}", .{container_id});
    }

    // Run a container (create + start)
    pub fn runContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, _: ?*const OciSpec) !void {
        try self.logger.info("Running crun container: {s} in bundle: {s}", .{ container_id, bundle_path });

        // Create container first
        try self.createContainer(container_id, bundle_path, null);

        // Then start it
        try self.startContainer(container_id);

        try self.logger.info("Successfully ran crun container: {s}", .{container_id});
    }

    // Check if container exists
    pub fn containerExists(self: *Self, container_id: []const u8) !bool {
        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Try to get container state
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = null;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Try to get container state
        var status: c.libcrun_container_status_t = undefined;
        const state_ret = c.libcrun_get_container_state_string(container_id.ptr, &status, &err);
        
        return state_ret == 0;
    }

    // Get container state
    pub fn getContainerState(self: *Self, container_id: []const u8) !ContainerState {
        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Initialize context
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = null;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Get container state
        var status: c.libcrun_container_status_t = undefined;
        const state_ret = c.libcrun_get_container_state_string(container_id.ptr, &status, &err);
        
        if (state_ret != 0) {
            return ContainerState.unknown;
        }

        // Map libcrun state to our enum
        // Note: This is a simplified mapping, actual implementation would need
        // to parse the status string returned by libcrun
        return ContainerState.unknown; // TODO: Implement proper state mapping
    }

    // Kill a container
    pub fn killContainer(self: *Self, container_id: []const u8, signal: []const u8) !void {
        try self.logger.info("Killing crun container: {s} with signal: {s}", .{ container_id, signal });

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Initialize context
        var context: c.libcrun_context_t = undefined;
        var err: c.libcrun_error_t = undefined;

        context.state_root = if (self.root_path) |root| root.ptr else "/run/crun";
        context.id = container_id.ptr;
        context.bundle = null;
        context.console_socket = null;
        context.pid_file = null;
        context.notify_socket = null;
        context.handler = null;
        context.preserve_fds = 0;
        context.listen_fds = 0;
        context.output_handler = null;
        context.output_handler_arg = null;
        context.fifo_exec_wait_fd = -1;
        context.systemd_cgroup = false;
        context.detach = false;
        context.no_new_keyring = false;
        context.force_no_cgroup = false;
        context.no_pivot = false;
        context.argv = null;
        context.argc = 0;
        context.handler_manager = null;

        // Kill container
        const kill_ret = c.libcrun_container_kill(&context, container_id.ptr, signal.ptr, &err);
        if (kill_ret != 0) {
            try self.logger.err("Failed to kill container: {s}", .{container_id});
            return CrunError.RuntimeError;
        }

        try self.logger.info("Successfully killed crun container: {s}", .{container_id});
    }
};
