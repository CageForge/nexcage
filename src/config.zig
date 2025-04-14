const std = @import("std");
const json = std.json;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const types = @import("types");
const logger_mod = @import("logger");
const Error = @import("error").Error;
const mem = std.mem;

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
    hosts: []const []const u8,
    token: []const u8,
    port: u16,
    node: []const u8,
    node_cache_duration: u64,
    timeout: u64,
    logger: *logger_mod.Logger,

    pub fn init(allocator: Allocator, logger_instance: *logger_mod.Logger) !Config {
        return Config{
            .allocator = allocator,
            .hosts = &[_][]const u8{},
            .token = "",
            .port = 8006,
            .node = "",
            .node_cache_duration = 300, // 5 minutes
            .timeout = 30_000, // 30 seconds
            .logger = logger_instance,
        };
    }

    pub fn deinit(self: *Config) void {
        for (self.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.hosts);
        self.allocator.free(self.token);
        self.allocator.free(self.node);
    }

    pub fn loadFromFile(self: *Config, path: []const u8) !void {
        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(content);

        const parsed = try json.parseFromSlice(json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        if (parsed.value.get("hosts")) |hosts| {
            var host_list = std.ArrayList([]const u8).init(self.allocator);
            defer host_list.deinit();

            for (hosts.array.items) |host| {
                try host_list.append(try self.allocator.dupe(u8, host.string));
            }

            self.hosts = try host_list.toOwnedSlice();
        } else {
            return Error.ProxmoxInvalidConfig;
        }

        if (parsed.value.get("token")) |token| {
            self.token = try self.allocator.dupe(u8, token.string);
        } else {
            return Error.ProxmoxInvalidConfig;
        }

        if (parsed.value.get("port")) |port| {
            self.port = @intCast(port.integer);
        }

        if (parsed.value.get("node")) |node| {
            self.node = try self.allocator.dupe(u8, node.string);
        } else {
            return Error.ProxmoxInvalidConfig;
        }

        if (parsed.value.get("node_cache_duration")) |duration| {
            self.node_cache_duration = @intCast(duration.integer);
        }

        if (parsed.value.get("timeout")) |timeout| {
            self.timeout = @intCast(timeout.integer);
        }
    }

    pub fn validate(self: *const Config) !void {
        if (self.hosts.len == 0) return Error.ProxmoxInvalidConfig;
        if (self.token.len == 0) return Error.ProxmoxInvalidToken;
        if (self.node.len == 0) return Error.ProxmoxInvalidNode;
        if (self.port == 0) return Error.ProxmoxInvalidConfig;
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
