const std = @import("std");
const cni = @import("cni.zig");
const plugin = @import("plugin.zig");
const os = std.os;
const net = std.net;
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;

/// Конфігурація Flannel CNI
pub const FlannelConfig = struct {
    /// Базова CNI конфігурація
    cni_config: cni.CNIConfig,
    
    /// Тип бекенду
    backend_type: []const u8,
    
    /// Конфігурація IPAM
    ipam: struct {
        type: []const u8,
        subnet: []const u8,
        routes: []const struct {
            dst: []const u8,
        },
    },
    
    /// Конфігурація делегування
    delegate: struct {
        bridge_name: []const u8,
        mtu: u32,
        hairpin_mode: bool,
    },
    
    const Self = @This();
    
    /// Створює нову конфігурацію
    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        var self = try allocator.create(Self);
        self.cni_config = try cni.CNIConfig.init(allocator, name, "flannel");
        self.backend_type = "vxlan";
        self.ipam = .{
            .type = "host-local",
            .subnet = "10.244.0.0/16",
            .routes = &[_]struct { dst: []const u8 }{
                .{ .dst = "0.0.0.0/0" },
            },
        };
        self.delegate = .{
            .bridge_name = "cni0",
            .mtu = 1450,
            .hairpin_mode = true,
        };
        return self;
    }
    
    /// Серіалізує конфігурацію в JSON
    pub fn toJson(self: *Self, allocator: Allocator) !std.json.Value {
        var root = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try root.Object.put("cniVersion", std.json.Value{ .String = "0.3.1" });
        try root.Object.put("name", std.json.Value{ .String = self.cni_config.name });
        try root.Object.put("type", std.json.Value{ .String = self.cni_config.type });
        try root.Object.put("backend_type", std.json.Value{ .String = self.backend_type });
        
        var ipam = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try ipam.Object.put("type", std.json.Value{ .String = self.ipam.type });
        try ipam.Object.put("subnet", std.json.Value{ .String = self.ipam.subnet });
        
        var routes = std.json.Value{ .Array = std.json.Array.init(allocator) };
        for (self.ipam.routes) |route| {
            var route_obj = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
            try route_obj.Object.put("dst", std.json.Value{ .String = route.dst });
            try routes.Array.append(route_obj);
        }
        try ipam.Object.put("routes", routes);
        try root.Object.put("ipam", ipam);
        
        var delegate = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try delegate.Object.put("bridge_name", std.json.Value{ .String = self.delegate.bridge_name });
        try delegate.Object.put("mtu", std.json.Value{ .Integer = self.delegate.mtu });
        try delegate.Object.put("hairpin_mode", std.json.Value{ .Bool = self.delegate.hairpin_mode });
        try root.Object.put("delegate", delegate);
        
        return root;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.cni_config.deinit();
    }
};

/// Flannel CNI плагін
pub const FlannelPlugin = struct {
    allocator: Allocator,
    config: *FlannelConfig,
    interface: plugin.CNIPluginInterface,
    
    const Self = @This();
    
    /// Створює новий плагін
    pub fn init(allocator: Allocator, config: *FlannelConfig) !*Self {
        var self = try allocator.create(Self);
        self.allocator = allocator;
        self.config = config;
        self.interface = .{
            .plugin_type = .flannel,
            .addFn = addNetwork,
            .deleteFn = deleteNetwork,
            .checkFn = checkNetwork,
            .deinitFn = deinit,
        };
        return self;
    }
    
    /// Додає мережевий інтерфейс
    fn addNetwork(interface: *plugin.CNIPluginInterface, container_id: []const u8, netns: []const u8) cni.CNIResult {
        const self = @fieldParentPtr(Self, "interface", interface);
        
        // Створюємо тимчасовий файл для конфігурації
        const tmp_dir = "/tmp";
        const config_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/flannel-cni-{s}.conf",
            .{ tmp_dir, container_id }
        );
        defer self.allocator.free(config_path);
        
        // Серіалізуємо конфігурацію в JSON
        const config_json = try self.config.toJson(self.allocator);
        defer config_json.deinit();
        
        // Записуємо конфігурацію у файл
        const file = try fs.createFileAbsolute(config_path, .{});
        defer file.close();
        
        try json.stringify(config_json, .{}, file.writer());
        
        // Викликаємо flannel-cni з конфігурацією
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "/opt/cni/bin/flannel",
                "add",
                container_id,
                netns,
                "--config",
                config_path,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        // Видаляємо тимчасовий файл
        try fs.deleteFileAbsolute(config_path);
        
        // Перевіряємо результат виконання
        if (result.term.Exited != 0) {
            return cni.CNIResult{
                .success = false,
                .error = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to add network: {?s}",
                    .{result.stderr}
                ),
            };
        }
        
        return cni.CNIResult{
            .success = true,
            .error = null,
        };
    }
    
    /// Видаляє мережевий інтерфейс
    fn deleteNetwork(interface: *plugin.CNIPluginInterface, container_id: []const u8, netns: []const u8) cni.CNIResult {
        const self = @fieldParentPtr(Self, "interface", interface);
        
        // Викликаємо flannel-cni для видалення інтерфейсу
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "/opt/cni/bin/flannel",
                "del",
                container_id,
                netns,
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        // Перевіряємо результат виконання
        if (result.term.Exited != 0) {
            return .{
                .success = false,
                .error = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to delete network: {?s}",
                    .{result.stderr}
                ),
            };
        }
        
        return .{
            .success = true,
            .error = null,
        };
    }
    
    /// Перевіряє стан мережевого інтерфейсу
    fn checkNetwork(interface: *plugin.CNIPluginInterface, container_id: []const u8, netns: []const u8) cni.CNIResult {
        const self = @fieldParentPtr(Self, "interface", interface);
        
        // Перевіряємо наявність мережевого інтерфейсу в namespace
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "ip",
                "netns",
                "exec",
                netns,
                "ip",
                "link",
                "show",
                "eth0",
            },
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        
        // Якщо інтерфейс не знайдено
        if (result.term.Exited != 0) {
            return .{
                .success = false,
                .error = try std.fmt.allocPrint(
                    self.allocator,
                    "Network interface not found: {?s}",
                    .{result.stderr}
                ),
            };
        }
        
        return .{
            .success = true,
            .error = null,
        };
    }
    
    /// Звільняє ресурси
    fn deinit(interface: *plugin.CNIPluginInterface) void {
        const self = @fieldParentPtr(Self, "interface", interface);
        self.allocator.destroy(self.config);
        self.allocator.destroy(self);
    }
}; 