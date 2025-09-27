const std = @import("std");
const core = @import("core");

/// Proxmox VM backend specific types
/// VM configuration for Proxmox
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

/// VM status
pub const VmStatus = enum {
    stopped,
    running,
    paused,
    unknown,
};

/// VM information
pub const VmInfo = struct {
    allocator: std.mem.Allocator,
    vmid: u32,
    name: []const u8,
    status: VmStatus,
    memory: u64,
    cores: u32,
    sockets: u32,
    cpu: []const u8,
    ip_address: ?[]const u8 = null,
    uptime: ?u64 = null,

    pub fn deinit(self: *VmInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.cpu);
        if (self.ip_address) |ip| self.allocator.free(ip);
    }
};

/// VM backend configuration
pub const ProxmoxVmBackendConfig = struct {
    allocator: std.mem.Allocator,
    proxmox_host: []const u8,
    proxmox_port: u16 = 8006,
    proxmox_token: []const u8,
    proxmox_node: []const u8,
    verify_ssl: bool = false,
    timeout: ?u64 = null,

    pub fn deinit(self: *ProxmoxVmBackendConfig) void {
        self.allocator.free(self.proxmox_host);
        self.allocator.free(self.proxmox_token);
        self.allocator.free(self.proxmox_node);
    }
};
