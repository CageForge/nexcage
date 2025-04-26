const std = @import("std");
const json = @import("json");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const types = @import("types");
const logger_mod = @import("logger");
const Error = @import("error").Error;
const mem = std.mem;

pub const ProxmoxConfig = struct {
    hosts: []const []const u8,
    port: u16,
    token: []const u8,
    node: []const u8,
    node_cache_duration: u64,
};

pub const Config = struct {
    proxmox: ProxmoxConfig,
    runtime: struct {
        socket_path: []const u8,
        log_level: []const u8,
    },
    logger: *logger_mod.Logger,
    timeout: u32,
    node_cache_duration: u64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, logger_instance: *logger_mod.Logger) !Config {
        return Config{
            .allocator = allocator,
            .proxmox = .{
                .hosts = &[_][]const u8{},
                .token = "",
                .port = 8006,
                .node = "",
                .node_cache_duration = 60,
            },
            .runtime = .{
                .socket_path = "/var/run/proxmox-lxcri.sock",
                .log_level = "info",
            },
            .logger = logger_instance,
            .timeout = 30_000,
            .node_cache_duration = 300,
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
        self.allocator.free(self.runtime.log_level);
    }

    pub fn loadFromFile(self: *Config, file_path: []const u8) !void {
        const file = try fs.cwd().openFile(file_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        const value = try json.parse(content, self.allocator);
        defer value.deinit(self.allocator);

        // Parse proxmox config
        if (value.object().getOrNull("proxmox")) |proxmox_obj| {
            if (proxmox_obj.object().getOrNull("hosts")) |hosts_arr| {
                const arr = hosts_arr.array();
                const hosts = try self.allocator.alloc([]const u8, arr.len());
                for (arr.items(), 0..) |host, i| {
                    hosts[i] = try self.allocator.dupe(u8, host.string());
                }
                self.proxmox.hosts = hosts;
            }

            if (proxmox_obj.object().getOrNull("port")) |port| {
                self.proxmox.port = @intCast(port.integer());
            }

            if (proxmox_obj.object().getOrNull("token")) |token| {
                self.proxmox.token = try self.allocator.dupe(u8, token.string());
            }

            if (proxmox_obj.object().getOrNull("node")) |node| {
                self.proxmox.node = try self.allocator.dupe(u8, node.string());
            }

            if (proxmox_obj.object().getOrNull("node_cache_duration")) |duration| {
                self.proxmox.node_cache_duration = @intCast(duration.integer());
            }
        }

        // Parse runtime config
        if (value.object().getOrNull("runtime")) |runtime_obj| {
            if (runtime_obj.object().getOrNull("socket_path")) |socket_path| {
                self.runtime.socket_path = try self.allocator.dupe(u8, socket_path.string());
            }

            if (runtime_obj.object().getOrNull("log_level")) |log_level| {
                self.runtime.log_level = try self.allocator.dupe(u8, log_level.string());
            }
        }
    }
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
