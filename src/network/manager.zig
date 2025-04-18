const std = @import("std");
const types = @import("../types/pod.zig");
const cni = @import("cni.zig");
const cilium = @import("cilium.zig");
const state = @import("state.zig");
const Allocator = std.mem.Allocator;

pub const NetworkError = error{
    ConfigurationError,
    CNIError,
    IPAMError,
    InterfaceError,
    StateError,
    ProxmoxError,
    InitializationFailed,
    InterfaceCreationFailed,
    InterfaceNotFound,
    ConfigurationFailed,
    ConnectionFailed,
    NetworkAlreadyExists,
    NetworkNotFound,
    InvalidState,
    NetworkCreateFailed,
    NetworkDeleteFailed,
    NetworkStartFailed,
    NetworkStopFailed,
};

/// Менеджер мережі
pub const NetworkManager = struct {
    allocator: Allocator,
    cni_plugin: *cni.CNIPlugin,
    networks: std.StringHashMap(*Network),
    
    const Self = @This();
    
    /// Створює новий менеджер мережі
    pub fn init(allocator: Allocator, plugin_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        // Створюємо базову конфігурацію CNI
        const config = cni.CNIConfig{
            .name = "proxmox-net",
            .type = "bridge",
            .cniVersion = cni.CNI_VERSION,
            .args = null,
        };

        // Ініціалізуємо CNI плагін
        const plugin = try allocator.create(cni.CNIPlugin);
        errdefer allocator.destroy(plugin);
        plugin.* = try cni.CNIPlugin.init(allocator, config, plugin_dir);

        self.* = .{
            .allocator = allocator,
            .cni_plugin = plugin,
            .networks = std.StringHashMap(*Network).init(allocator),
        };
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var it = self.networks.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.networks.deinit();
        self.cni_plugin.deinit();
        self.allocator.destroy(self.cni_plugin);
        self.allocator.destroy(self);
    }
    
    /// Створює нову мережу для Pod-а
    pub fn createNetwork(self: *Self, pod_id: []const u8, config: types.NetworkConfig) !void {
        if (self.networks.get(pod_id)) |_| {
            return error.NetworkAlreadyExists;
        }

        var network = try self.allocator.create(Network);
        errdefer self.allocator.destroy(network);

        network.* = try Network.init(self.allocator, pod_id, config, self.cni_plugin);
        errdefer network.deinit();

        try self.networks.put(pod_id, network);
    }
    
    /// Видаляє мережу Pod-а
    pub fn deleteNetwork(self: *Self, pod_id: []const u8) !void {
        const network = self.networks.get(pod_id) orelse return error.NetworkNotFound;
        try network.cleanup();
        network.deinit();
        self.allocator.destroy(network);
        _ = self.networks.remove(pod_id);
    }
    
    /// Запускає мережу Pod-а
    pub fn startNetwork(self: *Self, pod_id: []const u8) !void {
        const network = self.networks.get(pod_id) orelse return error.NetworkNotFound;
        try network.start();
    }
    
    /// Зупиняє мережу Pod-а
    pub fn stopNetwork(self: *Self, pod_id: []const u8) !void {
        const network = self.networks.get(pod_id) orelse return error.NetworkNotFound;
        try network.stop();
    }
    
    /// Отримує статус мережі Pod-а
    pub fn getNetworkStatus(self: *Self, pod_id: []const u8) !NetworkStatus {
        const network = self.networks.get(pod_id) orelse return error.NetworkNotFound;
        return network.getStatus();
    }
};

pub const Network = struct {
    const Self = @This();

    allocator: Allocator,
    pod_id: []const u8,
    config: types.NetworkConfig,
    cni_plugin: *cni.CNIPlugin,
    status: NetworkStatus,

    pub fn init(
        allocator: Allocator,
        pod_id: []const u8,
        config: types.NetworkConfig,
        cni_plugin: *cni.CNIPlugin,
    ) !Self {
        return Self{
            .allocator = allocator,
            .pod_id = try allocator.dupe(u8, pod_id),
            .config = config,
            .cni_plugin = cni_plugin,
            .status = .Created,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.pod_id);
    }

    pub fn start(self: *Self) !void {
        if (self.status != .Created and self.status != .Stopped) {
            return error.InvalidState;
        }

        // Отримуємо шлях до network namespace
        const netns = try std.fmt.allocPrint(
            self.allocator,
            "/proc/{s}/ns/net",
            .{self.pod_id},
        );
        defer self.allocator.free(netns);

        // Додаємо мережу через CNI плагін
        _ = try self.cni_plugin.add(self.pod_id, netns);

        // Налаштовуємо DNS якщо потрібно
        if (self.config.dns.servers.len > 0) {
            try self.setupDNS();
        }

        // Налаштовуємо port forwarding
        for (self.config.port_mappings) |mapping| {
            try self.setupPortForward(mapping);
        }

        self.status = .Running;
    }

    pub fn stop(self: *Self) !void {
        if (self.status != .Running) {
            return error.InvalidState;
        }

        // Видаляємо port forwarding
        for (self.config.port_mappings) |mapping| {
            try self.removePortForward(mapping);
        }

        // Отримуємо шлях до network namespace
        const netns = try std.fmt.allocPrint(
            self.allocator,
            "/proc/{s}/ns/net",
            .{self.pod_id},
        );
        defer self.allocator.free(netns);

        // Видаляємо мережу через CNI плагін
        try self.cni_plugin.delete(self.pod_id, netns);

        self.status = .Stopped;
    }

    pub fn cleanup(self: *Self) !void {
        if (self.status == .Running) {
            try self.stop();
        }
        self.status = .Deleted;
    }

    pub fn getStatus(self: *Self) NetworkStatus {
        return self.status;
    }

    fn setupDNS(self: *Self) !void {
        // TODO: Реалізувати налаштування DNS
    }

    fn setupPortForward(self: *Self, mapping: types.PortMapping) !void {
        // TODO: Реалізувати налаштування port forwarding
    }

    fn removePortForward(self: *Self, mapping: types.PortMapping) !void {
        // TODO: Реалізувати видалення port forwarding
    }
};

pub const NetworkStatus = enum {
    Created,
    Running,
    Stopped,
    Deleted,
};

pub const NetworkInterface = struct {
    name: []const u8,
    ip_address: []const u8,
    netmask: []const u8,
    gateway: ?[]const u8,
    mtu: u32,
    
    pub fn init(allocator: Allocator) !NetworkInterface {
        return NetworkInterface{
            .name = try allocator.dupe(u8, "eth0"),
            .ip_address = try allocator.dupe(u8, "0.0.0.0"),
            .netmask = try allocator.dupe(u8, "255.255.255.0"),
            .gateway = null,
            .mtu = 1500,
        };
    }
    
    pub fn deinit(self: *NetworkInterface, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.ip_address);
        allocator.free(self.netmask);
        if (self.gateway) |g| allocator.free(g);
    }
}; 