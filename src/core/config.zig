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
        return try Config.init(self.allocator, .lxc);
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

    pub fn parseConfig(self: *Self, value: std.json.Value) !Config {
        // Start with default config
        var config = try Config.init(self.allocator, .lxc);

        // runtime_type
        if (value.object.get("runtime_type")) |runtime_value| {
            switch (runtime_value) {
                .string => |runtime_str| {
                    config.runtime_type = self.parseRuntimeType(runtime_str);
                },
                else => {},
            }
        }

        // default_runtime
        if (value.object.get("default_runtime")) |default_value| {
            switch (default_value) {
                .string => |default_str| {
                    // replace allocated string safely
                    self.allocator.free(config.default_runtime);
                    config.default_runtime = try self.allocator.dupe(u8, default_str);
                },
                else => {},
            }
        }

        // log_level
        if (value.object.get("log_level")) |level_value| {
            switch (level_value) {
                .string => |level_str| {
                    config.log_level = self.parseLogLevel(level_str);
                },
                else => {},
            }
        }

        // log_file
        if (value.object.get("log_file")) |file_value| {
            switch (file_value) {
                .string => |file_str| {
                    if (config.log_file) |old| self.allocator.free(old);
                    config.log_file = try self.allocator.dupe(u8, file_str);
                },
                else => {},
            }
        }

        // data_dir
        if (value.object.get("data_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.data_dir);
                    config.data_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // cache_dir
        if (value.object.get("cache_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.cache_dir);
                    config.cache_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // temp_dir
        if (value.object.get("temp_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.temp_dir);
                    config.temp_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // network
        if (value.object.get("network")) |network_value| {
            // start from existing defaults
            var net = config.network;
            const obj = network_value.object;

            if (obj.get("bridge")) |bridge_value| {
                switch (bridge_value) {
                    .string => |bridge_str| {
                        if (net.bridge) |old_bridge| self.allocator.free(old_bridge);
                        net.bridge = try self.allocator.dupe(u8, bridge_str);
                    },
                    else => {},
                }
            }

            if (obj.get("ip")) |ip_value| {
                switch (ip_value) {
                    .string => |ip_str| {
                        if (net.ip) |old_ip| self.allocator.free(old_ip);
                        net.ip = try self.allocator.dupe(u8, ip_str);
                    },
                    else => {},
                }
            }

            if (obj.get("gateway")) |gateway_value| {
                switch (gateway_value) {
                    .string => |gw_str| {
                        if (net.gateway) |old_gw| self.allocator.free(old_gw);
                        net.gateway = try self.allocator.dupe(u8, gw_str);
                    },
                    else => {},
                }
            }

            config.network = net;
        }

        // security
        if (value.object.get("security")) |sec_value| {
            const obj = sec_value.object;
            var sec = config.security;

            if (obj.get("seccomp")) |v| {
                switch (v) {
                    .bool => |b| sec.seccomp = b,
                    else => {},
                }
            }
            if (obj.get("apparmor")) |v| {
                switch (v) {
                    .bool => |b| sec.apparmor = b,
                    else => {},
                }
            }
            if (obj.get("read_only")) |v| {
                switch (v) {
                    .bool => |b| sec.read_only = b,
                    else => {},
                }
            }

            // capabilities: array of strings (by reference; not allocating here)
            // If needed later, we can dupe each entry and manage lifetime

            config.security = sec;
        }

        // resources
        if (value.object.get("resources")) |res_value| {
            const obj = res_value.object;
            var res = config.resources;

            if (obj.get("memory")) |v| {
                switch (v) {
                    .integer => |n| res.memory = @intCast(n),
                    else => {},
                }
            }
            if (obj.get("cpu")) |v| {
                switch (v) {
                    .float => |f| res.cpu = f,
                    .integer => |n| res.cpu = @floatFromInt(n),
                    else => {},
                }
            }
            if (obj.get("disk")) |v| {
                switch (v) {
                    .integer => |n| res.disk = @intCast(n),
                    else => {},
                }
            }
            if (obj.get("network_bandwidth")) |v| {
                switch (v) {
                    .integer => |n| res.network_bandwidth = @intCast(n),
                    else => {},
                }
            }

            config.resources = res;
        }

        // container_config
        if (value.object.get("container_config")) |container_value| {
            const obj = container_value.object;
            var container_cfg = config.container_config;

            if (obj.get("crun_name_patterns")) |patterns_value| {
                switch (patterns_value) {
                    .array => |patterns_array| {
                        var patterns = try self.allocator.alloc([]const u8, patterns_array.items.len);
                        for (patterns_array.items, 0..) |pattern_item, i| {
                            switch (pattern_item) {
                                .string => |pattern_str| {
                                    patterns[i] = try self.allocator.dupe(u8, pattern_str);
                                },
                                else => {},
                            }
                        }
                        container_cfg.crun_name_patterns = patterns;
                    },
                    else => {},
                }
            }

            if (obj.get("default_container_type")) |type_value| {
                switch (type_value) {
                    .string => |type_str| {
                        container_cfg.default_container_type = self.parseContainerType(type_str);
                    },
                    else => {},
                }
            }

            config.container_config = container_cfg;
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

    fn parseContainerType(self: *Self, type_str: []const u8) types.ContainerType {
        _ = self;
        if (std.mem.eql(u8, type_str, "lxc")) {
            return .lxc;
        } else if (std.mem.eql(u8, type_str, "crun")) {
            return .crun;
        } else if (std.mem.eql(u8, type_str, "runc")) {
            return .runc;
        } else if (std.mem.eql(u8, type_str, "vm")) {
            return .vm;
        }
        return .lxc; // default
    }

    pub fn parseNetworkConfig(self: *Self, value: std.json.Value) !types.NetworkConfig {
        var config = types.NetworkConfig{
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
    container_config: types.ContainerConfig,

    pub fn init(allocator: std.mem.Allocator, runtime_type: types.RuntimeType) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = runtime_type,
            .default_runtime = try allocator.dupe(u8, "lxc"),
            .log_level = logging.LogLevel.info,
            .log_file = null,
            .data_dir = try allocator.dupe(u8, "/var/lib/proxmox-lxcri"),
            .cache_dir = try allocator.dupe(u8, "/var/cache/proxmox-lxcri"),
            .temp_dir = try allocator.dupe(u8, "/tmp/proxmox-lxcri"),
            .network = types.NetworkConfig{
                .bridge = try allocator.dupe(u8, "lxcbr0"),
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
            .container_config = types.ContainerConfig{
                .crun_name_patterns = &[_][]const u8{},
                .default_container_type = .lxc,
            },
        };
    }

    pub fn getContainerType(self: *const Self, container_name: []const u8) types.ContainerType {
        for (self.container_config.crun_name_patterns) |pattern| {
            if (self.matchesPattern(container_name, pattern)) {
                return .crun;
            }
        }
        return self.container_config.default_container_type;
    }

    fn matchesPattern(_: *const Self, name: []const u8, pattern: []const u8) bool {
        var name_idx: usize = 0;
        var pattern_idx: usize = 0;

        while (pattern_idx < pattern.len) {
            if (pattern[pattern_idx] == '*') {
                // Skip until next pattern character or end
                while (name_idx < name.len and (pattern_idx + 1 >= pattern.len or name[name_idx] != pattern[pattern_idx + 1])) {
                    name_idx += 1;
                }
                pattern_idx += 1;
            } else if (name_idx < name.len and pattern[pattern_idx] == name[name_idx]) {
                name_idx += 1;
                pattern_idx += 1;
            } else {
                return false;
            }
        }

        return name_idx == name.len;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.default_runtime);
        if (self.log_file) |log_file| {
            self.allocator.free(log_file);
        }
        self.allocator.free(self.data_dir);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.temp_dir);
        self.network.deinit(self.allocator);
        self.security.deinit();
        self.resources.deinit();
        self.container_config.deinit(self.allocator);
    }
};
