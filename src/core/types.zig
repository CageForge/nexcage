const std = @import("std");

// Global types and structures accessible to all modules

/// Global error types
pub const Error = error{
    InvalidConfig,
    NetworkError,
    StorageError,
    RuntimeError,
    ValidationError,
    NotFound,
    FileNotFound,
    PermissionDenied,
    Timeout,
    OutOfMemory,
    InvalidInput,
    OperationFailed,
    UnsupportedOperation,
};

/// Sandbox configuration
pub const SandboxConfig = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    runtime_type: RuntimeType,
    image: ?[]const u8 = null,
    resources: ?ResourceLimits = null,
    security: ?SecurityConfig = null,
    network: ?NetworkConfig = null,
    storage: ?StorageConfig = null,

    pub fn deinit(self: *SandboxConfig) void {
        self.allocator.free(self.name);
        if (self.resources) |*r| r.deinit();
        if (self.security) |*s| s.deinit();
        if (self.network) |*n| n.deinit(self.allocator);
        if (self.storage) |*s| s.deinit(self.allocator);
    }
};

/// Runtime type enumeration
pub const RuntimeType = enum {
    lxc,
    qemu,
    crun,
    runc,
    vm,
    proxmox_lxc,
};


/// Container type enumeration
pub const ContainerType = enum {
    lxc,
    crun,
    runc,
    vm,
    proxmox_lxc,
};

/// Resource limits
pub const ResourceLimits = struct {
    memory: ?u64 = null,
    cpu: ?f64 = null,
    disk: ?u64 = null,
    network_bandwidth: ?u64 = null,

    pub fn deinit(self: *ResourceLimits) void {
        _ = self;
    }
};

/// Security configuration
pub const SecurityConfig = struct {
    seccomp: ?bool = null,
    apparmor: ?bool = null,
    capabilities: ?[]const []const u8 = null,
    read_only: ?bool = null,

    pub fn deinit(self: *SecurityConfig) void {
        if (self.capabilities) |caps| {
            for (caps) |cap| {
                // Note: capabilities are not allocated, just referenced
                _ = cap;
            }
        }
    }
};

/// Network configuration
pub const NetworkConfig = struct {
    bridge: ?[]const u8 = null,
    ip: ?[]const u8 = null,
    gateway: ?[]const u8 = null,
    dns: ?[]const []const u8 = null,
    port_mappings: ?[]const PortMapping = null,

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        if (self.bridge) |b| allocator.free(b);
        if (self.ip) |i| allocator.free(i);
        if (self.gateway) |g| allocator.free(g);
        if (self.dns) |d| {
            for (d) |dns| {
                // DNS entries are not allocated, just referenced
                _ = dns;
            }
        }
        if (self.port_mappings) |pm| {
            for (pm) |mapping| {
                mapping.deinit(allocator);
            }
            allocator.free(pm);
        }
    }
};

/// Port mapping
pub const PortMapping = struct {
    host_port: u16,
    container_port: u16,
    protocol: []const u8,

    pub fn deinit(self: *const PortMapping, allocator: std.mem.Allocator) void {
        // protocol is not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Storage configuration
pub const StorageConfig = struct {
    rootfs: ?[]const u8 = null,
    volumes: ?[]const Volume = null,
    tmpfs: ?[]const TmpfsMount = null,

    pub fn deinit(self: *StorageConfig, allocator: std.mem.Allocator) void {
        if (self.rootfs) |r| allocator.free(r);
        if (self.volumes) |v| {
            for (v) |*vol| {
                vol.deinit(allocator);
            }
            allocator.free(v);
        }
        if (self.tmpfs) |t| {
            for (t) |*tmp| {
                tmp.deinit(allocator);
            }
            allocator.free(t);
        }
    }
};

/// Volume mount
pub const Volume = struct {
    source: []const u8,
    destination: []const u8,
    read_only: bool = false,
    options: ?[]const u8 = null,

    pub fn deinit(self: *Volume, allocator: std.mem.Allocator) void {
        // source, destination, options are not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Tmpfs mount
pub const TmpfsMount = struct {
    destination: []const u8,
    size: ?u64 = null,
    mode: ?u32 = null,

    pub fn deinit(self: *TmpfsMount, allocator: std.mem.Allocator) void {
        // destination is not allocated, just referenced
        _ = self;
        _ = allocator;
    }
};

/// Command enumeration
pub const Command = enum {
    create,
    start,
    stop,
    delete,
    list,
    info,
    exec,
    run,
    help,
    version,
    state,
};

/// Runtime options
pub const RuntimeOptions = struct {
    allocator: std.mem.Allocator,
    command: Command,
    container_id: ?[]const u8 = null,
    image: ?[]const u8 = null,
    runtime_type: ?RuntimeType = null,
    config_file: ?[]const u8 = null,
    verbose: bool = false,
    debug: bool = false,
    help: bool = false,
    detach: bool = false,
    interactive: bool = false,
    tty: bool = false,
    user: ?[]const u8 = null,
    workdir: ?[]const u8 = null,
    env: ?[]const []const u8 = null,
    args: ?[]const []const u8 = null,

    pub fn deinit(self: *RuntimeOptions) void {
        if (self.container_id) |id| self.allocator.free(id);
        if (self.image) |img| self.allocator.free(img);
        if (self.config_file) |cfg| self.allocator.free(cfg);
        if (self.user) |u| self.allocator.free(u);
        if (self.workdir) |wd| self.allocator.free(wd);
        if (self.env) |e| {
            for (e) |env_var| {
                // env vars are not allocated, just referenced
                _ = env_var;
            }
        }
        if (self.args) |a| {
            for (a) |arg| {
                // args are not allocated, just referenced
                _ = arg;
            }
        }
    }
};

/// Configuration error types
pub const ConfigError = error{
    InvalidFormat,
    MissingField,
    InvalidValue,
    FileNotFound,
    PermissionDenied,
    ParseError,
};

/// Routing rule for container backend selection
pub const RoutingRule = struct {
    pattern: []const u8,
    runtime: RuntimeType,

    pub fn deinit(self: *const RoutingRule, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
    }
};

/// Container configuration
pub const ContainerConfig = struct {
    // Legacy pattern support (deprecated - use routing instead)
    crun_name_patterns: []const []const u8,
    default_container_type: ContainerType,
    
    // New routing system with regex patterns
    routing: []const RoutingRule,
    default_runtime: RuntimeType,

    pub fn deinit(self: *ContainerConfig, allocator: std.mem.Allocator) void {
        // Clean up legacy patterns
        for (self.crun_name_patterns) |pattern| {
            allocator.free(pattern);
        }
        allocator.free(self.crun_name_patterns);
        
        // Clean up routing rules
        for (self.routing) |rule| {
            rule.deinit(allocator);
        }
        allocator.free(self.routing);
    }
};

/// Signal constants
pub const SIGINT = 2;
pub const SIGTERM = 15;
pub const SIGHUP = 1;

/// Proxmox LXC backend configuration
pub const ProxmoxLxcBackendConfig = struct {
    allocator: std.mem.Allocator,
    // Optional overrides from config file
    zfs_pool: ?[]const u8 = null,
    default_memory_mb: ?u32 = null,
    default_cores: ?u32 = null,
    default_bridge: ?[]const u8 = null,
    default_ostype: ?[]const u8 = null,
    default_unprivileged: ?bool = null,

    pub fn deinit(self: *ProxmoxLxcBackendConfig) void {
        if (self.zfs_pool) |p| self.allocator.free(p);
        if (self.default_bridge) |b| self.allocator.free(b);
        if (self.default_ostype) |o| self.allocator.free(o);
    }
};
