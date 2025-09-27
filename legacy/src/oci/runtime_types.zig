const std = @import("std");
const Allocator = std.mem.Allocator;

// OCI Runtime Spec v1.0.2
pub const OciSpec = struct {
    ociVersion: []const u8,
    process: ?Process,
    root: ?Root,
    hostname: ?[]const u8,
    mounts: ?[]const Mount,
    hooks: ?Hooks,
    annotations: ?StringMap,
    linux: ?Linux,
    windows: ?Windows,
    vm: ?VM,

    pub fn validate(self: *const @This()) !void {
        // Validate OCI version
        if (!std.mem.eql(u8, self.ociVersion, "1.0.2")) {
            return error.UnsupportedOciVersion;
        }

        // Validate process configuration
        if (self.process) |process| {
            try process.validate();
        }

        // Validate root filesystem
        if (self.root) |root| {
            try root.validate();
        }

        // Validate mounts
        if (self.mounts) |mounts| {
            for (mounts) |mount| {
                try mount.validate();
            }
        }

        // Validate Linux-specific configuration
        if (self.linux) |linux| {
            try linux.validate();
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.ociVersion);
        if (self.hostname) |hostname| allocator.free(hostname);
        if (self.process) |process| process.deinit(allocator);
        if (self.root) |root| root.deinit(allocator);
        if (self.mounts) |mounts| {
            for (mounts) |mount| mount.deinit(allocator);
            allocator.free(mounts);
        }
        if (self.hooks) |hooks| hooks.deinit(allocator);
        if (self.annotations) |annotations| annotations.deinit(allocator);
        if (self.linux) |linux| linux.deinit(allocator);
        if (self.windows) |windows| windows.deinit(allocator);
        if (self.vm) |vm| vm.deinit(allocator);
    }
};

pub const Process = struct {
    terminal: ?bool,
    consoleSize: ?Box,
    user: User,
    args: []const []const u8,
    env: ?[]const []const u8,
    cwd: []const u8,
    capabilities: ?LinuxCapabilities,
    rlimits: ?[]const POSIXRlimit,
    noNewPrivileges: bool,
    apparmorProfile: ?[]const u8,
    oomScoreAdj: ?i32,
    selinuxLabel: ?[]const u8,

    pub fn validate(self: *const @This()) !void {
        // Validate user configuration
        try self.user.validate();

        // Validate arguments
        if (self.args.len == 0) {
            return error.MissingProcessArgs;
        }

        // Validate working directory
        if (!std.mem.startsWith(u8, self.cwd, "/")) {
            return error.InvalidWorkingDirectory;
        }

        // Validate environment variables
        if (self.env) |env| {
            for (env) |env_var| {
                if (env_var.len == 0) return error.EmptyEnvironmentVariable;
            }
        }

        // Validate capabilities if present
        if (self.capabilities) |caps| {
            try caps.validate();
        }

        // Validate resource limits if present
        if (self.rlimits) |limits| {
            for (limits) |limit| {
                try limit.validate();
            }
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.user.deinit(allocator);

        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);

        if (self.env) |env| {
            for (env) |env_var| allocator.free(env_var);
            allocator.free(env);
        }

        allocator.free(self.cwd);

        if (self.capabilities) |caps| caps.deinit(allocator);

        if (self.rlimits) |limits| {
            for (limits) |limit| limit.deinit(allocator);
            allocator.free(limits);
        }

        if (self.apparmorProfile) |profile| allocator.free(profile);
        if (self.selinuxLabel) |label| allocator.free(label);
    }
};

pub const Root = struct {
    path: []const u8,
    readonly: bool,

    pub fn validate(self: *const @This()) !void {
        if (self.path.len == 0) {
            return error.MissingRootPath;
        }

        // Path must be absolute
        if (!std.mem.startsWith(u8, self.path, "/")) {
            return error.InvalidRootPath;
        }

        // Path must not contain ".." for security
        if (std.mem.indexOf(u8, self.path, "..") != null) {
            return error.InvalidRootPath;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path);
    }
};

