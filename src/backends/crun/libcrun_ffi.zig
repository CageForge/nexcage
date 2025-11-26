const std = @import("std");

/// FFI bindings for libcrun library
/// Using extern struct with minimal fields needed for API calls
pub const Libcrun = struct {
    /// Context structure (only fields we need to set)
    pub const Context = extern struct {
        state_root: [*c]const u8,
        id: [*c]const u8,
        bundle: [*c]const u8,
        console_socket: [*c]const u8,
        pid_file: [*c]const u8,
        notify_socket: [*c]const u8,
        handler: [*c]const u8,
        preserve_fds: c_int,
        listen_fds: c_int,
        output_handler: ?*anyopaque,
        output_handler_arg: ?*anyopaque,
        fifo_exec_wait_fd: c_int,
        systemd_cgroup: bool,
        detach: bool,
        no_new_keyring: bool,
        force_no_cgroup: bool,
        no_pivot: bool,
        argv: [*][*c]u8,
        argc: c_int,
        handler_manager: ?*anyopaque,
    };
    
    /// Opaque types for structures we don't need to access
    pub const Container = opaque {};
    pub const Error = opaque {};
    pub const ContainerStatus = opaque {};

    /// Create a container
    pub extern fn libcrun_container_create(
        context: *Context,
        container: *Container,
        options: c_uint,
        err: *?*Error,
    ) c_int;

    /// Start a container
    pub extern fn libcrun_container_start(
        context: *Context,
        id: [*c]const u8,
        err: *?*Error,
    ) c_int;

    /// Kill a container
    pub extern fn libcrun_container_kill(
        context: *Context,
        id: [*c]const u8,
        signal: [*c]const u8,
        err: *?*Error,
    ) c_int;

    /// Delete a container
    pub extern fn libcrun_container_delete(
        context: *Context,
        def: ?*anyopaque, // runtime_spec_schema_config_schema *
        id: [*c]const u8,
        force: bool,
        err: *?*Error,
    ) c_int;

    /// Get container state
    pub extern fn libcrun_container_state(
        context: *Context,
        id: [*c]const u8,
        out: ?*anyopaque, // FILE *
        err: *?*Error,
    ) c_int;

    /// Delete container status
    pub extern fn libcrun_container_delete_status(
        state_root: [*c]const u8,
        id: [*c]const u8,
        err: *?*Error,
    ) c_int;

    /// Load container from file
    pub extern fn libcrun_container_load_from_file(
        path: [*c]const u8,
        err: *?*Error,
    ) ?*Container;

    /// Free container
    pub extern fn libcrun_container_free(container: *Container) void;

    /// Read container status
    pub extern fn libcrun_read_container_status(
        status: *ContainerStatus,
        state_root: [*c]const u8,
        id: [*c]const u8,
        err: *?*Error,
    ) c_int;

    /// Get container state string
    pub extern fn libcrun_get_container_state_string(
        id: [*c]const u8,
        status: *const ContainerStatus,
        state_root: [*c]const u8,
        container_status: *[*c]const u8,
        running: *c_int,
        err: *?*Error,
    ) c_int;

    /// Release error
    pub extern fn libcrun_error_release(err: *?*Error) c_int;

    /// Options for container create
    pub const CREATE_OPTIONS_PREFORK: c_uint = 1;

    /// Default state root
    pub const DEFAULT_STATE_ROOT: []const u8 = "/run/crun";
};

