const std = @import("std");
const json = std.json;

/// OCI специфікація контейнера
pub const Spec = struct {
    /// Версія специфікації OCI
    oci_version: []const u8,
    
    /// Конфігурація процесу
    process: Process,
    
    /// Конфігурація root файлової системи
    root: Root,
    
    /// Точки монтування
    mounts: []Mount,
    
    /// Хостнейм
    hostname: ?[]const u8,
    
    /// Linux-специфічні налаштування
    linux: ?Linux,
    
    /// Анотації
    annotations: std.StringHashMap([]const u8),

    pub fn deinit(self: *Spec, allocator: std.mem.Allocator) void {
        allocator.free(self.oci_version);
        self.process.deinit(allocator);
        self.root.deinit(allocator);
        for (self.mounts) |mount| {
            mount.deinit(allocator);
        }
        allocator.free(self.mounts);
        if (self.hostname) |hostname| {
            allocator.free(hostname);
        }
        if (self.linux) |linux| {
            linux.deinit(allocator);
        }
        self.annotations.deinit();
    }
};

/// Конфігурація процесу
pub const Process = struct {
    /// Термінал
    terminal: bool,
    
    /// Консольний розмір
    console_size: ?ConsoleSize,
    
    /// Користувач
    user: User,
    
    /// Аргументи
    args: [][]const u8,
    
    /// Змінні середовища
    env: [][]const u8,
    
    /// Робоча директорія
    cwd: []const u8,
    
    /// Можливості (capabilities)
    capabilities: ?Capabilities,
    
    /// Ліміти ресурсів
    rlimits: []Rlimit,
    
    /// NoNewPrivileges
    no_new_privileges: bool,

    pub fn deinit(self: *Process, allocator: std.mem.Allocator) void {
        if (self.console_size) |console_size| {
            console_size.deinit(allocator);
        }
        self.user.deinit(allocator);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        for (self.env) |env| {
            allocator.free(env);
        }
        allocator.free(self.env);
        allocator.free(self.cwd);
        if (self.capabilities) |capabilities| {
            capabilities.deinit(allocator);
        }
        for (self.rlimits) |rlimit| {
            rlimit.deinit(allocator);
        }
        allocator.free(self.rlimits);
    }
};

/// Розмір консолі
pub const ConsoleSize = struct {
    height: u32,
    width: u32,

    pub fn deinit(self: *ConsoleSize, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Користувач
pub const User = struct {
    uid: u32,
    gid: u32,
    additional_gids: ?[]u32,

    pub fn deinit(self: *User, allocator: std.mem.Allocator) void {
        if (self.additional_gids) |gids| {
            allocator.free(gids);
        }
    }
};

/// Root файлова система
pub const Root = struct {
    path: []const u8,
    readonly: bool,

    pub fn deinit(self: *Root, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Точка монтування
pub const Mount = struct {
    destination: []const u8,
    source: ?[]const u8,
    type: []const u8,
    options: ?[][]const u8,

    pub fn deinit(self: *Mount, allocator: std.mem.Allocator) void {
        allocator.free(self.destination);
        if (self.source) |source| {
            allocator.free(source);
        }
        allocator.free(self.type);
        if (self.options) |options| {
            for (options) |option| {
                allocator.free(option);
            }
            allocator.free(options);
        }
    }
};

/// Linux-специфічні налаштування
pub const Linux = struct {
    devices: []Device,
    resources: ?Resources,
    cgroups_path: ?[]const u8,
    namespaces: []Namespace,
    masked_paths: [][]const u8,
    readonly_paths: [][]const u8,
    mount_label: ?[]const u8,

    pub fn deinit(self: *Linux, allocator: std.mem.Allocator) void {
        for (self.devices) |device| {
            device.deinit(allocator);
        }
        allocator.free(self.devices);
        if (self.resources) |resources| {
            resources.deinit(allocator);
        }
        if (self.cgroups_path) |path| {
            allocator.free(path);
        }
        for (self.namespaces) |namespace| {
            namespace.deinit(allocator);
        }
        allocator.free(self.namespaces);
        for (self.masked_paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.masked_paths);
        for (self.readonly_paths) |path| {
            allocator.free(path);
        }
        allocator.free(self.readonly_paths);
        if (self.mount_label) |label| {
            allocator.free(label);
        }
    }
};

/// Пристрій
pub const Device = struct {
    type: []const u8,
    path: []const u8,
    major: i64,
    minor: i64,
    file_mode: ?u32,
    uid: ?u32,
    gid: ?u32,

    pub fn deinit(self: *Device, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.path);
    }
};

/// Ресурси CPU
pub const CpuResources = struct {
    shares: ?u64,
    quota: ?i64,
    period: ?u64,
    realtime_runtime: ?i64,
    realtime_period: ?u64,
    cpus: ?[]const u8,
    mems: ?[]const u8,

    pub fn deinit(self: *CpuResources, allocator: std.mem.Allocator) void {
        if (self.cpus) |cpus| {
            allocator.free(cpus);
        }
        if (self.mems) |mems| {
            allocator.free(mems);
        }
    }
};

/// Ресурси
pub const Resources = struct {
    cpu: ?CpuResources,
    memory: ?MemoryResources,
    pids: ?PidsResources,
    block_io: ?BlockIoResources,
    hugepage_limits: ?[]HugepageLimit,
    network: ?NetworkResources,

    pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
        if (self.cpu) |cpu| {
            cpu.deinit(allocator);
        }
        if (self.memory) |memory| {
            memory.deinit(allocator);
        }
        if (self.pids) |pids| {
            pids.deinit(allocator);
        }
        if (self.block_io) |block_io| {
            block_io.deinit(allocator);
        }
        if (self.hugepage_limits) |limits| {
            for (limits) |limit| {
                limit.deinit(allocator);
            }
            allocator.free(limits);
        }
        if (self.network) |network| {
            network.deinit(allocator);
        }
    }
};

/// Простір імен
pub const Namespace = struct {
    type: []const u8,
    path: ?[]const u8,

    pub fn deinit(self: *Namespace, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        if (self.path) |path| {
            allocator.free(path);
        }
    }
};

/// Можливості (capabilities)
pub const Capabilities = struct {
    bounding: ?[][]const u8,
    effective: ?[][]const u8,
    inheritable: ?[][]const u8,
    permitted: ?[][]const u8,
    ambient: ?[][]const u8,

    pub fn deinit(self: *Capabilities, allocator: std.mem.Allocator) void {
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

/// Ліміт ресурсу
pub const Rlimit = struct {
    type: []const u8,
    soft: u64,
    hard: u64,

    pub fn deinit(self: *Rlimit, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
    }
}; 