pub const Mount = struct {
    destination: []const u8,
    type: []const u8,
    source: []const u8,
    options: ?[]const []const u8,

    pub fn validate(self: *const @This()) !void {
        if (self.destination.len == 0) {
            return error.MissingMountDestination;
        }

        if (self.type.len == 0) {
            return error.MissingMountType;
        }

        if (self.source.len == 0) {
            return error.MissingMountSource;
        }

        // Destination must be absolute path
        if (!std.mem.startsWith(u8, self.destination, "/")) {
            return error.InvalidMountDestination;
        }

        // Source must be absolute path
        if (!std.mem.startsWith(u8, self.source, "/")) {
            return error.InvalidMountSource;
        }

        // Validate mount type
        const valid_types = [_][]const u8{ "bind", "proc", "sysfs", "tmpfs", "devpts", "devtmpfs", "overlay" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, self.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidMountType;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.destination);
        allocator.free(self.type);
        allocator.free(self.source);

        if (self.options) |options| {
            for (options) |option| allocator.free(option);
            allocator.free(options);
        }
    }
};

pub const User = struct {
    uid: i32,
    gid: i32,
    additionalGids: ?[]const i32,

    pub fn validate(self: *const @This()) !void {
        if (self.uid < 0) return error.InvalidUID;
        if (self.gid < 0) return error.InvalidGID;

        if (self.additionalGids) |gids| {
            for (gids) |gid| {
                if (gid < 0) return error.InvalidAdditionalGID;
            }
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.additionalGids) |gids| {
            allocator.free(gids);
        }
    }
};

pub const LinuxCapabilities = struct {
    bounding: ?[]const []const u8,
    effective: ?[]const []const u8,
    inheritable: ?[]const []const u8,
    permitted: ?[]const []const u8,
    ambient: ?[]const []const u8,

    pub fn validate(self: *const @This()) !void {
        // Validate capability names
        if (self.bounding) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.effective) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.permitted) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.ambient) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
    }

    fn validateCapabilityName(_: *const @This(), cap: []const u8) !void {
        // Basic capability name validation
        if (cap.len == 0) return error.EmptyCapabilityName;
        if (cap.len > 64) return error.CapabilityNameTooLong;

        // Check for valid characters
        for (cap) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '_') {
                return error.InvalidCapabilityName;
            }
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.bounding) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.effective) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.permitted) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.ambient) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
    }
};

pub const Linux = struct {
    namespaces: ?[]const LinuxNamespace,
    devices: ?[]const LinuxDevice,
    cgroupsPath: ?[]const u8,
    resources: ?LinuxResources,
    seccomp: ?LinuxSeccomp,
    rootfsPropagation: ?[]const u8,
    maskedPaths: ?[]const []const u8,
    readonlyPaths: ?[]const []const u8,
    mountLabel: ?[]const u8,
    intelRdt: ?LinuxIntelRdt,

    pub fn validate(self: *const @This()) !void {
        // Validate namespaces if present
        if (self.namespaces) |namespaces| {
            for (namespaces) |ns| {
                try ns.validate();
            }
        }

        // Validate devices if present
        if (self.devices) |devices| {
            for (devices) |device| {
                try device.validate();
            }
        }

        // Validate cgroups path if present
        if (self.cgroupsPath) |path| {
            if (path.len > 0 and !std.mem.startsWith(u8, path, "/")) {
                return error.InvalidCgroupsPath;
            }
        }

        // Validate resources if present
        if (self.resources) |resources| {
            try resources.validate();
        }

        // Validate seccomp if present
        if (self.seccomp) |seccomp| {
            try seccomp.validate();
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.namespaces) |namespaces| {
            for (namespaces) |ns| ns.deinit(allocator);
            allocator.free(namespaces);
        }
        if (self.devices) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.cgroupsPath) |path| allocator.free(path);
        if (self.resources) |resources| resources.deinit(allocator);
        if (self.seccomp) |seccomp| seccomp.deinit(allocator);
        if (self.rootfsPropagation) |prop| allocator.free(prop);
        if (self.maskedPaths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        if (self.readonlyPaths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        if (self.mountLabel) |label| allocator.free(label);
        if (self.intelRdt) |rdt| rdt.deinit(allocator);
    }
};

// Supporting types
pub const Box = struct {
    height: u32,
    width: u32,
};

pub const StringMap = std.StringHashMap([]const u8);

pub const Hooks = struct {
    prestart: ?[]const Hook,
    createRuntime: ?[]const Hook,
    createContainer: ?[]const Hook,
    startContainer: ?[]const Hook,
    poststart: ?[]const Hook,
    poststop: ?[]const Hook,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.prestart) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
        if (self.createRuntime) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
        if (self.createContainer) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
        if (self.startContainer) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
        if (self.poststart) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
        if (self.poststop) |hooks| {
            for (hooks) |hook| hook.deinit(allocator);
            allocator.free(hooks);
        }
    }
};

