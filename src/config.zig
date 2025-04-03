const std = @import("std");
const json = std.json;
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    allocator: Allocator,
    proxmox: ProxmoxConfig,
    runtime: RuntimeConfig,

    pub fn init(allocator: Allocator) !Config {
        return Config{
            .allocator = allocator,
            .proxmox = try ProxmoxConfig.init(allocator),
            .runtime = try RuntimeConfig.init(allocator),
        };
    }

    pub fn deinit(self: *Config) void {
        self.proxmox.deinit();
        self.runtime.deinit();
    }

    pub fn loadFromFile(self: *Config, path: []const u8) !void {
        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(buffer);

        _ = try file.readAll(buffer);

        var parsed = try json.parseFromSlice(Config, self.allocator, buffer, .{});
        self.* = parsed.value;
    }
};

pub const ProxmoxConfig = struct {
    allocator: Allocator,
    host: []const u8,
    port: u16,
    token: []const u8,
    node: []const u8,
    storage: []const u8,
    network_bridge: []const u8,

    pub fn init(allocator: Allocator) !ProxmoxConfig {
        return ProxmoxConfig{
            .allocator = allocator,
            .host = try allocator.dupe(u8, "localhost"),
            .port = 8006,
            .token = try allocator.dupe(u8, ""),
            .node = try allocator.dupe(u8, "localhost"),
            .storage = try allocator.dupe(u8, "local-lvm"),
            .network_bridge = try allocator.dupe(u8, "vmbr0"),
        };
    }

    pub fn deinit(self: *ProxmoxConfig) void {
        self.allocator.free(self.host);
        self.allocator.free(self.token);
        self.allocator.free(self.node);
        self.allocator.free(self.storage);
        self.allocator.free(self.network_bridge);
    }
};

pub const RuntimeConfig = struct {
    allocator: Allocator,
    socket_path: []const u8,
    log_level: LogLevel,
    default_memory: u32,
    default_swap: u32,
    default_cores: u32,
    default_rootfs_size: []const u8,

    pub fn init(allocator: Allocator) !RuntimeConfig {
        return RuntimeConfig{
            .allocator = allocator,
            .socket_path = try allocator.dupe(u8, "/var/run/proxmox-lxcri.sock"),
            .log_level = .info,
            .default_memory = 512,
            .default_swap = 256,
            .default_cores = 1,
            .default_rootfs_size = try allocator.dupe(u8, "8G"),
        };
    }

    pub fn deinit(self: *RuntimeConfig) void {
        self.allocator.free(self.socket_path);
        self.allocator.free(self.default_rootfs_size);
    }
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
}; 