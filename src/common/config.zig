const std = @import("std");
const json = @import("zig-json");
const logger = @import("logger");
const types = @import("types");
const errors = @import("error");
const RuntimeType = types.RuntimeType;

pub const ConfigError = error{
    UnknownField,
    InvalidConfig,
    FileNotFound,
    ParseError,
    OutOfMemory,
    InvalidJson,
    MissingRequiredField,
    InvalidValue,
    InvalidType,
    InvalidFormat,
    InvalidPath,
    InvalidPort,
    InvalidToken,
    InvalidNode,
    InvalidHost,
    InvalidBridge,
    InvalidDnsServer,
    InvalidZfsDataset,
    InvalidImagePath,
    InvalidLogLevel,
    InvalidRuntimeType,
    InvalidRuntimePath,
    InvalidLogPath,
    InvalidRootPath,
    InvalidBundlePath,
    InvalidPidFile,
    InvalidConsoleSocket,
    InvalidSystemdCgroup,
    InvalidDebug,
    InvalidContainerConfig,
    InvalidCrunNamePattern,
    InvalidDefaultContainerType,
};

pub const ProxmoxConfig = types.ProxmoxConfig;
pub const StorageConfig = types.StorageConfig;
pub const NetworkConfig = types.NetworkConfig;
pub const ContainerConfig = types.ContainerConfig;
pub const RuntimeConfig = types.RuntimeConfig;
pub const JsonConfig = types.JsonConfig;

pub const Config = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    runtime_type: RuntimeType,
    runtime_path: ?[]const u8,
    default_runtime: ?[]const u8,
    proxmox: ProxmoxConfig,
    storage: StorageConfig,
    network: NetworkConfig,
    logger: *types.LogContext,
    container_config: ContainerConfig,
    log_path: ?[]const u8,
    root_path: []const u8,
    bundle_path: []const u8,
    pid_file: ?[]const u8,
    console_socket: ?[]const u8,
    systemd_cgroup: bool,
    debug: bool,

    pub fn init(allocator: std.mem.Allocator, logger_ctx: *types.LogContext) !Config {
        var container_cfg = try ContainerConfig.init(allocator);
        container_cfg.crun_name_patterns = &[_][]const u8{
            "crun-*",
            "oci-*",
            "podman-*",
        };
        container_cfg.default_container_type = .lxc;
        return Config{
            .allocator = allocator,
            .runtime_type = .runc,
            .runtime_path = null,
            .default_runtime = null,
            .proxmox = try ProxmoxConfig.init(allocator),
            .storage = try StorageConfig.init(allocator),
            .network = try NetworkConfig.init(allocator),
            .logger = logger_ctx,
            .container_config = container_cfg,
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
        if (self.runtime_path) |path| {
            self.allocator.free(path);
        }
        if (self.default_runtime) |rt| {
            self.allocator.free(rt);
        }
        self.proxmox.deinit();
        self.storage.deinit();
        self.network.deinit(self.allocator);
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

    pub fn fromJson(allocator: std.mem.Allocator, json_config: JsonConfig, logger_ctx: *types.LogContext) !Config {
        var config = try Config.init(allocator, logger_ctx);
        errdefer config.deinit();

    // Runtime config
    if (json_config.runtime) |runtime| {
        if (runtime.root_path) |path| {
            config.runtime_path = try allocator.dupe(u8, path);
        }
        if (runtime.log_path) |path| {
            config.log_path = try allocator.dupe(u8, path);
        }
        // log_level не optional, працюємо напряму
        // if (runtime.log_level) |level| {
        //     ...
        // }
    }

    // Default runtime from root json
    if (json_config.default_runtime) |rt| {
        config.default_runtime = try allocator.dupe(u8, rt);
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
        if (network.bridge.len > 0) {
            config.network.bridge = try allocator.dupe(u8, network.bridge);
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

    pub fn getContainerType(self: *Config, container_name: []const u8) types.ContainerType {
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

pub fn deinitJsonConfig(config_value: *JsonConfig, allocator: std.mem.Allocator) void {
    // Safely deallocate runtime config
    if (config_value.runtime) |*runtime| {
        if (runtime.root_path) |path| {
            if (path.len > 0 and path.ptr != undefined) {
                allocator.free(path);
            }
        }
        if (runtime.log_path) |path| {
            if (path.len > 0 and path.ptr != undefined) {
                allocator.free(path);
            }
        }
    }
    
    // Safely deallocate proxmox config
    if (config_value.proxmox) |*proxmox| {
        if (proxmox.hosts) |hosts| {
            if (hosts.ptr != undefined) {
                for (hosts) |host| {
                    if (host.len > 0 and host.ptr != undefined) {
                        allocator.free(host);
                    }
                }
                allocator.free(hosts);
            }
        }
        // Only deallocate if these fields were actually allocated
        if (proxmox.token) |token| {
            if (token.len > 0 and token.ptr != undefined) {
                allocator.free(token);
            }
        }
        if (proxmox.node) |node| {
            if (node.len > 0 and node.ptr != undefined) {
                allocator.free(node);
            }
        }
    }
    
    // Safely deallocate storage config
    if (config_value.storage) |*storage| {
        if (storage.zfs_dataset) |dataset| {
            if (dataset.len > 0 and dataset.ptr != undefined) {
                allocator.free(dataset);
            }
        }
        if (storage.image_path) |path| {
            if (path.len > 0 and path.ptr != undefined) {
                allocator.free(path);
            }
        }
    }
    
    // Safely deallocate network config
    if (config_value.network) |*network| {
        if (network.bridge.len > 0 and network.bridge.ptr != undefined) {
            allocator.free(network.bridge);
        }
        if (network.dns_servers) |servers| {
            if (servers.ptr != undefined) {
                for (servers) |server| {
                    if (server.len > 0 and server.ptr != undefined) {
                        allocator.free(server);
                    }
                }
                allocator.free(servers);
            }
        }
    }
}

const DEFAULT_TIMEOUT_MS: i64 = 10_000;

const IMAGES_DIR = "images";
const BUNDLE_DIR = "bundle";