pub const Hook = struct {
    path: []const u8,
    args: ?[]const []const u8,
    env: ?[]const []const u8,
    timeout: ?i64,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path);
        if (self.args) |args| {
            for (args) |arg| allocator.free(arg);
            allocator.free(args);
        }
        if (self.env) |env| {
            for (env) |env_var| allocator.free(env_var);
            allocator.free(env);
        }
    }
};

pub const LinuxNamespace = struct {
    type: []const u8,
    path: ?[]const u8,

    pub fn validate(self: *const @This()) !void {
        const valid_types = [_][]const u8{ "pid", "network", "ipc", "uts", "mount", "user", "cgroup" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, self.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidNamespaceType;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.type);
        if (self.path) |path| allocator.free(path);
    }
};

pub const LinuxDevice = struct {
    path: []const u8,
    type: []const u8,
    major: i64,
    minor: i64,
    fileMode: ?u32,
    uid: ?u32,
    gid: ?u32,

    pub fn validate(self: *const @This()) !void {
        if (self.path.len == 0) return error.MissingDevicePath;
        if (self.type.len == 0) return error.MissingDeviceType;

        // Validate device type
        const valid_types = [_][]const u8{ "c", "b", "u", "p" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, self.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidDeviceType;
        }

        // Validate major/minor numbers
        if (self.major < 0) return error.InvalidMajorNumber;
        if (self.minor < 0) return error.InvalidMinorNumber;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.path);
        allocator.free(self.type);
    }
};

pub const LinuxResources = struct {
    devices: ?[]const LinuxDeviceCgroup,
    memory: ?LinuxMemory,
    cpu: ?LinuxCPU,
    pids: ?LinuxPids,
    network: ?LinuxNetwork,
    hugepageLimits: ?[]const LinuxHugepageLimit,
    blockIO: ?LinuxBlockIO,

    pub fn validate(self: *const @This()) !void {
        if (self.devices) |devices| {
            for (devices) |device| {
                try device.validate();
            }
        }
        if (self.memory) |memory| {
            try memory.validate();
        }
        if (self.cpu) |cpu| {
            try cpu.validate();
        }
        if (self.pids) |pids| {
            try pids.validate();
        }
        if (self.network) |network| {
            try network.validate();
        }
        if (self.hugepageLimits) |limits| {
            for (limits) |limit| {
                try limit.validate();
            }
        }
        if (self.blockIO) |block_io| {
            try block_io.validate();
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.devices) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.memory) |memory| memory.deinit(allocator);
        if (self.cpu) |cpu| cpu.deinit(allocator);
        if (self.pids) |pids| pids.deinit(allocator);
        if (self.network) |network| network.deinit(allocator);
        if (self.hugepageLimits) |limits| {
            for (limits) |limit| limit.deinit(allocator);
            allocator.free(limits);
        }
        if (self.blockIO) |block_io| block_io.deinit(allocator);
    }
};

