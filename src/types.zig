const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

pub const ContainerStatus = enum {
    created,
    running,
    stopped,
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
    onboot: bool = false,
    protection: bool = false,
    start: bool = true,
    template: bool = false,
    unprivileged: bool = true,
    features: Features = .{},
    mp0: ?MountPoint = null,
    mp1: ?MountPoint = null,
    mp2: ?MountPoint = null,
    mp3: ?MountPoint = null,
    mp4: ?MountPoint = null,
    mp5: ?MountPoint = null,
    mp6: ?MountPoint = null,
    mp7: ?MountPoint = null,

    pub fn deinit(self: *LXCConfig, allocator: Allocator) void {
        allocator.free(self.hostname);
        allocator.free(self.ostype);
        allocator.free(self.rootfs);
        self.net0.deinit(allocator);
        if (self.mp0) |*mp| mp.deinit(allocator);
        if (self.mp1) |*mp| mp.deinit(allocator);
        if (self.mp2) |*mp| mp.deinit(allocator);
        if (self.mp3) |*mp| mp.deinit(allocator);
        if (self.mp4) |*mp| mp.deinit(allocator);
        if (self.mp5) |*mp| mp.deinit(allocator);
        if (self.mp6) |*mp| mp.deinit(allocator);
        if (self.mp7) |*mp| mp.deinit(allocator);
    }

    pub fn jsonStringify(self: LXCConfig, options: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('{');
        try json.stringifyField("hostname", self.hostname, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("ostype", self.ostype, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("memory", self.memory, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("swap", self.swap, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("cores", self.cores, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("rootfs", self.rootfs, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("net0", self.net0, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("onboot", self.onboot, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("protection", self.protection, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("start", self.start, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("template", self.template, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("unprivileged", self.unprivileged, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("features", self.features, options, writer);

        if (self.mp0) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp0", mp, options, writer);
        }
        if (self.mp1) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp1", mp, options, writer);
        }
        if (self.mp2) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp2", mp, options, writer);
        }
        if (self.mp3) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp3", mp, options, writer);
        }
        if (self.mp4) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp4", mp, options, writer);
        }
        if (self.mp5) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp5", mp, options, writer);
        }
        if (self.mp6) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp6", mp, options, writer);
        }
        if (self.mp7) |mp| {
            try writer.writeByte(',');
            try json.stringifyField("mp7", mp, options, writer);
        }

        try writer.writeByte('}');
    }
};

pub const NetworkConfig = struct {
    name: []const u8,
    bridge: []const u8,
    ip: []const u8,
    gw: ?[]const u8 = null,
    ip6: ?[]const u8 = null,
    gw6: ?[]const u8 = null,
    mtu: ?u16 = null,
    rate: ?u32 = null,
    tag: ?u16 = null,
    trunks: ?[]const u16 = null,
    type: []const u8 = "veth",

    pub fn deinit(self: *NetworkConfig, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.bridge);
        allocator.free(self.ip);
        if (self.gw) |gw| allocator.free(gw);
        if (self.ip6) |ip6| allocator.free(ip6);
        if (self.gw6) |gw6| allocator.free(gw6);
        if (self.trunks) |trunks| allocator.free(trunks);
        allocator.free(self.type);
    }

    pub fn jsonStringify(self: NetworkConfig, options: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('{');
        try json.stringifyField("name", self.name, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("bridge", self.bridge, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("ip", self.ip, options, writer);

        if (self.gw) |gw| {
            try writer.writeByte(',');
            try json.stringifyField("gw", gw, options, writer);
        }
        if (self.ip6) |ip6| {
            try writer.writeByte(',');
            try json.stringifyField("ip6", ip6, options, writer);
        }
        if (self.gw6) |gw6| {
            try writer.writeByte(',');
            try json.stringifyField("gw6", gw6, options, writer);
        }
        if (self.mtu) |mtu| {
            try writer.writeByte(',');
            try json.stringifyField("mtu", mtu, options, writer);
        }
        if (self.rate) |rate| {
            try writer.writeByte(',');
            try json.stringifyField("rate", rate, options, writer);
        }
        if (self.tag) |tag| {
            try writer.writeByte(',');
            try json.stringifyField("tag", tag, options, writer);
        }
        if (self.trunks) |trunks| {
            try writer.writeByte(',');
            try json.stringifyField("trunks", trunks, options, writer);
        }

        try writer.writeByte(',');
        try json.stringifyField("type", self.type, options, writer);
        try writer.writeByte('}');
    }
};

pub const Features = struct {
    nesting: bool = false,
    fuse: bool = false,
    keyctl: bool = false,
    mknod: bool = false,
    mount: []const []const u8 = &[_][]const u8{},

    pub fn jsonStringify(self: Features, options: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('{');
        try json.stringifyField("nesting", self.nesting, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("fuse", self.fuse, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("keyctl", self.keyctl, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("mknod", self.mknod, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("mount", self.mount, options, writer);
        try writer.writeByte('}');
    }
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

    pub fn jsonStringify(self: MountPoint, options: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('{');
        try json.stringifyField("volume", self.volume, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("mp", self.mp, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("size", self.size, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("acl", self.acl, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("backup", self.backup, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("quota", self.quota, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("replicate", self.replicate, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("shared", self.shared, options, writer);
        try writer.writeByte('}');
    }
};

pub const LXCStatus = enum {
    stopped,
    running,
    paused,
    unknown,

    pub fn jsonStringify(self: LXCStatus, _: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('"');
        try writer.writeAll(@tagName(self));
        try writer.writeByte('"');
    }
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

    pub fn jsonStringify(self: LXCContainer, options: json.StringifyOptions, writer: anytype) !void {
        try writer.writeByte('{');
        try json.stringifyField("vmid", self.vmid, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("name", self.name, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("status", self.status, options, writer);
        try writer.writeByte(',');
        try json.stringifyField("config", self.config, options, writer);
        try writer.writeByte('}');
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
