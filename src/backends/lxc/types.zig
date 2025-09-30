const std = @import("std");

/// LXC-specific types and structures
/// LXC container options
pub const LxcOptions = struct {
    allocator: std.mem.Allocator,
    template: ?[]const u8 = null,
    arch: ?[]const u8 = null,
    dist: ?[]const u8 = null,
    release: ?[]const u8 = null,
    variant: ?[]const u8 = null,
    mirror: ?[]const u8 = null,
    security_arch: ?[]const u8 = null,
    no_download: bool = false,
    keyserver: ?[]const u8 = null,
    extra_args: ?[]const []const u8 = null,

    pub fn deinit(self: *LxcOptions) void {
        if (self.template) |t| self.allocator.free(t);
        if (self.arch) |a| self.allocator.free(a);
        if (self.dist) |d| self.allocator.free(d);
        if (self.release) |r| self.allocator.free(r);
        if (self.variant) |v| self.allocator.free(v);
        if (self.mirror) |m| self.allocator.free(m);
        if (self.security_arch) |sa| self.allocator.free(sa);
        if (self.keyserver) |k| self.allocator.free(k);
        if (self.extra_args) |args| {
            for (args) |arg| {
                // args are not allocated, just referenced
                _ = arg;
            }
        }
    }
};

/// LXC container configuration
pub const LxcConfig = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    template: []const u8,
    arch: []const u8,
    dist: []const u8,
    release: []const u8,
    variant: ?[]const u8 = null,
    mirror: ?[]const u8 = null,
    security_arch: ?[]const u8 = null,
    no_download: bool = false,
    keyserver: ?[]const u8 = null,
    extra_args: ?[]const []const u8 = null,
    network: ?LxcNetworkConfig = null,
    storage: ?LxcStorageConfig = null,
    security: ?LxcSecurityConfig = null,
    resources: ?LxcResourceConfig = null,

    pub fn deinit(self: *LxcConfig) void {
        self.allocator.free(self.name);
        self.allocator.free(self.template);
        self.allocator.free(self.arch);
        self.allocator.free(self.dist);
        self.allocator.free(self.release);
        if (self.variant) |v| self.allocator.free(v);
        if (self.mirror) |m| self.allocator.free(m);
        if (self.security_arch) |sa| self.allocator.free(sa);
        if (self.keyserver) |k| self.allocator.free(k);
        if (self.extra_args) |args| {
            for (args) |arg| {
                // args are not allocated, just referenced
                _ = arg;
            }
        }
        if (self.network) |*net| net.deinit();
        if (self.storage) |*stor| stor.deinit();
        if (self.security) |*sec| sec.deinit();
        if (self.resources) |*res| res.deinit();
    }
};

/// LXC network configuration
pub const LxcNetworkConfig = struct {
    allocator: std.mem.Allocator,
    type: []const u8 = "veth",
    link: ?[]const u8 = null,
    flags: ?[]const u8 = null,
    name: ?[]const u8 = null,
    hwaddr: ?[]const u8 = null,
    mtu: ?u32 = null,
    ipv4: ?[]const u8 = null,
    ipv6: ?[]const u8 = null,
    script_up: ?[]const u8 = null,
    script_down: ?[]const u8 = null,

    pub fn deinit(self: *LxcNetworkConfig) void {
        self.allocator.free(self.type);
        if (self.link) |l| self.allocator.free(l);
        if (self.flags) |f| self.allocator.free(f);
        if (self.name) |n| self.allocator.free(n);
        if (self.hwaddr) |h| self.allocator.free(h);
        if (self.ipv4) |ip4| self.allocator.free(ip4);
        if (self.ipv6) |ip6| self.allocator.free(ip6);
        if (self.script_up) |su| self.allocator.free(su);
        if (self.script_down) |sd| self.allocator.free(sd);
    }
};

/// LXC storage configuration
pub const LxcStorageConfig = struct {
    allocator: std.mem.Allocator,
    type: []const u8 = "dir",
    source: ?[]const u8 = null,
    size: ?u64 = null,
    fstype: ?[]const u8 = null,
    options: ?[]const u8 = null,

    pub fn deinit(self: *LxcStorageConfig) void {
        self.allocator.free(self.type);
        if (self.source) |s| self.allocator.free(s);
        if (self.fstype) |fs| self.allocator.free(fs);
        if (self.options) |opts| self.allocator.free(opts);
    }
};

