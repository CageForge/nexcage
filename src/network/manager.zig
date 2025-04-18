const std = @import("std");
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
};

/// Менеджер мережі
pub const NetworkManager = struct {
    allocator: Allocator,
    cilium_plugin: *cilium.CiliumPlugin,
    state_manager: *state.NetworkStateManager,
    
    const Self = @This();
    
    /// Створює новий менеджер мережі
    pub fn init(
        allocator: Allocator,
        config_dir: []const u8,
        state_dir: []const u8,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        // Створюємо конфігурацію Cilium
        var cilium_config = try cilium.CiliumConfig.init(allocator, "cilium");
        cilium_config.enable_endpoint_routes = true;
        cilium_config.enable_ipv4 = true;
        cilium_config.enable_ipv6 = false;
        cilium_config.ipam = .{
            .type = "cilium-ipam",
            .pool_v4 = "10.0.0.0/16",
        };
        cilium_config.dns = .{
            .servers = &[_][]const u8{
                "8.8.8.8",
                "1.1.1.1",
            },
            .options = &[_][]const u8{
                "ndots:5",
            },
        };
        
        // Створюємо Cilium плагін
        const plugin = try cilium.CiliumPlugin.init(allocator, cilium_config);
        errdefer plugin.deinit();
        
        // Створюємо менеджер стану
        const state_manager = try state.NetworkStateManager.init(allocator, state_dir);
        errdefer state_manager.deinit();
        
        self.* = .{
            .allocator = allocator,
            .cilium_plugin = plugin,
            .state_manager = state_manager,
        };
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.cilium_plugin.deinit();
        self.state_manager.deinit();
        self.allocator.destroy(self);
    }
    
    /// Додає мережевий інтерфейс до контейнера
    pub fn setupNetwork(
        self: *Self,
        container_id: []const u8,
        netns: []const u8,
    ) !*state.NetworkState {
        // Викликаємо Cilium CNI для налаштування мережі
        const result = try self.cilium_plugin.add(container_id, netns);
        if (!result.success) {
            if (result.error) |err| {
                std.log.err(
                    "Failed to setup network for container {s}: {s}",
                    .{ container_id, err.msg },
                );
            }
            return NetworkError.CNIError;
        }
        
        // Парсимо результат
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            result.message.?,
            .{},
        );
        defer parsed.deinit();
        
        // Створюємо запис про стан мережі
        const network_state = try state.NetworkState.init(
            self.allocator,
            container_id,
            "eth0", // TODO: make configurable
            parsed.value.object.get("mac").?.string,
        );
        errdefer network_state.deinit(self.allocator);
        
        // Зберігаємо IP адреси
        if (parsed.value.object.get("ips")) |ips| {
            for (ips.array.items) |ip| {
                const version = ip.object.get("version").?.string;
                const address = ip.object.get("address").?.string;
                
                if (std.mem.eql(u8, version, "4")) {
                    network_state.ip_v4 = try self.allocator.dupe(u8, address);
                } else if (std.mem.eql(u8, version, "6")) {
                    network_state.ip_v6 = try self.allocator.dupe(u8, address);
                }
            }
        }
        
        // Зберігаємо DNS конфігурацію
        if (parsed.value.object.get("dns")) |dns| {
            const dns_config = try self.allocator.create(state.NetworkState.DNSConfig);
            
            // Копіюємо DNS сервери
            const servers = dns.object.get("servers").?.array;
            dns_config.servers = try self.allocator.alloc([]const u8, servers.items.len);
            for (servers.items, 0..) |server, i| {
                dns_config.servers[i] = try self.allocator.dupe(u8, server.string);
            }
            
            // Копіюємо search домени
            const search = dns.object.get("search").?.array;
            dns_config.search = try self.allocator.alloc([]const u8, search.items.len);
            for (search.items, 0..) |domain, i| {
                dns_config.search[i] = try self.allocator.dupe(u8, domain.string);
            }
            
            // Копіюємо опції
            const options = dns.object.get("options").?.array;
            dns_config.options = try self.allocator.alloc([]const u8, options.items.len);
            for (options.items, 0..) |opt, i| {
                dns_config.options[i] = try self.allocator.dupe(u8, opt.string);
            }
            
            network_state.dns = dns_config;
        }
        
        // Зберігаємо маршрути
        if (parsed.value.object.get("routes")) |routes| {
            for (routes.array.items) |route| {
                try network_state.routes.append(.{
                    .destination = try self.allocator.dupe(u8, route.object.get("dst").?.string),
                    .gateway = try self.allocator.dupe(u8, route.object.get("gw").?.string),
                    .interface = try self.allocator.dupe(u8, "eth0"),
                });
            }
        }
        
        // Зберігаємо стан
        try self.state_manager.addState(network_state);
        
        return network_state;
    }
    
    /// Видаляє мережевий інтерфейс з контейнера
    pub fn cleanupNetwork(self: *Self, container_id: []const u8, netns: []const u8) !void {
        // Викликаємо Cilium CNI для очищення мережі
        const result = try self.cilium_plugin.delete(container_id, netns);
        if (!result.success) {
            if (result.error) |err| {
                std.log.err(
                    "Failed to cleanup network for container {s}: {s}",
                    .{ container_id, err.msg },
                );
            }
            return NetworkError.CNIError;
        }
        
        // Видаляємо стан
        self.state_manager.removeState(container_id);
    }
    
    /// Перевіряє стан мережі контейнера
    pub fn checkNetwork(self: *Self, container_id: []const u8, netns: []const u8) !void {
        const result = try self.cilium_plugin.check(container_id, netns);
        if (!result.success) {
            if (result.error) |err| {
                std.log.err(
                    "Network check failed for container {s}: {s}",
                    .{ container_id, err.msg },
                );
            }
            return NetworkError.CNIError;
        }
    }
    
    /// Отримує стан мережі контейнера
    pub fn getNetworkState(self: *Self, container_id: []const u8) ?*state.NetworkState {
        return self.state_manager.getState(container_id);
    }
}; 