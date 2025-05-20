const std = @import("std");
const json = std.json;
const logger = @import("logger");
const types = @import("types");
const errors = @import("error");
const container = @import("container");
const RuntimeType = @import("oci/runtime/mod.zig").RuntimeType;

pub const ConfigError = error{
    UnknownField,
    InvalidConfig,
} || std.mem.Allocator.Error;

pub const Config = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    runtime_type: RuntimeType,
    runtime_path: ?[]const u8,
    proxmox: ProxmoxConfig,
    storage: StorageConfig,
    network: NetworkConfig,
    logger: *logger.LogContext,
    container_config: ContainerConfig,
    log_path: ?[]const u8,
    root_path: []const u8,
    bundle_path: []const u8,
    pid_file: ?[]const u8,
    console_socket: ?[]const u8,
    systemd_cgroup: bool,
    debug: bool,

    pub fn init(allocator: std.mem.Allocator, logger_ctx: *logger.LogContext) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = .runc,
            .runtime_path = null,
            .proxmox = try ProxmoxConfig.init(allocator),
            .storage = try StorageConfig.init(allocator),
            .network = try NetworkConfig.init(allocator),
            .logger = logger_ctx,
            .container_config = ContainerConfig{
                .crun_name_patterns = &[_][]const u8{
                    "crun-*",
                    "oci-*",
                    "podman-*",
                },
                .default_container_type = .lxc,
            },
            .log_path = null,
            .root_path = "/var/run/proxmox-lxcri",
            .bundle_path = "/var/lib/proxmox-lxcri",
            .pid_file = null,
            .console_socket = null,
            .systemd_cgroup = false,
            .debug = false,
        };
    }

    pub fn deinit(self: *Config) void {
        self.runtime_path = null;
        self.proxmox.deinit();
        self.storage.deinit();
        self.network.deinit();
        if (self.log_path) |path| {
            self.allocator.free(path);
        }
        if (self.pid_file) |file| {
            self.allocator.free(file);
        }
        if (self.console_socket) |socket| {
            self.allocator.free(socket);
        }
    }

    pub fn fromJson(allocator: std.mem.Allocator, json_config: JsonConfig, logger_ctx: *logger.LogContext) !Config {
        var config = try Config.init(allocator, logger_ctx);
        errdefer config.deinit();

        // Runtime config
        if (json_config.runtime) |runtime| {
            if (runtime.root_path) |path| {
                config.runtime_path = try allocator.dupe(u8, path);
            }
            if (runtime.log_path) |path| {
                config.runtime_path = try allocator.dupe(u8, path);
            }
            if (runtime.log_level) |level| {
                config.runtime_type = level;
            }
        }

        // Proxmox config
        if (json_config.proxmox) |proxmox| {
            if (proxmox.hosts) |hosts| {
                var new_hosts = try allocator.alloc([]const u8, hosts.len);
                errdefer {
                    for (new_hosts) |host| {
                        allocator.free(host);
                    }
                    allocator.free(new_hosts);
                }
                for (hosts, 0..) |host, i| {
                    new_hosts[i] = try allocator.dupe(u8, host);
                }
                config.proxmox.hosts = new_hosts;
            }
            if (proxmox.port) |port| {
                config.proxmox.port = port;
            }
            if (proxmox.token) |token| {
                config.proxmox.token = try allocator.dupe(u8, token);
            }
            if (proxmox.node) |node| {
                config.proxmox.node = try allocator.dupe(u8, node);
            }
        }

        // Storage config
        if (json_config.storage) |storage| {
            if (storage.zfs_dataset) |dataset| {
                config.storage.zfs_dataset = try allocator.dupe(u8, dataset);
            }
            if (storage.image_path) |path| {
                config.storage.image_path = try allocator.dupe(u8, path);
            }
        }

        // Network config
        if (json_config.network) |network| {
            if (network.bridge) |bridge| {
                config.network.bridge = try allocator.dupe(u8, bridge);
            }
            if (network.dns_servers) |servers| {
                var new_servers = try allocator.alloc([]const u8, servers.len);
                errdefer {
                    for (new_servers) |server| {
                        allocator.free(server);
                    }
                    allocator.free(new_servers);
                }
                for (servers, 0..) |server, i| {
                    new_servers[i] = try allocator.dupe(u8, server);
                }
                config.network.dns_servers = new_servers;
            }
        }
        
        return config;
    }

    pub fn getContainerType(self: *Config, container_name: []const u8) container.ContainerType {
        for (self.container_config.crun_name_patterns) |pattern| {
            if (self.matchesPattern(container_name, pattern)) {
                return .crun;
            }
        }
        return self.container_config.default_container_type;
    }

    fn matchesPattern(_: *Config, name: []const u8, pattern: []const u8) bool {
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

    pub fn setRuntimeType(self: *Config, runtime_type: RuntimeType) void {
        self.runtime_type = runtime_type;
    }

    pub fn setRuntimePath(self: *Config, path: []const u8) !void {
        if (self.runtime_path) |old_path| {
            self.allocator.free(old_path);
        }
        self.runtime_path = try self.allocator.dupe(u8, path);
    }

    pub fn getRuntimePath(self: *Config) ![]const u8 {
        if (self.runtime_path) |path| {
            return path;
        }

        const default_path = switch (self.runtime_type) {
            .runc => "/usr/bin/runc",
            .crun => "/usr/bin/crun",
        };

        // Перевіряємо чи існує файл
        const file = std.fs.openFileAbsolute(default_path, .{}) catch {
            return error.RuntimeNotFound;
        };
        defer file.close();

        return try self.allocator.dupe(u8, default_path);
    }
};

