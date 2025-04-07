const std = @import("std");
const json = std.json;
const fs = std.fs;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");

pub const Config = struct {
    allocator: Allocator,
    proxmox: ProxmoxConfig,
    runtime: RuntimeConfig,

    pub fn init(allocator: Allocator) !Config {
        return Config{
            .allocator = allocator,
            .proxmox = ProxmoxConfig{
                .hosts = &[_][]const u8{"localhost"},
                .current_host_index = 0,
                .port = 8006,
                .token = "",
                .node = "localhost",
                .node_cache_duration = 60, // Default 60 seconds
            },
            .runtime = RuntimeConfig{
                .log_level = .info,
                .socket_path = "/var/run/proxmox-lxcri.sock",
            },
        };
    }

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.proxmox.token);
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

        var parsed = try json.parseFromSlice(json.Value, self.allocator, file_content, .{});
        defer parsed.deinit();

        const root = parsed.value;

        // Parse Proxmox configuration
        if (root.object.get("proxmox")) |proxmox_obj| {
            if (proxmox_obj.object.get("hosts")) |hosts| {
                if (hosts == .array) {
                    var host_list = std.ArrayList([]const u8).init(self.allocator);
                    defer host_list.deinit();

                    for (hosts.array.items) |host| {
                        if (host == .string) {
                            try host_list.append(try self.allocator.dupe(u8, host.string));
                        }
                    }

                    self.proxmox.hosts = try host_list.toOwnedSlice();
                }
            }
            if (proxmox_obj.object.get("port")) |port| {
                if (port == .integer) {
                    self.proxmox.port = @intCast(port.integer);
                }
            }
            if (proxmox_obj.object.get("token")) |token| {
                if (token == .string) {
                    self.proxmox.token = try self.allocator.dupe(u8, token.string);
                }
            }
            if (proxmox_obj.object.get("node")) |node| {
                if (node == .string) {
                    self.proxmox.node = try self.allocator.dupe(u8, node.string);
                }
            }
            if (proxmox_obj.object.get("node_cache_duration")) |duration| {
                if (duration == .integer) {
                    self.proxmox.node_cache_duration = @intCast(duration.integer);
                }
            }
        }

        // Parse Runtime configuration
        if (root.object.get("runtime")) |runtime_obj| {
            if (runtime_obj.object.get("log_level")) |log_level| {
                if (log_level == .string) {
                    self.runtime.log_level = std.meta.stringToEnum(types.LogLevel, log_level.string) orelse .info;
                }
            }
            if (runtime_obj.object.get("socket_path")) |socket_path| {
                if (socket_path == .string) {
                    self.runtime.socket_path = try self.allocator.dupe(u8, socket_path.string);
                }
            }
        }
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
