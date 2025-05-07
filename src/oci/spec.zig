const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const json = std.json;
const logger = @import("logger");
const types = @import("types");
const errors = @import("error");
const common = @import("common");
const create = @import("create.zig");
const StorageConfig = create.StorageConfig;
const Allocator = std.mem.Allocator;

pub const Process = types.Process;
pub const User = types.User;
pub const Capabilities = types.Capabilities;
pub const RlimitType = types.RlimitType;
pub const Rlimit = types.Rlimit;

pub const Root = struct {
    path: []const u8,
    readonly: bool = false,

    pub fn deinit(self: *const Root, allocator: Allocator) void {
        allocator.free(self.path);
    }
};

pub const Mount = struct {
    destination: []const u8,
    type: []const u8,
    source: []const u8,
    options: ?[]const []const u8 = null,

    pub fn deinit(self: *const Mount, allocator: Allocator) void {
        allocator.free(self.destination);
        allocator.free(self.type);
        allocator.free(self.source);
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

pub const Hooks = struct {
    prestart: ?[]const Hook = null,
    poststart: ?[]const Hook = null,
    poststop: ?[]const Hook = null,

    pub fn deinit(self: *const Hooks, allocator: Allocator) void {
        if (self.prestart) |hooks| {
            for (hooks) |hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.poststart) |hooks| {
            for (hooks) |hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
        if (self.poststop) |hooks| {
            for (hooks) |hook| {
                hook.deinit(allocator);
            }
            allocator.free(hooks);
        }
    }
};

pub const Spec = struct {
    version: []const u8,
    process: Process,
    root: Root,
    hostname: []const u8,
    mounts: []const Mount,
    hooks: ?Hooks,
    annotations: std.StringHashMap([]const u8),
    linux: LinuxSpec,
    storage: StorageConfig,

    pub fn deinit(self: *Spec, allocator: Allocator) void {
        allocator.free(self.version);
        allocator.free(self.hostname);
        for (self.mounts) |mount| {
            mount.deinit(allocator);
        }
        allocator.free(self.mounts);
        if (self.hooks) |hooks| {
            hooks.deinit(allocator);
        }
        var it = self.annotations.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.annotations.deinit();
        self.linux.deinit(allocator);
        if (self.storage.storage_path) |path| {
            allocator.free(path);
        }
        if (self.storage.storage_pool) |pool| {
            allocator.free(pool);
        }
    }
};

pub const LinuxSpec = struct {
    namespaces: []const LinuxNamespace,
    resources: ?LinuxResources = null,
    cgroupsPath: ?[]const u8 = null,
    devices: []const LinuxDevice,
    seccomp: ?Seccomp = null,
    selinux: ?SELinux = null,
    
    pub fn deinit(self: *const LinuxSpec, allocator: Allocator) void {
        for (self.namespaces) |ns| {
            ns.deinit(allocator);
        }
        allocator.free(self.namespaces);
        
        if (self.resources) |res| {
            res.deinit(allocator);
        }
        if (self.cgroupsPath) |path| {
            allocator.free(path);
        }
        
        for (self.devices) |dev| {
            dev.deinit(allocator);
        }
        allocator.free(self.devices);
        
        if (self.seccomp) |*seccomp_| {
            seccomp_.deinit(allocator);
        }
        
        if (self.selinux) |*selinux_| {
            selinux_.deinit(allocator);
        }
    }
};

pub const LinuxNamespace = struct {
    type: []const u8,
    path: ?[]const u8 = null,

    pub fn deinit(self: *const LinuxNamespace, allocator: Allocator) void {
        allocator.free(self.type);
        if (self.path) |p| {
            allocator.free(p);
        }
    }
};

pub const LinuxDevice = struct {
    path: []const u8,
    type: []const u8,
    major: i64,
    minor: i64,
    fileMode: ?u32 = null,
    uid: ?u32 = null,
    gid: ?u32 = null,

    pub fn deinit(self: *const LinuxDevice, allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.type);
    }
};

pub const LinuxResources = struct {
    devices: ?[]LinuxDeviceCgroup = null,
    memory: ?LinuxMemory = null,
    cpu: ?LinuxCPU = null,
    pids: ?LinuxPids = null,
    blockIO: ?LinuxBlockIO = null,
    hugepageLimits: ?[]LinuxHugepageLimit = null,
    network: ?LinuxNetwork = null,

    pub fn deinit(self: *const LinuxResources, allocator: Allocator) void {
        if (self.devices) |d| {
            for (d) |*device| {
                device.deinit(allocator);
            }
            allocator.free(d);
        }
        if (self.memory) |*m| {
            m.deinit(allocator);
        }
        if (self.cpu) |*c| {
            c.deinit(allocator);
        }
        if (self.pids) |*p| {
            p.deinit(allocator);
        }
        if (self.blockIO) |*b| {
            b.deinit(allocator);
        }
        if (self.hugepageLimits) |h| {
            for (h) |*limit| {
                limit.deinit(allocator);
            }
            allocator.free(h);
        }
        if (self.network) |*n| {
            n.deinit(allocator);
        }
    }
};

pub const LinuxDeviceCgroup = struct {
    allow: bool,
    type: ?[]const u8 = null,
    major: ?i64 = null,
    minor: ?i64 = null,
    access: ?[]const u8 = null,

    pub fn deinit(self: *const LinuxDeviceCgroup, allocator: Allocator) void {
        if (self.type) |t| {
            allocator.free(t);
        }
        if (self.access) |a| {
            allocator.free(a);
        }
    }
};

pub const LinuxMemory = struct {
    limit: ?u64 = null,
    reservation: ?u64 = null,
    swap: ?u64 = null,
    kernel: ?u64 = null,
    kernelTCP: ?u64 = null,
    swappiness: ?u64 = null,
    disableOOMKiller: bool = false,
    useHierarchy: bool = false,

    pub fn deinit(self: *const LinuxMemory, allocator: Allocator) void {
        _ = allocator;
        _ = self;
        // Немає динамічно виділеної пам'яті для очищення
    }
};

pub const LinuxCPU = struct {
    shares: ?u64 = null,
    quota: ?i64 = null,
    period: ?u64 = null,
    realtimeRuntime: ?i64 = null,
    realtimePeriod: ?u64 = null,
    cpus: ?[]const u8 = null,
    mems: ?[]const u8 = null,

    pub fn deinit(self: *const LinuxCPU, allocator: Allocator) void {
        if (self.cpus) |c| {
            allocator.free(c);
        }
        if (self.mems) |m| {
            allocator.free(m);
        }
    }
};

pub const LinuxPids = struct {
    limit: i64,

    pub fn deinit(self: *const LinuxPids, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const NetworkInterface = struct {
    name: []const u8,
    mac: ?[]const u8 = null,
    address: ?[]const []const u8 = null,
    gateway: ?[]const u8 = null,
    mtu: ?u32 = null,
    
    pub fn deinit(self: *const NetworkInterface, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.mac) |mac_| {
            allocator.free(mac_);
        }
        if (self.address) |addrs| {
            for (addrs) |addr| {
                allocator.free(addr);
            }
            allocator.free(addrs);
        }
        if (self.gateway) |gw| {
            allocator.free(gw);
        }
    }
};

pub const NetworkRoute = struct {
    destination: []const u8,
    gateway: []const u8,
    source: ?[]const u8 = null,
    metric: ?u32 = null,
    
    pub fn deinit(self: *const NetworkRoute, allocator: Allocator) void {
        allocator.free(self.destination);
        allocator.free(self.gateway);
        if (self.source) |src| {
            allocator.free(src);
        }
    }
};

pub const LinuxNetwork = struct {
    classID: ?u32 = null,
    priorities: ?[]LinuxInterfacePriority = null,
    interfaces: ?[]NetworkInterface = null,
    routes: ?[]NetworkRoute = null,
    dnsServers: ?[]const []const u8 = null,
    dnsOptions: ?[]const []const u8 = null,
    dnsSearch: ?[]const []const u8 = null,
    
    pub fn deinit(self: *const LinuxNetwork, allocator: Allocator) void {
        if (self.priorities) |p| {
            for (p) |*priority| {
                priority.deinit(allocator);
            }
            allocator.free(p);
        }
        
        if (self.interfaces) |ifaces| {
            for (ifaces) |*iface| {
                iface.deinit(allocator);
            }
            allocator.free(ifaces);
        }
        
        if (self.routes) |routes_| {
            for (routes_) |*route| {
                route.deinit(allocator);
            }
            allocator.free(routes_);
        }
        
        if (self.dnsServers) |servers| {
            for (servers) |server| {
                allocator.free(server);
            }
            allocator.free(servers);
        }
        
        if (self.dnsOptions) |options| {
            for (options) |option| {
                allocator.free(option);
            }
            allocator.free(options);
        }
        
        if (self.dnsSearch) |search| {
            for (search) |domain| {
                allocator.free(domain);
            }
            allocator.free(search);
        }
    }
};

pub const LinuxInterfacePriority = struct {
    name: []const u8,
    priority: u32,

    pub fn deinit(self: *const LinuxInterfacePriority, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const LinuxHugepageLimit = struct {
    pageSize: []const u8,
    limit: u64,

    pub fn deinit(self: *const LinuxHugepageLimit, allocator: Allocator) void {
        allocator.free(self.pageSize);
    }
};

pub const LinuxBlockIO = struct {
    weight: ?u16 = null,
    leafWeight: ?u16 = null,
    weightDevice: ?[]LinuxWeightDevice = null,
    throttleReadBpsDevice: ?[]LinuxThrottleDevice = null,
    throttleWriteBpsDevice: ?[]LinuxThrottleDevice = null,
    throttleReadIOPSDevice: ?[]LinuxThrottleDevice = null,
    throttleWriteIOPSDevice: ?[]LinuxThrottleDevice = null,

    pub fn deinit(self: *const LinuxBlockIO, allocator: Allocator) void {
        if (self.weightDevice) |devices| {
            for (devices) |*device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttleReadBpsDevice) |devices| {
            for (devices) |*device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttleWriteBpsDevice) |devices| {
            for (devices) |*device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttleReadIOPSDevice) |devices| {
            for (devices) |*device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
        if (self.throttleWriteIOPSDevice) |devices| {
            for (devices) |*device| {
                device.deinit(allocator);
            }
            allocator.free(devices);
        }
    }
};

pub const LinuxWeightDevice = struct {
    major: i64,
    minor: i64,
    weight: ?u16 = null,
    leafWeight: ?u16 = null,

    pub fn deinit(self: *const LinuxWeightDevice, _: Allocator) void {
        _ = self;
    }
};

pub const LinuxThrottleDevice = struct {
    major: i64,
    minor: i64,
    rate: u64,

    pub fn deinit(self: *const LinuxThrottleDevice, _: Allocator) void {
        _ = self;
    }
};

pub const Seccomp = struct {
    defaultAction: []const u8,
    architectures: ?[]const []const u8 = null,
    flags: ?[]const []const u8 = null,
    listenerPath: ?[]const u8 = null,
    listenerMetadata: ?[]const u8 = null,
    syscalls: ?[]const SeccompSyscall = null,

    pub fn deinit(self: *const Seccomp, allocator: Allocator) void {
        allocator.free(self.defaultAction);
        
        if (self.architectures) |archs| {
            for (archs) |arch| {
                allocator.free(arch);
            }
            allocator.free(archs);
        }
        
        if (self.flags) |flags_| {
            for (flags_) |flag| {
                allocator.free(flag);
            }
            allocator.free(flags_);
        }
        
        if (self.listenerPath) |path| {
            allocator.free(path);
        }
        
        if (self.listenerMetadata) |metadata| {
            allocator.free(metadata);
        }
        
        if (self.syscalls) |syscalls_| {
            for (syscalls_) |syscall| {
                syscall.deinit(allocator);
            }
            allocator.free(syscalls_);
        }
    }
};

pub const SeccompSyscall = struct {
    names: []const []const u8,
    action: []const u8,
    args: ?[]const SeccompArg = null,

    pub fn deinit(self: *const SeccompSyscall, allocator: Allocator) void {
        for (self.names) |name| {
            allocator.free(name);
        }
        allocator.free(self.names);
        allocator.free(self.action);
        
        if (self.args) |args_| {
            for (args_) |arg| {
                arg.deinit(allocator);
            }
            allocator.free(args_);
        }
    }
};

pub const SeccompArg = struct {
    index: u32,
    value: u64,
    valueTwo: u64,
    op: []const u8,

    pub fn deinit(self: *const SeccompArg, allocator: Allocator) void {
        allocator.free(self.op);
    }
};

pub const SELinux = struct {
    user: ?[]const u8 = null,
    role: ?[]const u8 = null,
    type: ?[]const u8 = null,
    level: ?[]const u8 = null,
    
    pub fn deinit(self: *const SELinux, allocator: Allocator) void {
        if (self.user) |user_| {
            allocator.free(user_);
        }
        if (self.role) |role_| {
            allocator.free(role_);
        }
        if (self.type) |type_| {
            allocator.free(type_);
        }
        if (self.level) |level_| {
            allocator.free(level_);
        }
    }
};

pub const OciImageConfig = struct {
    storage: StorageConfig,
    raw_image: bool = false,
    raw_image_size: u64 = 10 * 1024 * 1024 * 1024, // 10GB за замовчуванням
    registry_url: ?[]const u8 = null,
    registry_username: ?[]const u8 = null,
    registry_password: ?[]const u8 = null,

    pub fn deinit(self: *const OciImageConfig, allocator: Allocator) void {
        if (self.storage.storage_path) |path| {
            allocator.free(path);
        }
        if (self.storage.storage_pool) |pool| {
            allocator.free(pool);
        }
        if (self.registry_url) |url| {
            allocator.free(url);
        }
        if (self.registry_username) |username| {
            allocator.free(username);
        }
        if (self.registry_password) |password| {
            allocator.free(password);
        }
    }
}; 