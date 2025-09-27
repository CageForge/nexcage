const std = @import("std");

/// Proxmox API specific types and structures
/// Proxmox API configuration
pub const ProxmoxApiConfig = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16 = 8006,
    token: []const u8,
    node: []const u8,
    verify_ssl: bool = false,
    timeout: ?u64 = null,

    pub fn deinit(self: *ProxmoxApiConfig) void {
        self.allocator.free(self.host);
        self.allocator.free(self.token);
        self.allocator.free(self.node);
    }
};

/// Proxmox API response
pub const ProxmoxResponse = struct {
    allocator: std.mem.Allocator,
    data: ?std.json.Value = null,
    success: bool = false,
    message: ?[]const u8 = null,
    status_code: u16 = 0,

    pub fn deinit(self: *ProxmoxResponse) void {
        if (self.data) |d| {
            d.deinit();
        }
        if (self.message) |m| {
            self.allocator.free(m);
        }
    }
};

/// Proxmox LXC container configuration
pub const ProxmoxLxcConfig = struct {
    allocator: std.mem.Allocator,
    vmid: u32,
    hostname: []const u8,
    memory: u64 = 512,
    cores: u32 = 1,
    rootfs: []const u8,
    net0: ?[]const u8 = null,
    ostemplate: ?[]const u8 = null,
    password: ?[]const u8 = null,
    ssh_public_keys: ?[]const u8 = null,
    unprivileged: bool = true,
    onboot: bool = false,
    start: bool = false,

    pub fn deinit(self: *ProxmoxLxcConfig) void {
        self.allocator.free(self.hostname);
        self.allocator.free(self.rootfs);
        if (self.net0) |net| self.allocator.free(net);
        if (self.ostemplate) |ost| self.allocator.free(ost);
        if (self.password) |pass| self.allocator.free(pass);
        if (self.ssh_public_keys) |keys| self.allocator.free(keys);
    }
};

/// Proxmox VM configuration
pub const ProxmoxVmConfig = struct {
    allocator: std.mem.Allocator,
    vmid: u32,
    name: []const u8,
    memory: u64 = 1024,
    cores: u32 = 1,
    sockets: u32 = 1,
    cpu: []const u8 = "host",
    scsi0: ?[]const u8 = null,
    ide0: ?[]const u8 = null,
    net0: ?[]const u8 = null,
    bootdisk: ?[]const u8 = null,
    onboot: bool = false,
    start: bool = false,

    pub fn deinit(self: *ProxmoxVmConfig) void {
        self.allocator.free(self.name);
        self.allocator.free(self.cpu);
        if (self.scsi0) |scsi| self.allocator.free(scsi);
        if (self.ide0) |ide| self.allocator.free(ide);
        if (self.net0) |net| self.allocator.free(net);
        if (self.bootdisk) |boot| self.allocator.free(boot);
    }
};

/// Proxmox template information
pub const ProxmoxTemplate = struct {
    allocator: std.mem.Allocator,
    volid: []const u8,
    format: []const u8,
    size: u64,
    ctime: i64,
    description: ?[]const u8 = null,

    pub fn deinit(self: *ProxmoxTemplate) void {
        self.allocator.free(self.volid);
        self.allocator.free(self.format);
        if (self.description) |desc| self.allocator.free(desc);
    }
};

/// Proxmox node information
pub const ProxmoxNode = struct {
    allocator: std.mem.Allocator,
    node: []const u8,
    status: []const u8,
    cpu: f64,
    maxcpu: u32,
    mem: u64,
    maxmem: u64,
    uptime: u64,
    level: ?[]const u8 = null,

    pub fn deinit(self: *ProxmoxNode) void {
        self.allocator.free(self.node);
        self.allocator.free(self.status);
        if (self.level) |l| self.allocator.free(l);
    }
};

/// Proxmox storage information
pub const ProxmoxStorage = struct {
    allocator: std.mem.Allocator,
    storage: []const u8,
    type: []const u8,
    content: []const u8,
    shared: bool = false,
    enabled: bool = true,
    used: ?u64 = null,
    avail: ?u64 = null,
    total: ?u64 = null,

    pub fn deinit(self: *ProxmoxStorage) void {
        self.allocator.free(self.storage);
        self.allocator.free(self.type);
        self.allocator.free(self.content);
    }
};

/// Proxmox API error types
pub const ProxmoxApiError = error{
    ConnectionFailed,
    AuthenticationFailed,
    InvalidResponse,
    ResourceNotFound,
    ResourceExists,
    InsufficientPermissions,
    InvalidConfiguration,
    OperationFailed,
    NetworkError,
    Timeout,
};
