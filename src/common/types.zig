const std = @import("std");
const Allocator = std.mem.Allocator;
const json = @import("zig-json");

// Simple container status enum (for filtering and queries)
pub const SimpleContainerStatus = enum {
    running,
    stopped,
    paused,
    unknown,
};

pub const ContainerType = enum {
    crun,
    lxc,
    vm,
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn jsonStringify(self: LogLevel, _: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('"');
        try writer.writeAll(@tagName(self));
        try writer.writeByte('"');
    }

    pub fn jsonParse(source: anytype) !LogLevel {
        if (source == .string) {
            return fromString(source.string);
        }
        return error.InvalidLogLevel;
    }

    pub fn fromString(str: []const u8) !LogLevel {
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "err")) return .err;
        return error.InvalidLogLevel;
    }
};

pub const EnvVar = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: *EnvVar, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const ContainerConfig = struct {
    id: []const u8,
    name: []const u8,
    state: ContainerStateInfo,
    pid: ?u32,
    bundle: []const u8,
    annotations: ?[]Annotation,
    metadata: ?ContainerMetadata,
    image: ?ImageSpec,
    command: ?[]const []const u8,
    args: ?[]const []const u8,
    working_dir: ?[]const u8,
    envs: ?[]EnvVar,
    mounts: ?[]Mount,
    devices: ?[]Device,
    labels: ?*std.StringHashMap([]const u8),
    linux: ?LinuxContainerConfig,
    log_path: ?[]const u8,
    allocator: Allocator,
    crun_name_patterns: []const []const u8,
    default_container_type: ContainerType,

    pub fn init(allocator: Allocator) !ContainerConfig {
        return ContainerConfig{
            .id = "",
            .name = "",
            .state = ContainerStateInfo{
                .oci_version = "",
                .id = "",
                .status = "",
                .pid = 0,
                .bundle = "",
                .annotations = null,
                .allocator = allocator,
            },
            .pid = null,
            .bundle = "",
            .annotations = null,
            .metadata = null,
            .image = null,
            .command = null,
            .args = null,
            .working_dir = null,
            .envs = null,
            .mounts = null,
            .devices = null,
            .labels = null,
            .linux = null,
            .log_path = null,
            .allocator = allocator,
            .crun_name_patterns = &[_][]const u8{
                "crun-*",
                "oci-*",
                "podman-*",
            },
            .default_container_type = .lxc,
        };
    }

    pub fn deinit(self: *ContainerConfig) void {
        if (self.id.len > 0) self.allocator.free(self.id);
        if (self.name.len > 0) self.allocator.free(self.name);
        self.state.deinit(self.allocator);
        if (self.bundle.len > 0) self.allocator.free(self.bundle);
        if (self.annotations) |annotations| {
            for (annotations) |*annotation| {
                annotation.deinit(self.allocator);
            }
            self.allocator.free(annotations);
        }
        if (self.metadata) |*metadata| {
            metadata.deinit(self.allocator);
        }
        if (self.image) |*image| {
            image.deinit(self.allocator);
        }
        if (self.command) |command| {
            for (command) |cmd| {
                self.allocator.free(cmd);
            }
            self.allocator.free(command);
        }
        if (self.args) |args| {
            for (args) |arg| {
                self.allocator.free(arg);
            }
            self.allocator.free(args);
        }
        if (self.working_dir) |dir| {
            self.allocator.free(dir);
        }
        if (self.envs) |envs| {
            for (envs) |*env| {
                env.deinit(self.allocator);
            }
            self.allocator.free(envs);
        }
        if (self.mounts) |mounts| {
            for (mounts) |*mount| {
                mount.deinit(self.allocator);
            }
            self.allocator.free(mounts);
        }
        if (self.devices) |devices| {
            for (devices) |*device| {
                device.deinit(self.allocator);
            }
            self.allocator.free(devices);
        }
        if (self.labels) |labels| {
            labels.deinit();
        }
        if (self.linux) |*linux| {
            linux.deinit(self.allocator);
        }
        if (self.log_path) |path| {
            self.allocator.free(path);
        }
    }
};

