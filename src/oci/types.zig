const std = @import("std");

pub const User = struct {
    uid: u32,
    gid: u32,
    additionalGids: ?[]const u32 = null,

    pub fn deinit(self: *const User, allocator: std.mem.Allocator) void {
        if (self.additionalGids) |gids| {
            allocator.free(gids);
        }
    }
};

pub const Process = struct {
    terminal: bool = false,
    user: ?User = null,
    args: ?[][]const u8 = null,
    env: ?[][]const u8 = null,
    cwd: ?[]const u8 = null,
    capabilities: ?Capabilities = null,
    rlimits: ?[]Rlimit = null,

    pub fn deinit(self: *const Process, allocator: std.mem.Allocator) void {
        if (self.user) |user| {
            user.deinit(allocator);
        }
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
        if (self.cwd) |cwd| {
            allocator.free(cwd);
        }
        if (self.capabilities) |caps| {
            caps.deinit(allocator);
        }
        if (self.rlimits) |rlimits| {
            for (rlimits) |rlimit| {
                rlimit.deinit(allocator);
            }
            allocator.free(rlimits);
        }
    }
};

pub const Capabilities = struct {
    bounding: ?[][]const u8 = null,
    effective: ?[][]const u8 = null,
    inheritable: ?[][]const u8 = null,
    permitted: ?[][]const u8 = null,
    ambient: ?[][]const u8 = null,

    pub fn deinit(self: *const Capabilities, allocator: std.mem.Allocator) void {
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

    pub fn deinit(self: *const Rlimit, _: std.mem.Allocator) void {
        _ = self;
    }
};

pub const Bundle = struct {
    arch: []const u8,
    os: []const u8,
    hostname: []const u8,
    memory: u64,
    cpus: u32,
    network: NetworkConfig,
    mounts: []Mount,
    env: std.StringHashMap([]const u8),

    pub fn deinit(self: *Bundle, allocator: std.mem.Allocator) void {
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

pub const NetworkConfig = struct {
    type: []const u8,
    bridge: ?[]const u8 = null,
    address: ?[]const u8 = null,
    gateway: ?[]const u8 = null,
    nameservers: ?[][]const u8 = null,

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.bridge) |bridge| allocator.free(bridge);
        if (self.address) |addr| allocator.free(addr);
        if (self.gateway) |gw| allocator.free(gw);
        if (self.nameservers) |ns| {
            for (ns) |server| {
                allocator.free(server);
            }
            allocator.free(ns);
        }
    }
};

pub const Mount = struct {
    source: []const u8,
    destination: []const u8,
    type: []const u8,
    options: ?[][]const u8,

    pub fn deinit(self: *Mount, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.destination);
        allocator.free(self.type);
        if (self.options) |opts| {
            for (opts) |opt| {
                allocator.free(opt);
            }
            allocator.free(opts);
        }
    }
};

pub const Hook = struct {
    path: []const u8,
    args: ?[]const []const u8 = null,
    env: ?[]const []const u8 = null,
    timeout: ?i64 = null,

    pub fn deinit(self: *const Hook, allocator: std.mem.Allocator) void {
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

pub const Hooks = struct {
    prestart: ?[]Hook = null,
    createRuntime: ?[]Hook = null,
    createContainer: ?[]Hook = null,
    startContainer: ?[]Hook = null,
    poststart: ?[]Hook = null,
    poststop: ?[]Hook = null,

    pub fn deinit(self: *const Hooks, allocator: std.mem.Allocator) void {
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

pub const RuntimeType = enum {
    lxc,
    crun,
    vm,
};

pub const ContainerState = struct {
    hooks: ?Hooks = null,

    pub fn deinit(self: *ContainerState, allocator: std.mem.Allocator) void {
        if (self.hooks) |*hooks| {
            hooks.deinit(allocator);
        }
    }
};