pub const LinuxSeccomp = struct {
    defaultAction: []const u8,
    architectures: ?[]const []const u8,
    flags: ?[]const []const u8,
    syscalls: ?[]const LinuxSyscall,

    pub fn validate(self: *const @This()) !void {
        const valid_actions = [_][]const u8{ "SCMP_ACT_KILL", "SCMP_ACT_TRAP", "SCMP_ACT_ERRNO", "SCMP_ACT_TRACE", "SCMP_ACT_ALLOW" };
        var valid = false;
        for (valid_actions) |action| {
            if (std.mem.eql(u8, self.defaultAction, action)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidSeccompAction;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.defaultAction);
        if (self.architectures) |archs| {
            for (archs) |arch| allocator.free(arch);
            allocator.free(archs);
        }
        if (self.flags) |flags| {
            for (flags) |flag| allocator.free(flag);
            allocator.free(flags);
        }
        if (self.syscalls) |syscalls| {
            for (syscalls) |syscall| syscall.deinit(allocator);
            allocator.free(syscalls);
        }
    }
};

// Placeholder types for future implementation
pub const Windows = struct {
    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const VM = struct {
    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const POSIXRlimit = struct {
    type: RlimitType,
    hard: u64,
    soft: u64,

    pub fn validate(self: *const @This()) !void {
        if (self.hard < self.soft) {
            return error.InvalidRlimitValues;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
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

// Additional supporting types (simplified for now)
pub const LinuxDeviceCgroup = struct {
    allow: bool,
    type: []const u8,
    major: ?i64,
    minor: ?i64,
    access: []const u8,

    pub fn validate(self: *const @This()) !void {
        if (self.type.len == 0) return error.MissingDeviceType;
        if (self.access.len == 0) return error.MissingDeviceAccess;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.type);
        allocator.free(self.access);
    }
};

pub const LinuxMemory = struct {
    limit: ?i64,
    reservation: ?i64,
    swap: ?i64,
    kernel: ?i64,
    kernelTCP: ?i64,
    swappiness: ?u64,

    pub fn validate(self: *const @This()) !void {
        if (self.limit) |limit| {
            if (limit < 0) return error.InvalidMemoryLimit;
        }
        if (self.reservation) |reservation| {
            if (reservation < 0) return error.InvalidMemoryReservation;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const LinuxCPU = struct {
    shares: ?u64,
    quota: ?i64,
    period: ?u64,
    realtimeRuntime: ?i64,
    realtimePeriod: ?u64,
    cpus: ?[]const u8,
    mems: ?[]const u8,

    pub fn validate(self: *const @This()) !void {
        if (self.quota) |quota| {
            if (quota < 0) return error.InvalidCPUQuota;
        }
        if (self.period) |period| {
            if (period <= 0) return error.InvalidCPUPeriod;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.cpus) |cpus| allocator.free(cpus);
        if (self.mems) |mems| allocator.free(mems);
    }
};

pub const LinuxPids = struct {
    limit: i64,

    pub fn validate(self: *const @This()) !void {
        if (self.limit < 0) return error.InvalidPidsLimit;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const LinuxNetwork = struct {
    classID: ?u32,
    priorities: ?[]const LinuxInterfacePriority,

    pub fn validate(self: *const @This()) !void {
        if (self.priorities) |priorities| {
            for (priorities) |priority| {
                try priority.validate();
            }
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.priorities) |priorities| {
            for (priorities) |priority| priority.deinit(allocator);
            allocator.free(priorities);
        }
    }
};

pub const LinuxInterfacePriority = struct {
    name: []const u8,
    priority: u32,

    pub fn validate(self: *const @This()) !void {
        if (self.name.len == 0) return error.MissingInterfaceName;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const LinuxHugepageLimit = struct {
    pageSize: []const u8,
    limit: u64,

    pub fn validate(self: *const @This()) !void {
        if (self.pageSize.len == 0) return error.MissingPageSize;
        if (self.limit == 0) return error.InvalidHugepageLimit;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.pageSize);
    }
};

pub const LinuxBlockIO = struct {
    weight: ?u16,
    leafWeight: ?u16,
    weightDevice: ?[]const LinuxWeightDevice,
    throttleReadBpsDevice: ?[]const LinuxThrottleDevice,
    throttleWriteBpsDevice: ?[]const LinuxThrottleDevice,
    throttleReadIOPSDevice: ?[]const LinuxThrottleDevice,
    throttleWriteIOPSDevice: ?[]const LinuxThrottleDevice,

    pub fn validate(self: *const @This()) !void {
        if (self.weight) |weight| {
            if (weight > 1000) return error.InvalidBlockIOWeight;
        }
        if (self.leafWeight) |leaf_weight| {
            if (leaf_weight > 1000) return error.InvalidBlockIOLeafWeight;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.weightDevice) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.throttleReadBpsDevice) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.throttleWriteBpsDevice) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.throttleReadIOPSDevice) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.throttleWriteIOPSDevice) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
    }
};

pub const LinuxWeightDevice = struct {
    major: i64,
    minor: i64,
    weight: ?u16,
    leafWeight: ?u16,

    pub fn validate(self: *const @This()) !void {
        if (self.major < 0) return error.InvalidMajorNumber;
        if (self.minor < 0) return error.InvalidMinorNumber;
        if (self.weight) |weight| {
            if (weight > 1000) return error.InvalidWeightDeviceWeight;
        }
        if (self.leafWeight) |leaf_weight| {
            if (leaf_weight > 1000) return error.InvalidWeightDeviceLeafWeight;
        }
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const LinuxThrottleDevice = struct {
    major: i64,
    minor: i64,
    rate: u64,

    pub fn validate(self: *const @This()) !void {
        if (self.major < 0) return error.InvalidMajorNumber;
        if (self.minor < 0) return error.InvalidMinorNumber;
        if (self.rate == 0) return error.InvalidThrottleRate;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const LinuxSyscall = struct {
    names: []const []const u8,
    action: []const u8,
    args: ?[]const LinuxSeccompArg,
    comment: ?[]const u8,
    includes: ?LinuxSeccompOpts,
    excludes: ?LinuxSeccompOpts,

    pub fn validate(self: *const @This()) !void {
        if (self.names.len == 0) return error.MissingSyscallNames;
        if (self.action.len == 0) return error.MissingSyscallAction;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        for (self.names) |name| allocator.free(name);
        allocator.free(self.names);
        allocator.free(self.action);
        if (self.args) |args| {
            for (args) |arg| arg.deinit(allocator);
            allocator.free(args);
        }
        if (self.comment) |comment| allocator.free(comment);
        if (self.includes) |includes| includes.deinit(allocator);
        if (self.excludes) |excludes| excludes.deinit(allocator);
    }
};

pub const LinuxSeccompArg = struct {
    index: u32,
    value: u64,
    valueTwo: ?u64,
    op: []const u8,

    pub fn validate(self: *const @This()) !void {
        if (self.op.len == 0) return error.MissingSeccompArgOp;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        allocator.free(self.op);
    }
};

pub const LinuxSeccompOpts = struct {
    arches: ?[]const []const u8,
    caps: ?[]const []const u8,
    paths: ?[]const []const u8,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.arches) |arches| {
            for (arches) |arch| allocator.free(arch);
            allocator.free(arches);
        }
        if (self.caps) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.paths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
    }
};

pub const LinuxIntelRdt = struct {
    l3CacheSchema: ?[]const u8,
    l3CacheSchemaFile: ?[]const u8,
    memBwSchema: ?[]const u8,
    memBwSchemaFile: ?[]const u8,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.l3CacheSchema) |schema| allocator.free(schema);
        if (self.l3CacheSchemaFile) |file| allocator.free(file);
        if (self.memBwSchema) |schema| allocator.free(schema);
        if (self.memBwSchemaFile) |file| allocator.free(file);
    }
};

// Error types
pub const OciError = error{
    UnsupportedOciVersion,
    MissingProcessArgs,
    InvalidWorkingDirectory,
    EmptyEnvironmentVariable,
    MissingRootPath,
    InvalidRootPath,
    MissingMountDestination,
    MissingMountType,
    MissingMountSource,
    InvalidMountDestination,
    InvalidMountSource,
    InvalidMountType,
    InvalidUID,
    InvalidGID,
    InvalidAdditionalGID,
    EmptyCapabilityName,
    CapabilityNameTooLong,
    InvalidCapabilityName,
    InvalidNamespaceType,
    InvalidDeviceType,
    InvalidMajorNumber,
    InvalidMinorNumber,
    InvalidSeccompAction,
    InvalidRlimitValues,
    MissingDeviceType,
    MissingDeviceAccess,
    InvalidMemoryLimit,
    InvalidMemoryReservation,
    InvalidCPUQuota,
    InvalidCPUPeriod,
    InvalidPidsLimit,
    MissingInterfaceName,
    MissingPageSize,
    InvalidHugepageLimit,
    InvalidBlockIOWeight,
    InvalidBlockIOLeafWeight,
    InvalidWeightDeviceWeight,
    InvalidWeightDeviceLeafWeight,
    InvalidThrottleRate,
    MissingSyscallNames,
    MissingSyscallAction,
    MissingSeccompArgOp,
    InvalidCgroupsPath,
    HostnameTooLong,
    InvalidHostnameCharacter,
    InvalidHostnameFormat,
};