pub const ContainerSpec = struct {
    config: ContainerConfig,
    network: ?NetworkConfig = null,
    storage: ?[]const StorageConfig = null,
    resources: ?ResourceLimits = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !ContainerSpec {
        return ContainerSpec{
            .config = try ContainerConfig.init(allocator),
            .network = null,
            .storage = null,
            .resources = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ContainerSpec) void {
        self.config.deinit();
        if (self.network) |*network| {
            network.deinit(self.allocator);
        }
        if (self.storage) |storage| {
            for (storage) |*config| {
                config.deinit();
            }
            self.allocator.free(storage);
        }
    }
};

pub const Container = struct {
    allocator: Allocator,
    config: ContainerConfig,
    state: ContainerState,
    pid: ?i32,

    pub fn init(allocator: Allocator, config: *ContainerConfig) !*Container {
        const container = try allocator.create(Container);
        container.* = Container{
            .allocator = allocator,
            .config = config.*,
            .state = .created,
            .pid = null,
        };
        return container;
    }

    pub fn deinit(self: *Container) void {
        self.allocator.destroy(self);
    }

    pub fn start(self: *Container, routing_config: anytype) !void {
        _ = self;
        _ = routing_config;
        // TODO: реалізувати запуск контейнера
    }
    pub fn stop(self: *Container, routing_config: anytype) !void {
        _ = self;
        _ = routing_config;
        // TODO: реалізувати зупинку контейнера
    }
    pub fn getState(self: *Container) ContainerState {
        return self.state;
    }
};

pub const LXCConfig = struct {
    hostname: []const u8,
    ostype: []const u8,
    memory: u32,
    swap: u32,
    cores: u32,
    rootfs: []const u8,
    net0: NetworkConfig,
    onboot: bool,
    protection: bool,
    start: bool,
    template: bool,
    unprivileged: bool,
    features: struct {},

    pub fn deinit(self: *LXCConfig, allocator: Allocator) void {
        allocator.free(self.hostname);
        allocator.free(self.ostype);
        allocator.free(self.rootfs);
        self.net0.deinit(allocator);
    }
};

pub const NetworkConfig = struct {
    name: []const u8,
    bridge: []const u8,
    ip: []const u8,
    gw: ?[]const u8 = null,
    type: ?[]const u8 = null,
    tag: ?u32 = null,
    rate: ?u32 = null,
    mtu: ?u32 = null,
    dns_servers: ?[]const []const u8 = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !NetworkConfig {
        return NetworkConfig{
            .name = "",
            .bridge = "",
            .ip = "",
            .gw = null,
            .type = null,
            .tag = null,
            .rate = null,
            .mtu = null,
            .dns_servers = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NetworkConfig, allocator: Allocator) void {
        if (self.name.len > 0) allocator.free(self.name);
        if (self.bridge.len > 0) allocator.free(self.bridge);
        if (self.ip.len > 0) allocator.free(self.ip);
        if (self.gw) |gw| allocator.free(gw);
        if (self.type) |type_str| allocator.free(type_str);
        if (self.dns_servers) |servers| {
            for (servers) |server| {
                allocator.free(server);
            }
            allocator.free(servers);
        }
    }
};

pub const Features = struct {
    nesting: bool = false,
    fuse: bool = false,
    keyctl: bool = false,
    mknod: bool = false,
    mount: []const []const u8 = &[_][]const u8{},
};

pub const MountPoint = struct {
    volume: []const u8,
    mp: []const u8,
    size: []const u8,
    acl: bool = false,
    backup: bool = true,
    quota: bool = false,
    replicate: bool = true,
    shared: bool = false,

    pub fn deinit(self: *MountPoint, allocator: Allocator) void {
        allocator.free(self.volume);
        allocator.free(self.mp);
        allocator.free(self.size);
    }
};

pub const LXCStatus = enum {
    stopped,
    running,
    paused,
    unknown,
};

pub const LXCContainer = struct {
    vmid: u32,
    name: []const u8,
    status: LXCStatus,
    config: LXCConfig,

    pub fn deinit(self: *LXCContainer, allocator: Allocator) void {
        allocator.free(self.name);
        self.config.deinit(allocator);
    }
};

pub const ContainerResources = struct {
    cpu_shares: ?u32 = null,
    cpu_quota: ?i64 = null,
    cpu_period: ?u64 = null,
    memory_limit_bytes: ?u64 = null,
    oom_score_adj: ?i32 = null,
    cpuset_cpus: ?[]const u8 = null,
    cpuset_mems: ?[]const u8 = null,

    pub fn deinit(self: *ContainerResources, allocator: Allocator) void {
        if (self.cpuset_cpus) |cpus| allocator.free(cpus);
        if (self.cpuset_mems) |mems| allocator.free(mems);
    }
};

pub const ContainerFilter = struct {
    id: ?[]const u8 = null,
    state: ?SimpleContainerStatus = null,
    pod_id: ?[]const u8 = null,
    label_selector: ?[]const u8 = null,

    pub fn deinit(self: *ContainerFilter, allocator: Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.pod_id) |pod_id| allocator.free(pod_id);
        if (self.label_selector) |selector| allocator.free(selector);
    }
};

pub const ContainerMetadata = struct {
    name: []const u8,
    attempt: u32,

    pub fn deinit(self: *ContainerMetadata, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const ImageSpec = struct {
    image: []const u8,
    url: ?[]const u8 = null,

    pub fn deinit(self: *ImageSpec, allocator: Allocator) void {
        allocator.free(self.image);
        if (self.url) |url| {
            allocator.free(url);
        }
    }
};

pub const Image = struct {
    id: []const u8,
    spec: ImageSpec,
    size_bytes: u64,
    uid: []const u8,
    username: []const u8,

    pub fn deinit(self: *Image, allocator: Allocator) void {
        allocator.free(self.id);
        self.spec.deinit(allocator);
        allocator.free(self.uid);
        allocator.free(self.username);
    }
};

pub const ImageStatus = struct {
    image: ImageSpec,
    present: bool,
    size_bytes: u64,

    pub fn deinit(self: *ImageStatus, allocator: Allocator) void {
        self.image.deinit(allocator);
    }
};

pub const ImageFilter = struct {
    image: ?ImageSpec = null,

    pub fn deinit(self: *ImageFilter, allocator: Allocator) void {
        if (self.image) |*img| {
            img.deinit(allocator);
        }
    }
};

// OCI hook definition used by oci/hooks.zig
pub const Hook = struct {
    path: []const u8,
    args: ?[]const []const u8 = null,
    env: ?[]const []const u8 = null,
    timeout: ?i64 = null,

    pub fn deinit(self: *const Hook, allocator: Allocator) void {
        allocator.free(self.path);
        if (self.args) |args| {
            for (args) |arg| {
                allocator.free(arg);
            }
            allocator.free(args);
        }
        if (self.env) |env| {
            for (env) |e| {
                allocator.free(e);
            }
            allocator.free(env);
        }
    }
};

pub const AuthConfig = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    auth: ?[]const u8 = null,
    server: ?[]const u8 = null,
    identity_token: ?[]const u8 = null,
    registry_token: ?[]const u8 = null,

    pub fn deinit(self: *AuthConfig, allocator: Allocator) void {
        if (self.username) |username| allocator.free(username);
        if (self.password) |password| allocator.free(password);
        if (self.auth) |auth| allocator.free(auth);
        if (self.server) |server| allocator.free(server);
        if (self.identity_token) |token| allocator.free(token);
        if (self.registry_token) |token| allocator.free(token);
    }
};

pub const Mount = struct {
    container_path: []const u8,
    host_path: []const u8,
    readonly: bool,
    selinux_relabel: bool,
    propagation: MountPropagation,

    pub fn deinit(self: *Mount, allocator: Allocator) void {
        allocator.free(self.container_path);
        allocator.free(self.host_path);
    }
};

pub const MountPropagation = enum {
    private,
    host_to_container,
    bidirectional,
};

pub const Device = struct {
    container_path: []const u8,
    host_path: []const u8,
    permissions: []const u8,

    pub fn deinit(self: *Device, allocator: Allocator) void {
        allocator.free(self.container_path);
        allocator.free(self.host_path);
        allocator.free(self.permissions);
    }
};

pub const LinuxContainerSecurityContext = struct {
    namespace_options: ?NamespaceOption = null,
    selinux_options: ?SELinuxOption = null,
    run_as_user: ?u32 = null,
    run_as_group: ?u32 = null,
    readonly_rootfs: bool = false,
    supplemental_groups: []u32,
    privileged: bool = false,
    seccomp_profile_path: ?[]const u8 = null,
    apparmor_profile: ?[]const u8 = null,
    no_new_privs: bool = false,

    pub fn deinit(self: *LinuxContainerSecurityContext, allocator: Allocator) void {
        if (self.namespace_options) |*ns| ns.deinit(allocator);
        if (self.selinux_options) |*selinux| selinux.deinit(allocator);
        allocator.free(self.supplemental_groups);
        if (self.seccomp_profile_path) |path| allocator.free(path);
        if (self.apparmor_profile) |profile| allocator.free(profile);
    }
};

pub const NamespaceOption = struct {
    network: NamespaceMode = .pod,
    pid: NamespaceMode = .container,
    ipc: NamespaceMode = .pod,

    pub fn deinit(self: *NamespaceOption, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const NamespaceMode = enum {
    pod,
    container,
    node,
};

pub const SELinuxOption = struct {
    user: []const u8,
    role: []const u8,
    type: []const u8,
    level: []const u8,

    pub fn deinit(self: *SELinuxOption, allocator: Allocator) void {
        allocator.free(self.user);
        allocator.free(self.role);
        allocator.free(self.type);
        allocator.free(self.level);
    }
};

pub const VMConfig = struct {
    name: []const u8,
    memory: u32,
    cores: u32,
    sockets: u32,
    net0: NetworkConfig,

    pub fn deinit(self: *VMConfig, allocator: Allocator) void {
        allocator.free(self.name);
        self.net0.deinit(allocator);
    }
};

pub const VMContainer = struct {
    vmid: u32,
    name: []const u8,
    status: SimpleContainerStatus,
    config: VMConfig,

    pub fn deinit(self: *VMContainer, allocator: Allocator) void {
        allocator.free(self.name);
        self.config.deinit(allocator);
    }
};

pub const Annotation = struct {
    key: []const u8,
    value: []const u8,

    pub fn deinit(self: *Annotation, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const ContainerState = enum {
    created,
    running,
    stopped,
    paused,    // Added from crun.zig
    deleted,
    unknown,
};

// Detailed container status information (moved from crun.zig)
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

pub const ContainerStateInfo = struct {
    oci_version: []const u8,
    id: []const u8,
    status: []const u8,
    pid: i64,
    bundle: []const u8,
    annotations: ?[]Annotation = null,
    allocator: Allocator,

    pub fn deinit(self: *ContainerStateInfo, allocator: Allocator) void {
        if (self.oci_version.len > 0) allocator.free(self.oci_version);
        if (self.id.len > 0) allocator.free(self.id);
        if (self.status.len > 0) allocator.free(self.status);
        if (self.bundle.len > 0) allocator.free(self.bundle);
        if (self.annotations) |annotations| {
            for (annotations) |*annotation| {
                annotation.deinit(allocator);
            }
            allocator.free(annotations);
        }
    }
};

pub const RlimitType = enum {
    RLIMIT_CPU,
    RLIMIT_FSIZE,
    RLIMIT_DATA,
    RLIMIT_STACK,
    RLIMIT_CORE,
    RLIMIT_RSS,
    RLIMIT_NPROC,
    RLIMIT_NOFILE,
    RLIMIT_MEMLOCK,
    RLIMIT_AS,
    RLIMIT_LOCKS,
    RLIMIT_SIGPENDING,
    RLIMIT_MSGQUEUE,
    RLIMIT_NICE,
    RLIMIT_RTPRIO,
    RLIMIT_RTTIME,
};

pub const Rlimit = struct {
    type: RlimitType,
    soft: u64,
    hard: u64,
};

pub const User = struct {
    uid: u32,
    gid: u32,
    additionalGids: ?[]const u32 = null,
    username: ?[]const u8 = null,

    pub fn deinit(self: *const User, allocator: Allocator) void {
        if (self.additionalGids) |gids| {
            allocator.free(gids);
        }
        if (self.username) |username| {
            allocator.free(username);
        }
    }
};

pub const Capabilities = struct {
    bounding: ?[]const []const u8 = null,
    effective: ?[]const []const u8 = null,
    inheritable: ?[]const []const u8 = null,
    permitted: ?[]const []const u8 = null,
    ambient: ?[]const []const u8 = null,

    pub fn deinit(self: *const Capabilities, allocator: Allocator) void {
        if (self.bounding) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.effective) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.permitted) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.ambient) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
    }
};

pub const Process = struct {
    terminal: bool = false,
    user: User,
    args: []const []const u8,
    env: []const []const u8,
    cwd: []const u8,
    capabilities: ?Capabilities = null,
    rlimits: ?[]Rlimit = null,
    no_new_privileges: bool = false,

    pub fn init() !Process {
        return Process{
            .terminal = false,
            .user = User{
                .uid = 0,
                .gid = 0,
                .additionalGids = null,
                .username = null,
            },
            .args = &[_][]const u8{},
            .env = &[_][]const u8{},
            .cwd = "",
            .capabilities = null,
            .rlimits = null,
            .no_new_privileges = false,
        };
    }

    pub fn deinit(self: *const Process, allocator: Allocator) void {
        self.user.deinit(allocator);
        // args and env are literals from init(), don't free them
        // cwd is a literal from init(), don't free it
        if (self.capabilities) |*caps| {
            caps.deinit(allocator);
        }
        if (self.rlimits) |rlimits_| {
            allocator.free(rlimits_);
        }
    }
};

pub const ImageConfig = struct {
    name: []const u8,
    tag: []const u8,
    registry_url: ?[]const u8 = null,
    registry_username: ?[]const u8 = null,
    registry_password: ?[]const u8 = null,
    raw_image: bool = false,
    raw_image_size: u64 = 0,

    pub fn deinit(self: *ImageConfig, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.tag);
        if (self.registry_url) |url| allocator.free(url);
        if (self.registry_username) |username| allocator.free(username);
        if (self.registry_password) |password| allocator.free(password);
    }
};

pub const RuntimeType = enum {
    runc,
    crun,
    lxc,
    vm,
};

pub const RuntimeConfig = struct {
    root_path: ?[]const u8 = null,
    log_path: ?[]const u8 = null,
    log_level: LogLevel = .info,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !RuntimeConfig {
        return RuntimeConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeConfig) void {
        if (self.root_path) |path| {
            self.allocator.free(path);
        }
        if (self.log_path) |path| {
            self.allocator.free(path);
        }
    }
};

pub const JsonConfig = struct {
    runtime: ?RuntimeConfig = null,
    proxmox: ?ProxmoxConfig = null,
    storage: ?StorageConfig = null,
    network: ?NetworkConfig = null,
};

pub const StorageConfig = struct {
    zfs_dataset: ?[]const u8 = null,
    image_path: ?[]const u8 = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !StorageConfig {
        return StorageConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StorageConfig) void {
        if (self.zfs_dataset) |dataset| {
            self.allocator.free(dataset);
        }
        if (self.image_path) |path| {
            self.allocator.free(path);
        }
    }
};

pub const StorageType = enum {
    bind,
    zfs,
    lvm,
    overlay,
};

pub const ResourceLimits = struct {
    memory: ?u64 = null,
    cpu_shares: ?u32 = null,
    cpu_quota: ?u32 = null,
    cpu_period: ?u32 = null,
    pids: ?u32 = null,
};

pub const RuntimeOptions = struct {
    root: ?[]const u8 = null,
    log: ?[]const u8 = null,
    log_format: ?[]const u8 = null,
    systemd_cgroup: bool = false,
    bundle: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    debug: bool = false,
    allocator: Allocator,

    pub fn init(allocator: Allocator) RuntimeOptions {
        return RuntimeOptions{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeOptions) void {
        if (self.root) |root| {
            self.allocator.free(root);
        }
        if (self.log) |log| {
            self.allocator.free(log);
        }
        if (self.log_format) |log_format| {
            self.allocator.free(log_format);
        }
        if (self.bundle) |bundle| {
            self.allocator.free(bundle);
        }
        if (self.pid_file) |pid_file| {
            self.allocator.free(pid_file);
        }
        if (self.console_socket) |console_socket| {
            self.allocator.free(console_socket);
        }
    }
};

pub const Command = enum {
    create,
    start,
    stop,
    state,
    kill,
    delete,
    list,
    info,
    pause,
    resume_container,
    exec,
    ps,
    run,        // Create and start container in one operation
    events,
    spec,
    checkpoint,
    restore,
    update,
    features,
    help,
    generate_config,
    version,        // Show version information
    unknown,
};

pub const ProxmoxConfig = struct {
    hosts: ?[]const []const u8 = null,
    port: ?u16 = null,
    token: ?[]const u8 = null,
    node: ?[]const u8 = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !ProxmoxConfig {
        return ProxmoxConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProxmoxConfig) void {
        if (self.hosts) |hosts| {
            for (hosts) |host| {
                self.allocator.free(host);
            }
            self.allocator.free(hosts);
        }
        if (self.token) |token| {
            self.allocator.free(token);
        }
        if (self.node) |node| {
            self.allocator.free(node);
        }
    }
};

pub const LoggerError = error{
    WriterError,
    AllocationError,
    NotInitialized,
    OutOfMemory,
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    DeviceBusy,
    InvalidArgument,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForWriting,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    Unexpected,
};

pub const LogContext = struct {
    allocator: std.mem.Allocator,
    level: LogLevel,
    name: []const u8,
    file: ?std.fs.File = null,
    writer: std.fs.File.Writer,
    tags: ?[]const []const u8 = null,

    pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: LogLevel, name: []const u8) !LogContext {
        return LogContext{
            .allocator = allocator,
            .level = level,
            .name = try allocator.dupe(u8, name),
            .file = null,
            .writer = writer,
        };
    }

    pub fn initWithFile(allocator: std.mem.Allocator, file: std.fs.File, level: LogLevel, name: []const u8) !LogContext {
        return LogContext{
            .allocator = allocator,
            .level = level,
            .name = try allocator.dupe(u8, name),
            .file = file,
            .writer = file.writer(),
        };
    }

    pub fn deinit(self: *LogContext) void {
        self.allocator.free(self.name);
        if (self.file) |file| {
            file.close();
        }
    }

    fn getTimestamp() []u8 {
        var buf: [32]u8 = undefined;
        const ts = std.time.timestamp();
        const printed = std.fmt.bufPrint(&buf, "{d}", .{ts}) catch buf[0..0];
        return printed;
    }

    pub fn setTags(self: *LogContext, tags: []const []const u8) void {
        self.tags = tags;
    }

    fn formatTags(self: *LogContext) []const u8 {
        if (self.tags) |tags| {
            var buf: [256]u8 = undefined;
            var idx: usize = 0;
            for (tags) |tag| {
                if (idx + tag.len + 3 > buf.len) break;
                buf[idx] = ' ';
                buf[idx+1] = '[';
                std.mem.copyForwards(u8, buf[idx+2..][0..tag.len], tag);
                idx += 2 + tag.len;
                buf[idx] = ']';
                idx += 1;
            }
            return buf[0..idx];
        } else {
            return "";
        }
    }

    pub fn debug(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.debug)) {
            const ts = getTimestamp();
            const tags = self.formatTags();
            self.writer.print("[{s}] [DEBUG] [{s}]{s} " ++ fmt ++ "\n", .{ts, self.name, tags} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn info(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.info)) {
            const ts = getTimestamp();
            const tags = self.formatTags();
            self.writer.print("[{s}] [INFO] [{s}]{s} " ++ fmt ++ "\n", .{ts, self.name, tags} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn warn(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.warn)) {
            const ts = getTimestamp();
            const tags = self.formatTags();
            self.writer.print("[{s}] [WARN] [{s}]{s} " ++ fmt ++ "\n", .{ts, self.name, tags} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn err(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.err)) {
            const ts = getTimestamp();
            const tags = self.formatTags();
            self.writer.print("[{s}] [ERROR] [{s}]{s} " ++ fmt ++ "\n", .{ts, self.name, tags} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }
};

pub const ErrorContext = struct {
    message: []const u8,
    error_type: Error,
    source: ?[]const u8 = null,
    details: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, message: []const u8, error_type: Error, source: ?[]const u8, details: ?[]const u8) !ErrorContext {
        return ErrorContext{
            .message = try allocator.dupe(u8, message),
            .error_type = error_type,
            .source = if (source) |s| try allocator.dupe(u8, s) else null,
            .details = if (details) |d| try allocator.dupe(u8, d) else null,
        };
    }

    pub fn deinit(self: *ErrorContext, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
        if (self.source) |s| allocator.free(s);
        if (self.details) |d| allocator.free(d);
    }

    pub fn format(self: ErrorContext, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Error: {s} ({s})", .{ self.message, @errorName(self.error_type) });
        if (self.source) |s| try writer.print(" in {s}", .{s});
        if (self.details) |d| try writer.print(": {s}", .{d});
    }
};

pub const Error = error{
    // Configuration errors
    ConfigNotFound,
    ConfigInvalid,
    InvalidConfig,
    InvalidToken,

    // Proxmox API errors
    ProxmoxAPIError,
    ProxmoxConnectionError,
    ProxmoxAuthError,
    ProxmoxResourceNotFound,
    ProxmoxOperationFailed,
    ProxmoxInvalidResponse,
    ProxmoxInvalidConfig,
    ProxmoxInvalidNode,
    ProxmoxInvalidVMID,
    ProxmoxInvalidToken,
    ProxmoxConnectionFailed,
    ProxmoxTimeout,
    ProxmoxResourceExists,
    ProxmoxInvalidState,
    ProxmoxInvalidParameter,
    ProxmoxPermissionDenied,
    ProxmoxInternalError,

    // CRI errors
    PodNotFound,
    ContainerNotFound,
    InvalidPodSpec,
    InvalidContainerSpec,
    PodCreationFailed,
    ContainerCreationFailed,
    PodDeletionFailed,
    ContainerDeletionFailed,

    // Runtime errors
    GRPCInitFailed,
    GRPCBindFailed,
    SocketError,
    ResourceLimitExceeded,

    // System errors
    FileSystemError,
    PermissionDenied,
    NetworkError,

    // New error type
    ClusterUnhealthy,

    ContainerAlreadyExists,
    InvalidContainerID,
    InvalidContainerName,
    InvalidContainerConfig,
    ContainerStartFailed,
    ContainerStopFailed,
    ContainerDeleteFailed,
    ContainerStateError,
    StorageError,
    OCIError,
    OutOfMemory,
    InvalidArgument,
    SystemError,
    UnknownError,

    InvalidArguments,
    UnknownCommand,
    UnexpectedArgument,
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
    WriterError,
    AllocationError,
    NotInitialized,
};

pub const ContainerFactory = struct {
    allocator: std.mem.Allocator,
    logger: *LogContext,

    pub fn init(allocator: std.mem.Allocator, logger_ctx: *LogContext) !ContainerFactory {
        return ContainerFactory{
            .allocator = allocator,
            .logger = logger_ctx,
        };
    }

    pub fn createManager(self: *ContainerFactory, spec: ContainerSpec) !ContainerManager {
        var manager = try ContainerManager.init(self.allocator, self.logger);
        errdefer manager.deinit();

        try manager.create(spec);
        return manager;
    }
};

pub const ProxmoxContainerConfig = struct {
    ostemplate: []const u8,
    hostname: ?[]const u8 = null,
    memory: ?u64 = null,
    swap: ?u64 = null,
    cores: ?u32 = null,
    cpulimit: ?u32 = null,
    rootfs: struct {
        volume: []const u8,
        size: []const u8,
    },
    net0: ?struct {
        name: []const u8,
        bridge: []const u8,
        ip: ?[]const u8 = null,
        gw: ?[]const u8 = null,
    } = null,
    unprivileged: bool = true,
    features: struct {
        nesting: bool = false,
    } = .{ .nesting = false },
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    runtime_type: RuntimeType,
    runtime_path: ?[]const u8,
    proxmox: ProxmoxConfig,
    storage: StorageConfig,
    network: NetworkConfig,
    logger: *LogContext,
    container_config: ContainerConfig,
    log_path: ?[]const u8,
    root_path: []const u8,
    bundle_path: []const u8,
    pid_file: ?[]const u8,
    console_socket: ?[]const u8,
    systemd_cgroup: bool,
    debug: bool,

    pub fn init(allocator: std.mem.Allocator, logger_ctx: *LogContext) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = .runc,
            .runtime_path = null,
            .proxmox = try ProxmoxConfig.init(allocator),
            .storage = try StorageConfig.init(allocator),
            .network = try NetworkConfig.init(allocator),
            .logger = logger_ctx,
            .container_config = ContainerConfig{
                .crun_name_patterns = &[_][]const u8{
                    "crun-*",
                    "oci-*",
                    "podman-*",
                },
                .default_container_type = .lxc,
            },
            .log_path = null,
            .root_path = "/var/run/proxmox-lxcri",
            .bundle_path = "/var/lib/proxmox-lxcri",
            .pid_file = null,
            .console_socket = null,
            .systemd_cgroup = false,
            .debug = false,
        };
    }

    pub fn deinit(self: *Config) void {
        self.runtime_path = null;
        self.proxmox.deinit();
        self.storage.deinit();
        self.network.deinit();
        if (self.log_path) |path| {
            self.allocator.free(path);
        }
        if (self.pid_file) |file| {
            self.allocator.free(file);
        }
        if (self.console_socket) |socket| {
            self.allocator.free(socket);
        }
    }
};

pub const LinuxContainerConfig = struct {
    // TODO: add fields
    pub fn deinit(self: *LinuxContainerConfig, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const ContainerManager = struct {
    pub fn init(allocator: std.mem.Allocator, logger: *LogContext) !ContainerManager {
        _ = allocator;
        _ = logger;
        return ContainerManager{};
    }
    pub fn deinit(self: *ContainerManager) void {
        _ = self;
    }
    pub fn create(self: *ContainerManager, spec: ContainerSpec) !void {
        _ = self;
        _ = spec;
    }
};

// OCI-specific types
pub const Bundle = struct {
    arch: []const u8,
    os: []const u8,
    hostname: []const u8,
    memory: u64,
    cpus: u32,
    network: NetworkConfig,
    mounts: []Mount,
    env: std.StringHashMap([]const u8),

    pub fn deinit(self: *Bundle, allocator: Allocator) void {
        allocator.free(self.arch);
        allocator.free(self.os);
        allocator.free(self.hostname);
        for (self.mounts) |mount| {
            mount.deinit(allocator);
        }
        allocator.free(self.mounts);
        self.env.deinit();
    }
};

pub const Hooks = struct {
    prestart: ?[]Hook = null,
    createRuntime: ?[]Hook = null,
    createContainer: ?[]Hook = null,
    startContainer: ?[]Hook = null,
    poststart: ?[]Hook = null,
    poststop: ?[]Hook = null,

    pub fn deinit(self: *const Hooks, allocator: Allocator) void {
        if (self.prestart) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.createRuntime) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.createContainer) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.startContainer) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.poststart) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.poststop) |hooks| {
            for (hooks) |*hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
    }
};

