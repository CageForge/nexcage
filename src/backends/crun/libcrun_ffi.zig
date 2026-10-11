const std = @import("std");

/// FFI bindings for libcrun library
pub const Libcrun = struct {
    /// struct libcrun_context_s from deps/crun/src/libcrun/container.h at the
    /// vendored commit, field for field. libcrun is handed a pointer to it
    /// and reads every field, so "only the fields we set" is not an option:
    /// this used to lack `no_open_tree_namespace`, which 1.30 added after
    /// `no_pivot`, and the offsets still matched only because the new bool
    /// fell into the padding before `argv`. The next field would not have.
    /// crun/mod.zig compares this with the header when the backend is built
    /// (expectSameLayout), so a pin that moves a field fails the build.
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
        /// Turns off libcrun's open_tree mount path; zeroed, as crun leaves it.
        no_open_tree_namespace: bool,
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

    /// Load container from a spec held in memory. libcrun keeps the text and
    /// writes it to the state directory as the container's config.json.
    pub extern fn libcrun_container_load_from_memory(
        json: [*c]const u8,
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

    /// int libcrun_container_pause (libcrun_context_t *context, const char *id,
    ///                              libcrun_error_t *err);
    /// int libcrun_container_unpause (libcrun_context_t *context, const char *id,
    ///                                libcrun_error_t *err);
    ///
    /// The cgroup freezer, which is what `runc pause` and `runc resume` mean:
    /// every process in the container stops where it is and stays in memory.
    pub extern fn libcrun_container_pause(
        context: *Context,
        id: [*c]const u8,
        err: *?*Error,
    ) c_int;

    pub extern fn libcrun_container_unpause(
        context: *Context,
        id: [*c]const u8,
        err: *?*Error,
    ) c_int;

    /// int libcrun_container_update (libcrun_context_t *context, const char *id,
    ///                               const char *content, size_t len, libcrun_error_t *err);
    /// int libcrun_container_update_from_values (libcrun_context_t *context, const char *id,
    ///                                           struct libcrun_update_value_s *values, size_t len,
    ///                                           libcrun_error_t *err);
    ///
    /// `update`, both ways crun itself offers it: a runtime-spec linux.resources
    /// document, which is what a container engine sends for an in-place resize,
    /// or a list of settings in crun's section/name vocabulary, which is what a
    /// command line says.
    ///
    /// `content` must end in a NUL, whatever `len` says: libcrun marks `len`
    /// unused and strlen()s the pointer (container.c, parse_json_file). Typed
    /// as a plain many-pointer, it took the slice update.zig read, which has
    /// no terminator, and libcrun read on past the allocation: a resize the
    /// engine sent was refused as "invalid utf-8 at position <len>" at some
    /// lengths, and a 64 KiB document crashed the process on an unmapped page.
    pub const UpdateValue = extern struct {
        section: [*:0]const u8,
        name: [*:0]const u8,
        numeric: bool,
        value: [*:0]const u8,
    };
    pub extern fn libcrun_container_update(context: *Context, id: [*c]const u8, content: [*:0]const u8, len: usize, err: *?*Error) c_int;
    pub extern fn libcrun_container_update_from_values(context: *Context, id: [*c]const u8, values: [*]UpdateValue, len: usize, err: *?*Error) c_int;

    /// int libcrun_container_read_pids (libcrun_context_t *context, const char *id,
    ///                                  bool recurse, pid_t **pids,
    ///                                  libcrun_error_t *err);
    ///
    /// The host PIDs of the processes in the container's cgroup, which is what
    /// `crun ps` and `runc ps` report. `*pids` comes back as a plain malloc'd
    /// array terminated by a 0, and the caller frees it -- crun's own ps leaks
    /// it, which costs nothing in a process that is about to exit.
    ///
    /// `recurse` walks the cgroup's children as well; crun passes true.
    pub extern fn libcrun_container_read_pids(
        context: *Context,
        id: [*c]const u8,
        recurse: bool,
        pids: *[*c]c_int,
        err: *?*Error,
    ) c_int;

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
    // deps/crun/src/libcrun/container.h at the **vendored** commit -- the
    // submodule pin, which the Dockerfile checks out by hash: CageForge/crun
    // 7d6f6955, which is upstream 1.30.1. The first version of this mirror
    // was written against an unpacked crun 1.23.1 tree that build.zig's
    // include paths pointed at, and 1.24 had added `memory_policy` at the
    // end of linux_info_s; reading the old layout here put everything after
    // it at the wrong offset: annotations became rubbish and
    // potentiallyUnsafeConfigAnnotations was a garbage pointer that
    // segfaulted on the first dereference.
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

/// Fails the build unless `Mirror` lays out `C` exactly: the same fields in
/// the same order, each at the same offset and of the same size, and the same
/// size overall. `C` is the struct as @cImport translates it from the vendored
/// header. Field names are compared too: the mirrors keep crun's.
pub fn expectSameLayout(comptime Mirror: type, comptime C: type) void {
    const theirs = @typeInfo(C).@"struct".fields;
    const ours = @typeInfo(Mirror).@"struct".fields;
    const n = @min(theirs.len, ours.len);
    inline for (0..n) |i| {
        const t = theirs[i];
        const o = ours[i];
        if (!std.mem.eql(u8, t.name, o.name)) @compileError(std.fmt.comptimePrint(
            "{s} has diverged from the vendored header's {s}: field {d} is `{s}` here and `{s}` there",
            .{ @typeName(Mirror), @typeName(C), i, o.name, t.name },
        ));
        if (@offsetOf(Mirror, o.name) != @offsetOf(C, t.name) or @sizeOf(o.type) != @sizeOf(t.type)) @compileError(std.fmt.comptimePrint(
            "{s}.{s} is {d} bytes at offset {d}, and in the vendored header {d} bytes at offset {d}",
            .{ @typeName(Mirror), o.name, @sizeOf(o.type), @offsetOf(Mirror, o.name), @sizeOf(t.type), @offsetOf(C, t.name) },
        ));
    }
    if (theirs.len != ours.len) @compileError(std.fmt.comptimePrint(
        "{s} has {d} fields and the vendored header's {s} has {d}: the first {d} agree, so one end gained or lost a field",
        .{ @typeName(Mirror), ours.len, @typeName(C), theirs.len, n },
    ));
    if (@sizeOf(Mirror) != @sizeOf(C)) @compileError(std.fmt.comptimePrint(
        "{s} is {d} bytes and the vendored header's {s} is {d}",
        .{ @typeName(Mirror), @sizeOf(Mirror), @typeName(C), @sizeOf(C) },
    ));
}
