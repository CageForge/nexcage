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
            .proxmox = ProxmoxConfig{
                .host = "localhost",
                .port = 8006,
                .token = "",
            },
            .runtime = RuntimeConfig{
                .log_level = .info,
                .socket_path = "/var/run/proxmox-lxcri.sock",
            },
        };
    }

    pub fn deinit(self: *Config) void {
        self.allocator.free(self.proxmox.host);
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
            if (proxmox_obj.object.get("host")) |host| {
                if (host == .string) {
                    self.proxmox.host = try self.allocator.dupe(u8, host.string);
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
        }

        // Parse Runtime configuration
        if (root.object.get("runtime")) |runtime_obj| {
            if (runtime_obj.object.get("log_level")) |log_level| {
                if (log_level == .string) {
                    self.runtime.log_level = std.meta.stringToEnum(LogLevel, log_level.string) orelse .info;
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
    host: []const u8,
    port: u16,
    token: []const u8,
};

pub const RuntimeConfig = struct {
    log_level: LogLevel,
    socket_path: []const u8,
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};
