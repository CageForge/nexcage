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
