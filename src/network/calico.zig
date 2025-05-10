const std = @import("std");
const cni = @import("cni.zig");
const plugin = @import("plugin.zig");
const Allocator = std.mem.Allocator;

/// Конфігурація Calico CNI
pub const CalicoConfig = struct {
    /// Базова CNI конфігурація
    cni_config: cni.CNIConfig,
    
    /// Тип сховища даних
    datastore_type: []const u8,
    
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
        node_name: []const u8,
    },
    
    const Self = @This();
    
    /// Створює нову конфігурацію
    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        var self = try allocator.create(Self);
        self.cni_config = try cni.CNIConfig.init(allocator, name, "calico");
        self.datastore_type = "kubernetes";
        self.ipam = .{
            .type = "calico-ipam",
            .subnet = "10.244.0.0/16",
            .routes = &[_]struct { dst: []const u8 }{
                .{ .dst = "0.0.0.0/0" },
            },
        };
        self.kubernetes = .{
            .kubeconfig = "/etc/kubernetes/kubeconfig",
            .node_name = try std.os.gethostname(allocator),
        };
        return self;
    }
    
    /// Серіалізує конфігурацію в JSON
    pub fn toJson(self: *Self, allocator: Allocator) !std.json.Value {
        var root = std.json.Value{ .Object = std.json.ObjectMap.init(allocator) };
        try root.Object.put("cniVersion", std.json.Value{ .String = "0.3.1" });
        try root.Object.put("name", std.json.Value{ .String = self.cni_config.name });
        try root.Object.put("type", std.json.Value{ .String = self.cni_config.type });
        try root.Object.put("datastore_type", std.json.Value{ .String = self.datastore_type });
        
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
        try kubernetes.Object.put("node_name", std.json.Value{ .String = self.kubernetes.node_name });
        try root.Object.put("kubernetes", kubernetes);
        
        return root;
    }
};

/// Calico CNI плагін
pub const CalicoPlugin = struct {
    allocator: Allocator,
    config: *CalicoConfig,
    interface: plugin.CNIPluginInterface,
    
    const Self = @This();
    
    /// Створює новий плагін
    pub fn init(allocator: Allocator, config: *CalicoConfig) !*Self {
        var self = try allocator.create(Self);
        self.allocator = allocator;
        self.config = config;
        self.interface = .{
            .plugin_type = .calico,
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
        // TODO: реалізувати додавання мережевого інтерфейсу
        return cni.CNIResult{
            .success = true,
            .error = null,
        };
    }
    
    /// Видаляє мережевий інтерфейс
    fn deleteNetwork(interface: *plugin.CNIPluginInterface, container_id: []const u8, netns: []const u8) cni.CNIResult {
        const self = @fieldParentPtr(Self, "interface", interface);
        // TODO: реалізувати видалення мережевого інтерфейсу
        return cni.CNIResult{
            .success = true,
            .error = null,
        };
    }
    
    /// Перевіряє стан мережевого інтерфейсу
    fn checkNetwork(interface: *plugin.CNIPluginInterface, container_id: []const u8, netns: []const u8) cni.CNIResult {
        const self = @fieldParentPtr(Self, "interface", interface);
        // TODO: реалізувати перевірку стану мережевого інтерфейсу
        return cni.CNIResult{
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