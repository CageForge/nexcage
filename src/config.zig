const std = @import("std");
const json = std.json;
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
    node_cache_duration: u64, // Cache duration in seconds
};

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
            .timeout = 30_000, // 30 секунд
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
    }

    pub fn loadFromFile(self: *Config, path: []const u8) !void {
        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = try json.parseFromSliceLeaky(json.Value, self.allocator, content, .{});
        //defer parsed.deinit();
        if (parsed == .object) {
            if (parsed.object.get("proxmox")) |proxmox_config| {
                const proxmox = proxmox_config.object;
                
                if (proxmox.get("hosts")) |hosts| {
                    var host_list = std.ArrayList([]const u8).init(self.allocator);
                    defer host_list.deinit();

                    for (hosts.array.items) |host| {
                        try host_list.append(try self.allocator.dupe(u8, host.string));
                    }

                    self.proxmox.hosts = try host_list.toOwnedSlice();
                } else {
                    return Error.ProxmoxInvalidConfig;
                }

                if (proxmox.get("token")) |token| {
                    self.proxmox.token = try self.allocator.dupe(u8, token.string);
                } else {
                    return Error.ProxmoxInvalidConfig;
                }

                const port = if (proxmox.get("port")) |port_value|
                    @as(u16, @intCast(port_value.integer))
                else
                    8006;
                self.proxmox.port = port;

                if (proxmox.get("node")) |node| {
                    self.proxmox.node = try self.allocator.dupe(u8, node.string);
                } else {
                    return Error.ProxmoxInvalidConfig;
                }

                if (proxmox.get("node_cache_duration")) |duration| {
                    self.proxmox.node_cache_duration = @as(u64, @intCast(duration.integer));
                } else {
                    return Error.ProxmoxInvalidConfig;
                }
            } else {
                return Error.ProxmoxInvalidConfig;
            }

            if (parsed.object.get("runtime")) |runtime_config| {
                const runtime = runtime_config.object;

                if (runtime.get("socket_path")) |socket_path| {
                    self.runtime.socket_path = try self.allocator.dupe(u8, socket_path.string);
                } else {
                    return Error.ProxmoxInvalidConfig;
                }

                if (runtime.get("log_level")) |log_level| {
                    self.runtime.log_level = try self.allocator.dupe(u8, log_level.string);
                } else {
                    return Error.ProxmoxInvalidConfig;
                }
            } else {
                return Error.ProxmoxInvalidConfig;
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