pub const RuntimeConfig = struct {
    root_path: ?[]const u8 = null,
    log_path: ?[]const u8 = null,
    log_level: types.LogLevel = .info,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !RuntimeConfig {
        return RuntimeConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeConfig) void {
        if (self.root_path) |path| {
            self.allocator.free(path);
        }
        if (self.log_path) |path| {
            self.allocator.free(path);
        }
    }
};

pub const ProxmoxConfig = struct {
    hosts: []const []const u8 = &[_][]const u8{},
    port: u16 = 8006,
    token: ?[]const u8 = null,
    node: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ProxmoxConfig {
        return ProxmoxConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProxmoxConfig) void {
        for (self.hosts) |host| {
            self.allocator.free(host);
        }
        if (self.hosts.len > 0) {
            self.allocator.free(self.hosts);
        }
        if (self.token) |token| {
            self.allocator.free(token);
        }
        if (self.node) |node| {
            self.allocator.free(node);
        }
    }
};

pub const StorageConfig = struct {
    zfs_dataset: ?[]const u8 = null,
    image_path: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !StorageConfig {
        return StorageConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StorageConfig) void {
        if (self.zfs_dataset) |dataset| {
            self.allocator.free(dataset);
        }
        if (self.image_path) |path| {
            self.allocator.free(path);
        }
    }
};

pub const NetworkConfig = struct {
    bridge: ?[]const u8 = null,
    dns_servers: []const []const u8 = &[_][]const u8{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !NetworkConfig {
        return NetworkConfig{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NetworkConfig) void {
        if (self.bridge) |bridge| {
            self.allocator.free(bridge);
        }
        for (self.dns_servers) |server| {
            self.allocator.free(server);
        }
        if (self.dns_servers.len > 0) {
            self.allocator.free(self.dns_servers);
        }
    }
};

pub const JsonConfig = struct {
    runtime: ?struct {
        root_path: ?[]const u8 = null,
        log_path: ?[]const u8 = null,
        log_level: ?types.LogLevel = null,
    } = null,
    proxmox: ?struct {
        hosts: ?[]const []const u8 = null,
        port: ?u16 = null,
        token: ?[]const u8 = null,
        node: ?[]const u8 = null,
    } = null,
    storage: ?struct {
        zfs_dataset: ?[]const u8 = null,
        image_path: ?[]const u8 = null,
    } = null,
    network: ?struct {
        bridge: ?[]const u8 = null,
        dns_servers: ?[]const []const u8 = null,
    } = null,
};

pub fn deinitJsonConfig(config_value: *JsonConfig, allocator: std.mem.Allocator) void {
    if (config_value.runtime) |runtime| {
        if (runtime.root_path) |path| allocator.free(path);
        if (runtime.log_path) |path| allocator.free(path);
    }
    if (config_value.proxmox) |proxmox| {
        if (proxmox.hosts) |hosts| {
            for (hosts) |host| allocator.free(host);
            allocator.free(hosts);
        }
        if (proxmox.token) |token| allocator.free(token);
        if (proxmox.node) |node| allocator.free(node);
    }
    if (config_value.storage) |storage| {
        if (storage.zfs_dataset) |dataset| allocator.free(dataset);
        if (storage.image_path) |path| allocator.free(path);
    }
    if (config_value.network) |network| {
        if (network.bridge) |bridge| allocator.free(bridge);
        if (network.dns_servers) |servers| {
            for (servers) |server| allocator.free(server);
            allocator.free(servers);
        }
    }
}

pub const ContainerConfig = struct {
    crun_name_patterns: []const []const u8,
    default_container_type: container.ContainerType,
};

const DEFAULT_TIMEOUT_MS: i64 = 10_000;

const IMAGES_DIR = "images";
const BUNDLE_DIR = "bundle";
