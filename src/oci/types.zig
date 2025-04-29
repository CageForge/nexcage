const std = @import("std");

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

pub const ContainerState = struct {
    hooks: ?Hooks = null,
    
    pub fn deinit(self: *ContainerState, allocator: std.mem.Allocator) void {
        if (self.hooks) |*hooks| {
            hooks.deinit(allocator);
        }
    }
}; 