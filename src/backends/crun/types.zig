const std = @import("std");
const core = @import("core");

/// Crun backend specific types
/// OCI container configuration
pub const OciContainerConfig = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    image: []const u8,
    command: ?[]const u8 = null,
    args: ?[][]const u8 = null,
    env: ?[][]const u8 = null,
    working_dir: ?[]const u8 = null,
    user: ?[]const u8 = null,
    memory_limit: ?u64 = null,
    cpu_limit: ?f64 = null,
    network_mode: ?[]const u8 = null,
    ports: ?[]PortMapping = null,
    volumes: ?[]VolumeMount = null,
    privileged: bool = false,
    interactive: bool = false,
    tty: bool = false,
    detach: bool = true,

    pub fn deinit(self: *OciContainerConfig) void {
        self.allocator.free(self.name);
        self.allocator.free(self.image);
        if (self.command) |cmd| self.allocator.free(cmd);
        if (self.args) |args| {
            for (args) |arg| self.allocator.free(arg);
            self.allocator.free(args);
        }
        if (self.env) |env| {
            for (env) |e| self.allocator.free(e);
            self.allocator.free(env);
        }
        if (self.working_dir) |wd| self.allocator.free(wd);
        if (self.user) |u| self.allocator.free(u);
        if (self.network_mode) |nm| self.allocator.free(nm);
        if (self.ports) |p| self.allocator.free(p);
        if (self.volumes) |v| {
            for (v) |vol| vol.deinit();
            self.allocator.free(v);
        }
    }
};

/// Port mapping
pub const PortMapping = struct {
    host_port: u16,
    container_port: u16,
    protocol: []const u8 = "tcp",
    host_ip: ?[]const u8 = null,

    pub fn deinit(self: *PortMapping) void {
        self.allocator.free(self.protocol);
        if (self.host_ip) |ip| self.allocator.free(ip);
    }
};

/// Volume mount
pub const VolumeMount = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    destination: []const u8,
    read_only: bool = false,
    bind_propagation: ?[]const u8 = null,

    pub fn deinit(self: *VolumeMount) void {
        self.allocator.free(self.source);
        self.allocator.free(self.destination);
        if (self.bind_propagation) |bp| self.allocator.free(bp);
    }
};

/// Container status
pub const ContainerStatus = enum {
    created,
    running,
    paused,
    restarting,
    removing,
    exited,
    dead,
    unknown,
};

/// Container information
pub const ContainerInfo = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    image: []const u8,
    status: ContainerStatus,
    created: i64,
    started_at: ?i64 = null,
    finished_at: ?i64 = null,
    exit_code: ?i32 = null,
    pid: ?u32 = null,
    ip_address: ?[]const u8 = null,

    pub fn deinit(self: *ContainerInfo) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.image);
        if (self.ip_address) |ip| self.allocator.free(ip);
    }
};

/// Crun backend configuration
pub const CrunBackendConfig = struct {
    allocator: std.mem.Allocator,
    crun_path: []const u8 = "crun",
    runtime_path: ?[]const u8 = null,
    root_path: ?[]const u8 = null,
    log_level: ?[]const u8 = null,
    debug: bool = false,

    pub fn deinit(self: *CrunBackendConfig) void {
        self.allocator.free(self.crun_path);
        if (self.runtime_path) |rp| self.allocator.free(rp);
        if (self.root_path) |rp| self.allocator.free(rp);
        if (self.log_level) |ll| self.allocator.free(ll);
    }
};