pub const OciContainerState = struct {
    hooks: ?Hooks = null,

    pub fn deinit(self: *OciContainerState, allocator: Allocator) void {
        if (self.hooks) |*hooks| {
            hooks.deinit(allocator);
        }
    }
};

// Additional types needed by OCI
pub const ConsoleSize = struct {
    height: u32,
    width: u32,
};

pub const LinuxCapabilities = struct {
    bounding: ?[][]const u8 = null,
    effective: ?[][]const u8 = null,
    inheritable: ?[][]const u8 = null,
    permitted: ?[][]const u8 = null,
    ambient: ?[][]const u8 = null,

    pub fn deinit(self: *const LinuxCapabilities, allocator: Allocator) void {
        if (self.bounding) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.effective) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.permitted) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
        if (self.ambient) |caps| {
            for (caps) |cap| {
                allocator.free(cap);
            }
            allocator.free(caps);
        }
    }
};

pub const RLimit = struct {
    type: []const u8,
    soft: u64,
    hard: u64,

    pub fn deinit(self: *const RLimit, allocator: Allocator) void {
        allocator.free(self.type);
    }
};

pub const CrunManager = struct {
    // TODO: implement crun management logic
    // You can add fields for configuration, logger, etc.

    pub fn create(self: *CrunManager, ...) !void {
        // TODO: implement create logic
        _ = self;
    }

    pub fn start(self: *CrunManager, ...) !void {
        // TODO: implement start logic
        _ = self;
    }

    pub fn stop(self: *CrunManager, ...) !void {
        // TODO: implement stop logic
        _ = self;
    }
};

// ============================================================================
// Signal constants moved from main.zig for better organization
// ============================================================================

// Signal constants
pub const SIGINT = std.posix.SIG.INT;
pub const SIGTERM = std.posix.SIG.TERM;
pub const SIGHUP = std.posix.SIG.HUP;

// Configuration error types moved from main.zig
pub const ConfigError = error{
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
} || std.fs.File.OpenError || std.fs.File.ReadError;

