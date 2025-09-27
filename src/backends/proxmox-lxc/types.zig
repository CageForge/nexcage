const std = @import("std");
const core = @import("core");

/// Proxmox LXC backend specific types
/// LXC container configuration for Proxmox
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

/// LXC container status
pub const LxcStatus = enum {
    stopped,
    running,
    paused,
    unknown,
};

/// LXC container information
pub const LxcInfo = struct {
    allocator: std.mem.Allocator,
    vmid: u32,
    hostname: []const u8,
    status: LxcStatus,
    memory: u64,
    cores: u32,
    rootfs: []const u8,
    ip_address: ?[]const u8 = null,
    uptime: ?u64 = null,

    pub fn deinit(self: *LxcInfo) void {
        self.allocator.free(self.hostname);
        self.allocator.free(self.rootfs);
        if (self.ip_address) |ip| self.allocator.free(ip);
    }
};

/// LXC backend configuration
pub const ProxmoxLxcBackendConfig = struct {
    allocator: std.mem.Allocator,
    proxmox_host: []const u8,
    proxmox_port: u16 = 8006,
    proxmox_token: []const u8,
    proxmox_node: []const u8,
    verify_ssl: bool = false,
    timeout: ?u64 = null,

    pub fn deinit(self: *ProxmoxLxcBackendConfig) void {
        self.allocator.free(self.proxmox_host);
        self.allocator.free(self.proxmox_token);
        self.allocator.free(self.proxmox_node);
    }
};
