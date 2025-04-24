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

        var scanner = try std.json.Scanner.initCompleteInput(self.allocator, content);
        defer scanner.deinit();
        
        var count: usize = 0;
        
        // Parse root object
        _ = try scanner.next(); // Skip first {
        
        while (true) {
            const token = try scanner.next();
            switch (token) {
                .ObjectEnd => break,
                .String => |str| {
                    if (std.mem.eql(u8, str, "proxmox")) {
                        try self.parseProxmoxConfig(&scanner);
                    } else if (std.mem.eql(u8, str, "runtime")) {
                        try self.parseRuntimeConfig(&scanner);
                    } else {
                        try skipValue(&scanner); // Skip unknown fields
                    }
                },
                else => return error.InvalidJson,
            }
            count += 1;
        }
    }

    fn parseProxmoxConfig(self: *Config, scanner: *std.json.Scanner) !void {
        _ = try scanner.next(); // Skip {
        
        while (true) {
            const token = try scanner.next();
            switch (token) {
                .ObjectEnd => break,
                .String => |key| {
                    if (std.mem.eql(u8, key, "hosts")) {
                        _ = try scanner.next(); // Skip [
                        var host_list = std.ArrayList([]const u8).init(self.allocator);
                        errdefer host_list.deinit();
                        
                        while (true) {
                            const host_token = try scanner.next();
                            switch (host_token) {
                                .ArrayEnd => break,
                                .String => |host| {
                                    try host_list.append(try self.allocator.dupe(u8, host));
                                },
                                else => return error.InvalidJson,
                            }
                        }
                        self.proxmox.hosts = try host_list.toOwnedSlice();
                    } else if (std.mem.eql(u8, key, "port")) {
                        const port_token = try scanner.next();
                        switch (port_token) {
                            .Number => |n| self.proxmox.port = @intFromFloat(n),
                            else => return error.InvalidJson,
                        }
                    } else if (std.mem.eql(u8, key, "token")) {
                        const token_value = try scanner.next();
                        switch (token_value) {
                            .String => |str| self.proxmox.token = try self.allocator.dupe(u8, str),
                            else => return error.InvalidJson,
                        }
                    } else if (std.mem.eql(u8, key, "node")) {
                        const node_token = try scanner.next();
                        switch (node_token) {
                            .String => |str| self.proxmox.node = try self.allocator.dupe(u8, str),
                            else => return error.InvalidJson,
                        }
                    } else if (std.mem.eql(u8, key, "node_cache_duration")) {
                        const duration_token = try scanner.next();
                        switch (duration_token) {
                            .Number => |n| self.proxmox.node_cache_duration = @intFromFloat(n),
                            else => return error.InvalidJson,
                        }
                    } else {
                        try skipValue(scanner); // Skip unknown fields
                    }
                },
                else => return error.InvalidJson,
            }
        }
    }

    fn parseRuntimeConfig(self: *Config, scanner: *std.json.Scanner) !void {
        _ = try scanner.next(); // Skip {
        
        while (true) {
            const token = try scanner.next();
            switch (token) {
                .ObjectEnd => break,
                .String => |key| {
                    if (std.mem.eql(u8, key, "socket_path")) {
                        const path_token = try scanner.next();
                        switch (path_token) {
                            .String => |str| self.runtime.socket_path = try self.allocator.dupe(u8, str),
                            else => return error.InvalidJson,
                        }
                    } else if (std.mem.eql(u8, key, "log_level")) {
                        const level_token = try scanner.next();
                        switch (level_token) {
                            .String => |str| self.runtime.log_level = try self.allocator.dupe(u8, str),
                            else => return error.InvalidJson,
                        }
                    } else {
                        try skipValue(scanner); // Skip unknown fields
                    }
                },
                else => return error.InvalidJson,
            }
        }
    }

    fn skipValue(scanner: *std.json.Scanner) !void {
        var depth: usize = 0;
        while (true) {
            const token = try scanner.next();
            switch (token) {
                .ObjectBegin, .ArrayBegin => depth += 1,
                .ObjectEnd, .ArrayEnd => {
                    if (depth == 0) return;
                    depth -= 1;
                },
                .String, .Number, .True, .False, .Null => {
                    if (depth == 0) return;
                },
                else => return error.InvalidJson,
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