/// LXC security configuration
pub const LxcSecurityConfig = struct {
    allocator: std.mem.Allocator,
    privileged: bool = false,
    id_maps: ?[]const IdMap = null,
    capabilities: ?[]const []const u8 = null,
    seccomp: ?[]const u8 = null,
    apparmor: ?[]const u8 = null,
    selinux: ?[]const u8 = null,

    pub fn deinit(self: *LxcSecurityConfig) void {
        if (self.id_maps) |maps| {
            for (maps) |map| {
                map.deinit(self.allocator);
            }
            self.allocator.free(maps);
        }
        if (self.capabilities) |caps| {
            for (caps) |cap| {
                // capabilities are not allocated, just referenced
                _ = cap;
            }
        }
        if (self.seccomp) |s| self.allocator.free(s);
        if (self.apparmor) |a| self.allocator.free(a);
        if (self.selinux) |s| self.allocator.free(s);
    }
};

/// ID mapping for user namespaces
pub const IdMap = struct {
    allocator: std.mem.Allocator,
    type: []const u8, // "uid" or "gid"
    host_id: u32,
    container_id: u32,
    range: u32,

    pub fn deinit(self: *const IdMap, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
    }
};

/// LXC resource configuration
pub const LxcResourceConfig = struct {
    allocator: std.mem.Allocator,
    memory: ?u64 = null,
    memory_swap: ?u64 = null,
    cpu_shares: ?u64 = null,
    cpuset: ?[]const u8 = null,
    blkio_weight: ?u16 = null,
    blkio_device_weight: ?[]const BlkioDeviceWeight = null,
    blkio_device_read_bps: ?[]const BlkioDeviceLimit = null,
    blkio_device_write_bps: ?[]const BlkioDeviceLimit = null,
    blkio_device_read_iops: ?[]const BlkioDeviceLimit = null,
    blkio_device_write_iops: ?[]const BlkioDeviceLimit = null,

    pub fn deinit(self: *LxcResourceConfig) void {
        if (self.cpuset) |cs| self.allocator.free(cs);
        if (self.blkio_device_weight) |bdw| {
            for (bdw) |weight| {
                weight.deinit(self.allocator);
            }
            self.allocator.free(bdw);
        }
        if (self.blkio_device_read_bps) |bdrb| {
            for (bdrb) |limit| {
                limit.deinit(self.allocator);
            }
            self.allocator.free(bdrb);
        }
        if (self.blkio_device_write_bps) |bdwb| {
            for (bdwb) |limit| {
                limit.deinit(self.allocator);
            }
            self.allocator.free(bdwb);
        }
        if (self.blkio_device_read_iops) |bdri| {
            for (bdri) |limit| {
                limit.deinit(self.allocator);
            }
            self.allocator.free(bdri);
        }
        if (self.blkio_device_write_iops) |bdwi| {
            for (bdwi) |limit| {
                limit.deinit(self.allocator);
            }
            self.allocator.free(bdwi);
        }
    }
};

/// Block I/O device weight
pub const BlkioDeviceWeight = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    weight: u16,

    pub fn deinit(self: *const BlkioDeviceWeight, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// Block I/O device limit
pub const BlkioDeviceLimit = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    rate: u64,

    pub fn deinit(self: *const BlkioDeviceLimit, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

/// LXC container state
pub const LxcState = enum {
    stopped,
    starting,
    running,
    stopping,
    aborting,
    freezing,
    frozen,
    thawed,
    unknown,
};

/// LXC container information
pub const LxcContainerInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    state: LxcState,
    pid: ?u32 = null,
    created: ?i64 = null,
    started: ?i64 = null,
    stopped: ?i64 = null,
    config_file: ?[]const u8 = null,

    pub fn deinit(self: *LxcContainerInfo) void {
        self.allocator.free(self.name);
        if (self.config_file) |cf| self.allocator.free(cf);
    }
};
