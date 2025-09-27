const std = @import("std");
const types = @import("types.zig");
const logging = @import("logging.zig");

/// Configuration loader and manager
pub const ConfigLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Load configuration from default locations
    pub fn loadDefault(self: *Self) !Config {
        // Try to load from default locations in order
        const default_paths = [_][]const u8{
            "./config.json",
            "/etc/proxmox-lxcri/config.json",
            "/etc/proxmox-lxcri/proxmox-lxcri.json",
        };

        for (default_paths) |path| {
            if (self.loadFromFile(path)) |config| {
                return config;
            } else |err| switch (err) {
                types.Error.FileNotFound => continue,
                else => return err,
            }
        }

        // Return default config if no file found
        return Config.init(self.allocator, .lxc);
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Self, path: []const u8) !Config {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return types.Error.FileNotFound,
            else => return err,
        };
        defer self.allocator.free(file_content);

        return self.loadFromString(file_content);
    }

    /// Load configuration from string
    pub fn loadFromString(self: *Self, json_string: []const u8) !Config {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_string, .{}) catch |err| switch (err) {
            error.InvalidCharacter => return types.Error.InvalidConfig,
            error.InvalidNumber => return types.Error.InvalidConfig,
            error.UnexpectedEndOfInput => return types.Error.InvalidConfig,
            else => return err,
        };
        defer parsed.deinit();

        const value = parsed.value;
        return self.parseConfig(value);
    }

    fn parseConfig(self: *Self, value: std.json.Value) !Config {
        var config = Config.init(self.allocator, .lxc); // default

        if (value.object.get("runtime_type")) |runtime_value| {
            switch (runtime_value) {
                .string => |runtime_str| {
                    config.runtime_type = self.parseRuntimeType(runtime_str);
                },
                else => {},
            }
        }

        if (value.object.get("default_runtime")) |default_value| {
            switch (default_value) {
                .string => |default_str| {
                    config.default_runtime = try self.allocator.dupe(u8, default_str);
                },
                else => {},
            }
        }

        if (value.object.get("log_level")) |level_value| {
            switch (level_value) {
                .string => |level_str| {
                    config.log_level = self.parseLogLevel(level_str);
                },
                else => {},
            }
        }

        if (value.object.get("log_file")) |file_value| {
            switch (file_value) {
                .string => |file_str| {
                    config.log_file = try self.allocator.dupe(u8, file_str);
                },
                else => {},
            }
        }

        if (value.object.get("data_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    config.data_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        if (value.object.get("cache_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    config.cache_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        if (value.object.get("temp_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    config.temp_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        if (value.object.get("network")) |network_value| {
            config.network = try self.parseNetworkConfig(network_value);
        }

        if (value.object.get("security")) |security_value| {
            config.security = try self.parseSecurityConfig(security_value);
        }

        if (value.object.get("resources")) |resources_value| {
            config.resources = try self.parseResourceLimits(resources_value);
        }

        return config;
    }

    fn parseRuntimeType(self: *Self, runtime_str: []const u8) types.RuntimeType {
        _ = self;
        if (std.mem.eql(u8, runtime_str, "lxc")) {
            return .lxc;
        } else if (std.mem.eql(u8, runtime_str, "crun")) {
            return .crun;
        } else if (std.mem.eql(u8, runtime_str, "runc")) {
            return .runc;
        } else if (std.mem.eql(u8, runtime_str, "proxmox")) {
            return .vm; // proxmox maps to vm
        }
        return .lxc; // default
    }

    fn parseLogLevel(self: *Self, level_str: []const u8) logging.LogLevel {
        _ = self;
        if (std.mem.eql(u8, level_str, "debug")) {
            return .debug;
        } else if (std.mem.eql(u8, level_str, "info")) {
            return .info;
        } else if (std.mem.eql(u8, level_str, "warn")) {
            return .warn;
        } else if (std.mem.eql(u8, level_str, "error")) {
            return logging.LogLevel.@"error";
        }
        return .info; // default
    }

    fn parseNetworkConfig(self: *Self, value: std.json.Value) !types.NetworkConfig {
        var config = types.NetworkConfig{
            .allocator = self.allocator,
            .bridge = try self.allocator.dupe(u8, "lxcbr0"),
            .ip = null,
            .gateway = null,
        };

        if (value.object.get("bridge")) |bridge_value| {
            switch (bridge_value) {
                .string => |bridge_str| {
                    self.allocator.free(config.bridge);
                    config.bridge = try self.allocator.dupe(u8, bridge_str);
                },
                else => {},
            }
        }

        if (value.object.get("ip")) |ip_value| {
            switch (ip_value) {
                .string => |ip_str| {
                    config.ip = try self.allocator.dupe(u8, ip_str);
                },
                else => {},
            }
        }

        if (value.object.get("gateway")) |gateway_value| {
            switch (gateway_value) {
                .string => |gateway_str| {
                    config.gateway = try self.allocator.dupe(u8, gateway_str);
                },
                else => {},
            }
        }

        return config;
    }

    fn parseSecurityConfig(self: *Self, value: std.json.Value) !types.SecurityConfig {
        _ = self;
        _ = value;
        return types.SecurityConfig{
            .seccomp = null,
            .apparmor = null,
            .capabilities = null,
            .read_only = null,
        };
    }

    fn parseResourceLimits(self: *Self, value: std.json.Value) !types.ResourceLimits {
        _ = self;
        _ = value;
        return types.ResourceLimits{
            .memory = null,
            .cpu = null,
            .disk = null,
            .network_bandwidth = null,
        };
    }
};

/// Global configuration structure
pub const Config = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    runtime_type: types.RuntimeType,
    default_runtime: []const u8,
    log_level: logging.LogLevel,
    log_file: ?[]const u8,
    data_dir: []const u8,
    cache_dir: []const u8,
    temp_dir: []const u8,
    network: types.NetworkConfig,
    security: types.SecurityConfig,
    resources: types.ResourceLimits,

    pub fn init(allocator: std.mem.Allocator, runtime_type: types.RuntimeType) Config {
        return Config{
            .allocator = allocator,
            .runtime_type = runtime_type,
            .default_runtime = "lxc",
            .log_level = logging.LogLevel.info,
            .log_file = null,
            .data_dir = "/var/lib/proxmox-lxcri",
            .cache_dir = "/var/cache/proxmox-lxcri",
            .temp_dir = "/tmp/proxmox-lxcri",
            .network = types.NetworkConfig{
                .allocator = allocator,
                .bridge = "lxcbr0",
                .ip = null,
                .gateway = null,
            },
            .security = types.SecurityConfig{
                .seccomp = null,
                .apparmor = null,
                .capabilities = null,
                .read_only = null,
            },
            .resources = types.ResourceLimits{
                .memory = null,
                .cpu = null,
                .disk = null,
                .network_bandwidth = null,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.default_runtime);
        if (self.log_file) |log_file| {
            self.allocator.free(log_file);
        }
        self.allocator.free(self.data_dir);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.temp_dir);
        self.network.deinit();
        self.security.deinit();
        self.resources.deinit();
    }
};
