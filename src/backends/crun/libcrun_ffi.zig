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
    /// struct libcrun_error_s from src/libcrun/error.h:
    ///
    ///     struct libcrun_error_s { int status; char *msg; };
    ///     typedef struct libcrun_error_s *libcrun_error_t;
    ///
    /// It was declared opaque here, which is why every failure on this backend
    /// could only be reported as "<operation> failed". `status` is an errno,
    /// or 0 when there is none; crun prints "msg: strerror(status)" in the
    /// first case and "msg" in the second.
    ///
    /// libcrun_error_release frees both msg and the struct, so read before
    /// releasing.
    pub const Error = extern struct {
        status: c_int,
        msg: [*c]u8,
    };
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
    /// int libcrun_container_killall (libcrun_context_t *context, const char *id,
    ///                                 const char *signal, libcrun_error_t *err);
    /// What `kill --all` means: the signal goes to every process in the
    /// container's cgroup, not only its init.
    pub extern fn libcrun_container_killall(
        context: *Context,
        id: [*c]const u8,
        signal: [*c]const u8,
        err: *?*Error,
    ) c_int;
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

    /// int libcrun_container_exec_process_file (libcrun_context_t *context,
    ///                                         const char *id, const char *path,
    ///                                         libcrun_error_t *err);
    ///
    /// The path holds an OCI process spec as JSON, and libcrun's own parser
    /// builds the struct from it. libcrun's other two exec entry points take a
    /// `runtime_spec_schema_config_schema_process *` instead: libocispec
    /// generates that type from a JSON schema and it is far larger than the two
    /// structs whose hand-written mirror already put a features document at the
    /// wrong offset. A path has no layout to get wrong.
    ///
    /// Returns the exit status of the command on success -- libcrun ends in
    /// wait_for_process, which is how `crun exec` propagates it -- and a
    /// negative value with `err` set on failure.
    pub extern fn libcrun_container_exec_process_file(
        context: *Context,
        id: [*c]const u8,
        path: [*c]const u8,
        err: *?*Error,
    ) c_int;

    // -- The features document ------------------------------------------
    //
    // `nexcage features` answers with what this build of libcrun can do,
    // because libcrun is what does the work. The alternative was to write the
    // document by hand, and a features document is a set of promises to a
    // kubelet: every line of it would have been my claim about someone else's
    // compile-time configuration, free to drift from it silently.
    //
    // These mirror `struct features_info_s` and its parts in
    // deps/crun/src/libcrun/container.h at the **vendored** commit, which is
    // kubebsd/crun c1ef7a1e (pinned in the Dockerfile and in build.zig's
    // include paths) -- not upstream containers/crun. The fork carries one
    // field upstream does not, `memory_policy` at the end of linux_info_s, and
    // reading upstream's layout here put everything after it at the wrong
    // offset: annotations became rubbish and potentiallyUnsafeConfigAnnotations
    // was a garbage pointer that segfaulted on the first dereference.
    //
    // So: a hand-written binding of a C struct is only correct for the layout
    // it was written against, and this one is written against a fork that moves.
    // Re-read that header when the submodule pin changes. featuresJson checks
    // the first field looks like a version, and the crun CI job asserts on the
    // document's contents, which is what would catch a shift further in.

    /// struct cgroup_info_s
    pub const CgroupInfo = extern struct {
        v1: bool,
        v2: bool,
        systemd: bool,
        systemd_user: bool,
    };

    /// struct seccomp_info_s
    pub const SeccompInfo = extern struct {
        enabled: bool,
        actions: [*c][*c]u8,
        operators: [*c][*c]u8,
        archs: [*c][*c]u8,
    };

    /// struct apparmor_info_s, selinux_info_s, idmap_info_s, intel_rdt_s and
    /// net_devices_s are each a single `bool enabled`.
    pub const EnabledInfo = extern struct {
        enabled: bool,
    };

    /// struct mount_ext_info_s
    pub const MountExtInfo = extern struct {
        idmap: EnabledInfo,
    };

    /// struct memory_policy_info_s. The vendored fork has this and upstream
    /// crun does not.
    pub const MemoryPolicyInfo = extern struct {
        mode: [*c][*c]u8,
        flags: [*c][*c]u8,
    };

    /// struct linux_info_s
    pub const LinuxInfo = extern struct {
        namespaces: [*c][*c]u8,
        capabilities: [*c][*c]u8,
        cgroup: CgroupInfo,
        seccomp: SeccompInfo,
        apparmor: EnabledInfo,
        selinux: EnabledInfo,
        mount_ext: MountExtInfo,
        intel_rdt: EnabledInfo,
        net_devices: EnabledInfo,
        memory_policy: MemoryPolicyInfo,
    };

    /// struct annotations_info_s
    pub const AnnotationsInfo = extern struct {
        io_github_seccomp_libseccomp_version: [*c]u8,
        run_oci_crun_checkpoint_enabled: bool,
        run_oci_crun_commit: [*c]u8,
        run_oci_crun_version: [*c]u8,
        run_oci_crun_wasm: bool,
    };

    /// struct features_info_s
    pub const FeaturesInfo = extern struct {
        oci_version_min: [*c]u8,
        oci_version_max: [*c]u8,
        hooks: [*c][*c]u8,
        mount_options: [*c][*c]u8,
        linux: LinuxInfo,
        annotations: AnnotationsInfo,
        potentially_unsafe_annotations: [*c][*c]u8,
    };

    /// int libcrun_container_get_features (libcrun_context_t *context,
    ///                                     struct features_info_s **info,
    ///                                     libcrun_error_t *err);
    pub extern fn libcrun_container_get_features(
        context: *Context,
        info: *?*FeaturesInfo,
        err: *?*Error,
    ) c_int;

    /// Options for container create
    pub const CREATE_OPTIONS_PREFORK: c_uint = 1;

    /// Default state root
    pub const DEFAULT_STATE_ROOT: []const u8 = "/run/crun";
};
