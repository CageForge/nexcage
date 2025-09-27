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
    resources: ?ResourceLimits = null,
    security: ?SecurityConfig = null,
    network: ?NetworkConfig = null,
    storage: ?StorageConfig = null,

    pub fn deinit(self: *SandboxConfig) void {
        self.allocator.free(self.name);
        if (self.resources) |*r| r.deinit();
        if (self.security) |*s| s.deinit();
        if (self.network) |*n| n.deinit();
        if (self.storage) |*s| s.deinit();
    }
};

/// Runtime type enumeration
pub const RuntimeType = enum {
    lxc,
    qemu,
    crun,
    runc,
    vm,
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
    allocator: std.mem.Allocator,
    bridge: ?[]const u8 = null,
    ip: ?[]const u8 = null,
    gateway: ?[]const u8 = null,
    dns: ?[]const []const u8 = null,
    port_mappings: ?[]const PortMapping = null,

    pub fn deinit(self: *NetworkConfig) void {
        if (self.bridge) |b| self.allocator.free(b);
        if (self.ip) |i| self.allocator.free(i);
        if (self.gateway) |g| self.allocator.free(g);
        if (self.dns) |d| {
            for (d) |dns| {
                // DNS entries are not allocated, just referenced
                _ = dns;
            }
        }
        if (self.port_mappings) |pm| {
            for (pm) |mapping| {
                mapping.deinit();
            }
            self.allocator.free(pm);
        }
    }
};

/// Port mapping
pub const PortMapping = struct {
    host_port: u16,
    container_port: u16,
    protocol: []const u8,

    pub fn deinit(self: *const PortMapping) void {
        // protocol is not allocated, just referenced
        _ = self;
    }
};

/// Storage configuration
pub const StorageConfig = struct {
    allocator: std.mem.Allocator,
    rootfs: ?[]const u8 = null,
    volumes: ?[]const Volume = null,
    tmpfs: ?[]const TmpfsMount = null,

    pub fn deinit(self: *StorageConfig) void {
        if (self.rootfs) |r| self.allocator.free(r);
        if (self.volumes) |v| {
            for (v) |*vol| {
                vol.deinit();
            }
            self.allocator.free(v);
        }
        if (self.tmpfs) |t| {
            for (t) |*tmp| {
                tmp.deinit();
            }
            self.allocator.free(t);
        }
    }
};

/// Volume mount
pub const Volume = struct {
    source: []const u8,
    destination: []const u8,
    read_only: bool = false,
    options: ?[]const u8 = null,

    pub fn deinit(self: *Volume) void {
        // source, destination, options are not allocated, just referenced
        _ = self;
    }
};

/// Tmpfs mount
pub const TmpfsMount = struct {
    destination: []const u8,
    size: ?u64 = null,
    mode: ?u32 = null,

    pub fn deinit(self: *TmpfsMount) void {
        // destination is not allocated, just referenced
        _ = self;
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

/// Signal constants
pub const SIGINT = 2;
pub const SIGTERM = 15;
pub const SIGHUP = 1;
