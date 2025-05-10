const std = @import("std");
const json = std.json;
const logger = @import("logger");
const types = @import("types");
const errors = @import("error");

pub const Config = struct {
    allocator: std.mem.Allocator,
    runtime: RuntimeConfig,
    proxmox: ProxmoxConfig,
    storage: StorageConfig,
    network: NetworkConfig,
    logger: *logger.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger_ctx: *logger.LogContext) !Config {
        return Config{
            .allocator = allocator,
            .runtime = try RuntimeConfig.init(allocator),
            .proxmox = try ProxmoxConfig.init(allocator),
            .storage = try StorageConfig.init(allocator),
            .network = try NetworkConfig.init(allocator),
            .logger = logger_ctx,
        };
    }

    pub fn deinit(self: *Config) void {
        self.runtime.deinit();
        self.proxmox.deinit();
        self.storage.deinit();
        self.network.deinit();
    }

    pub fn fromJson(allocator: std.mem.Allocator, json_config: JsonConfig, logger_ctx: *logger.LogContext) !Config {
        var config = try Config.init(allocator, logger_ctx);
        errdefer config.deinit();

        // Runtime config
        if (json_config.runtime) |runtime| {
            if (runtime.root_path) |path| {
                config.runtime.root_path = try allocator.dupe(u8, path);
            }
            if (runtime.log_path) |path| {
                config.runtime.log_path = try allocator.dupe(u8, path);
            }
            if (runtime.log_level) |level| {
                config.runtime.log_level = level;
            }
        }

        // Proxmox config
        if (json_config.proxmox) |proxmox| {
            if (proxmox.hosts) |hosts| {
                config.proxmox.hosts = try allocator.dupe([]const u8, hosts);
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
                config.network.dns_servers = try allocator.dupe([]const u8, servers);
            }
        }

        return config;
    }
};

pub const RuntimeConfig = struct {
    root_path: ?[]const u8 = null,
    log_path: ?[]const u8 = null,
    log_level: types.LogLevel = .info,

    pub fn init(allocator: std.mem.Allocator) !RuntimeConfig {
        _ = allocator;
        return RuntimeConfig{};
    }

    pub fn deinit(self: *RuntimeConfig) void {
        if (self.root_path) |path| {
            std.heap.page_allocator.free(path);
        }
        if (self.log_path) |path| {
            std.heap.page_allocator.free(path);
        }
    }
};

pub const ProxmoxConfig = struct {
    hosts: []const []const u8 = &[_][]const u8{},
    port: u16 = 8006,
    token: ?[]const u8 = null,
    node: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !ProxmoxConfig {
        _ = allocator;
        return ProxmoxConfig{};
    }

    pub fn deinit(self: *ProxmoxConfig) void {
        for (self.hosts) |host| {
            std.heap.page_allocator.free(host);
        }
        if (self.token) |token| {
            std.heap.page_allocator.free(token);
        }
        if (self.node) |node| {
            std.heap.page_allocator.free(node);
        }
    }
};

pub const StorageConfig = struct {
    zfs_dataset: ?[]const u8 = null,
    image_path: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !StorageConfig {
        _ = allocator;
        return StorageConfig{};
    }

    pub fn deinit(self: *StorageConfig) void {
        if (self.zfs_dataset) |dataset| {
            std.heap.page_allocator.free(dataset);
        }
        if (self.image_path) |path| {
            std.heap.page_allocator.free(path);
        }
    }
};

pub const NetworkConfig = struct {
    bridge: ?[]const u8 = null,
    dns_servers: []const []const u8 = &[_][]const u8{},

    pub fn init(allocator: std.mem.Allocator) !NetworkConfig {
        _ = allocator;
        return NetworkConfig{};
    }

    pub fn deinit(self: *NetworkConfig) void {
        if (self.bridge) |bridge| {
            std.heap.page_allocator.free(bridge);
        }
        for (self.dns_servers) |server| {
            std.heap.page_allocator.free(server);
        }
    }
};

pub const JsonConfig = struct {
    runtime: ?struct {
        root_path: ?[]const u8,
        log_path: ?[]const u8,
        log_level: ?types.LogLevel,
    } = null,
    proxmox: ?struct {
        hosts: ?[]const []const u8,
        port: ?u16,
        token: ?[]const u8,
        node: ?[]const u8,
    } = null,
    storage: ?struct {
        zfs_dataset: ?[]const u8,
        image_path: ?[]const u8,
    } = null,
    network: ?struct {
        bridge: ?[]const u8,
        dns_servers: ?[]const []const u8,
    } = null,
};
