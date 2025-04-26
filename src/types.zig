const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

pub const ContainerStatus = enum {
    running,
    stopped,
    paused,
    unknown,
};

pub const PodStatus = enum {
    pending,
    running,
    stopped,
    unknown,
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

pub const ContainerSpec = struct {
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    args: []const []const u8,
    env: []EnvVar,

    pub fn deinit(self: *ContainerSpec, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.image);
        for (self.command) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(self.command);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        for (self.env) |*env| {
            env.deinit(allocator);
        }
        allocator.free(self.env);
    }
};

pub const Container = struct {
    id: []const u8,
    name: []const u8,
    status: ContainerStatus,
    spec: ContainerSpec,

    pub fn deinit(self: *Container, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        self.spec.deinit(allocator);
    }
};

pub const PodSpec = struct {
    name: []const u8,
    namespace: []const u8,
    containers: []ContainerSpec,

    pub fn deinit(self: *PodSpec, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.namespace);
        for (self.containers) |*container| {
            container.deinit(allocator);
        }
        allocator.free(self.containers);
    }
};

pub const Pod = struct {
    id: []const u8,
    name: []const u8,
    namespace: []const u8,
    status: PodStatus,
    containers: []Container,

    pub fn init(allocator: Allocator, spec: PodSpec, containers: []Container) !Pod {
        return Pod{
            .id = try allocator.dupe(u8, spec.name),
            .name = try allocator.dupe(u8, spec.name),
            .namespace = try allocator.dupe(u8, spec.namespace),
            .status = .pending,
            .containers = containers,
        };
    }

    pub fn deinit(self: *Pod, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.namespace);
        for (self.containers) |*container| {
            container.deinit(allocator);
        }
        allocator.free(self.containers);
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
    
    pub fn deinit(self: *NetworkConfig, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.bridge);
        allocator.free(self.ip);
        if (self.gw) |gw| allocator.free(gw);
        if (self.type) |type_str| allocator.free(type_str);
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
    state: ?ContainerStatus = null,
    pod_id: ?[]const u8 = null,
    label_selector: ?[]const u8 = null,

    pub fn deinit(self: *ContainerFilter, allocator: Allocator) void {
        if (self.id) |id| allocator.free(id);
        if (self.pod_id) |pod_id| allocator.free(pod_id);
        if (self.label_selector) |selector| allocator.free(selector);
    }
};

pub const ContainerConfig = struct {
    metadata: ContainerMetadata,
    image: ImageSpec,
    command: []const []const u8,
    args: []const []const u8,
    working_dir: []const u8,
    envs: []EnvVar,
    mounts: []Mount,
    devices: []Device,
    labels: std.StringHashMap([]const u8),
    annotations: std.StringHashMap([]const u8),
    linux: LinuxContainerConfig,
    log_path: []const u8,

    pub fn deinit(self: *ContainerConfig, allocator: Allocator) void {
        self.metadata.deinit(allocator);
        self.image.deinit(allocator);
        for (self.command) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(self.command);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        allocator.free(self.working_dir);
        for (self.envs) |*env| {
            env.deinit(allocator);
        }
        allocator.free(self.envs);
        for (self.mounts) |*mount| {
            mount.deinit(allocator);
        }
        allocator.free(self.mounts);
        for (self.devices) |*device| {
            device.deinit(allocator);
        }
        allocator.free(self.devices);
        var labels_it = self.labels.iterator();
        while (labels_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.labels.deinit();
        var annotations_it = self.annotations.iterator();
        while (annotations_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.annotations.deinit();
        self.linux.deinit(allocator);
        allocator.free(self.log_path);
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

pub const LinuxContainerConfig = struct {
    resources: ?ContainerResources = null,
    security_context: ?LinuxContainerSecurityContext = null,

    pub fn deinit(self: *LinuxContainerConfig, allocator: Allocator) void {
        if (self.resources) |*res| res.deinit(allocator);
        if (self.security_context) |*ctx| ctx.deinit(allocator);
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
    status: ContainerStatus,
    config: VMConfig,

    pub fn deinit(self: *VMContainer, allocator: Allocator) void {
        allocator.free(self.name);
        self.config.deinit(allocator);
    }
};

pub const ContainerState = struct {
    ociVersion: []const u8,
    id: []const u8,
    status: []const u8,
    pid: i32,
    bundle: []const u8,
    annotations: ?[]struct { key: []const u8, value: []const u8 },

    pub fn deinit(self: *ContainerState, allocator: std.mem.Allocator) void {
        allocator.free(self.ociVersion);
        allocator.free(self.id);
        allocator.free(self.status);
        allocator.free(self.bundle);
        if (self.annotations) |annotations| {
            for (annotations) |annotation| {
                allocator.free(annotation.key);
                allocator.free(annotation.value);
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

    pub fn deinit(self: *const User, allocator: Allocator) void {
        if (self.additionalGids) |gids| {
            allocator.free(gids);
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

    pub fn deinit(self: *const Process, allocator: Allocator) void {
        self.user.deinit(allocator);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        for (self.env) |env_var| {
            allocator.free(env_var);
        }
        allocator.free(self.env);
        allocator.free(self.cwd);
        if (self.capabilities) |*caps| {
            caps.deinit(allocator);
        }
        if (self.rlimits) |rlimits_| {
            allocator.free(rlimits_);
        }
    }
};
