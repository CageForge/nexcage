const std = @import("std");
const json = std.json;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const types = @import("types");
const logger_mod = @import("logger");

const ConfigFile = struct {
    proxmox: struct {
        hosts: []const []const u8,
        port: u16 = 8006,
        token: []const u8,
        node: []const u8,
        node_cache_duration: u64 = 60,
    },
    runtime: struct {
        log_level: []const u8 = "info",
        socket_path: []const u8 = "/var/run/proxmox-lxcri.sock",
    },
};

pub const Config = struct {
    allocator: Allocator,
    proxmox: ProxmoxConfig,
    runtime: RuntimeConfig,
    logger: *logger_mod.Logger,

    pub fn init(allocator: Allocator) !Config {
        var hosts = try allocator.alloc([]const u8, 1);
        hosts[0] = try allocator.dupe(u8, "localhost");

        return Config{
            .allocator = allocator,
            .proxmox = ProxmoxConfig{
                .hosts = hosts,
                .current_host_index = 0,
                .port = 8006,
                .token = try allocator.dupe(u8, ""),
                .node = try allocator.dupe(u8, "localhost"),
                .node_cache_duration = 60, // Default 60 seconds
            },
            .runtime = RuntimeConfig{
                .log_level = .info,
                .socket_path = try allocator.dupe(u8, "/var/run/proxmox-lxcri.sock"),
            },
            .logger = undefined,
        };
    }

    pub fn deinit(self: *Config) void {
        for (self.proxmox.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.proxmox.hosts);
        self.allocator.free(self.proxmox.token);
        self.allocator.free(self.proxmox.node);
        self.allocator.free(self.runtime.socket_path);
    }

    pub fn loadFromFile(self: *Config, path: []const u8) !void {
        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const file_content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(file_content);

        const bytes_read = try file.readAll(file_content);
        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }

        var parsed = try json.parseFromSlice(ConfigFile, self.allocator, file_content, .{});
        defer parsed.deinit();

        const config = parsed.value;

        // Free old memory
        for (self.proxmox.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.proxmox.hosts);
        self.allocator.free(self.proxmox.token);
        self.allocator.free(self.proxmox.node);
        self.allocator.free(self.runtime.socket_path);

        // Update Proxmox configuration
        var hosts = try self.allocator.alloc([]const u8, config.proxmox.hosts.len);
        for (config.proxmox.hosts, 0..) |host, i| {
            hosts[i] = try self.allocator.dupe(u8, host);
        }
        self.proxmox.hosts = hosts;
        self.proxmox.port = config.proxmox.port;
        self.proxmox.token = try self.allocator.dupe(u8, config.proxmox.token);
        self.proxmox.node = try self.allocator.dupe(u8, config.proxmox.node);
        self.proxmox.node_cache_duration = config.proxmox.node_cache_duration;

        // Update Runtime configuration
        self.runtime.log_level = std.meta.stringToEnum(types.LogLevel, config.runtime.log_level) orelse .info;
        self.runtime.socket_path = try self.allocator.dupe(u8, config.runtime.socket_path);
    }
};

pub const ProxmoxConfig = struct {
    hosts: []const []const u8,
    current_host_index: usize,
    port: u16,
    token: []const u8,
    node: []const u8,
    node_cache_duration: u64, // Cache duration in seconds
};

pub const RuntimeConfig = struct {
    log_level: types.LogLevel,
    socket_path: []const u8,
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};
