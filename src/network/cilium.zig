const std = @import("std");
const cni = @import("cni.zig");
const plugin = @import("plugin.zig");
const os = std.os;
const net = std.net;
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;

/// Конфігурація Cilium CNI
pub const CiliumConfig = struct {
    /// Базова CNI конфігурація
    cni_config: cni.CNIConfig,
    
    /// Режим роботи Cilium
    mode: []const u8,
    
    /// Конфігурація IPAM
    ipam: struct {
        type: []const u8,
        subnet: []const u8,
        routes: []const struct {
            dst: []const u8,
        },
    },
    
    /// Конфігурація Kubernetes
    kubernetes: struct {
        kubeconfig: []const u8,
    },
    
    /// Конфігурація мережевої політики
    policy: struct {
        type: []const u8,
        enabled: bool,
    },
    
    const Self = @This();
    
    /// Створює нову конфігурацію
    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        var self = try allocator.create(Self);
        self.cni_config = try cni.CNIConfig.init(allocator, name, "cilium");
        self.mode = "tunnel";
        self.ipam = .{
            .type = "cilium-ipam",
            .subnet = "10.0.0.0/8",
            .routes = &[_]struct { dst: []const u8 }{
                .{ .dst = "0.0.0.0/0" },
            },
        };
        self.kubernetes = .{
            .kubeconfig = "/etc/kubernetes/kubeconfig",
        };
        self.policy = .{
            .type = "k8s",
            .enabled = true,
        };
        return self;
    }
    
    /// Серіалізує конфігурацію в JSON
    pub fn toJson(self: *Self, allocator: Allocator) !std.json.Value {
        var root = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try root.Object.put("cniVersion", std.json.Value{ .String = "0.3.1" });
        try root.Object.put("name", std.json.Value{ .String = self.cni_config.name });
        try root.Object.put("type", std.json.Value{ .String = self.cni_config.type });
        try root.Object.put("mode", std.json.Value{ .String = self.mode });
        
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
        
        var kubernetes = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try kubernetes.Object.put("kubeconfig", std.json.Value{ .String = self.kubernetes.kubeconfig });
        try root.Object.put("kubernetes", kubernetes);
        
        var policy = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try policy.Object.put("type", std.json.Value{ .String = self.policy.type });
        try policy.Object.put("enabled", std.json.Value{ .Bool = self.policy.enabled });
        try root.Object.put("policy", policy);
        
        return root;
    }
};

/// Cilium CNI плагін
pub const CiliumPlugin = struct {
    allocator: Allocator,
    config: *CiliumConfig,
    interface: plugin.CNIPluginInterface,
    
    const Self = @This();
    
    /// Створює новий плагін
    pub fn init(allocator: Allocator, config: *CiliumConfig) !*Self {
        var self = try allocator.create(Self);
        self.allocator = allocator;
        self.config = config;
        self.interface = .{
            .plugin_type = .cilium,
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
            "{s}/cilium-cni-{s}.conf",
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
        
        // Викликаємо cilium-cni з конфігурацією
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "/opt/cni/bin/cilium-cni",
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
        
        // Викликаємо cilium-cni для видалення інтерфейсу
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "/opt/cni/bin/cilium-cni",
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
            return cni.CNIResult{
                .success = false,
                .error = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to delete network: {?s}",
                    .{result.stderr}
                ),
            };
        }
        
        return cni.CNIResult{
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
                "cilium0",
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