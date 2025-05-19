const std = @import("std");
const testing = std.testing;
const network = @import("network");
const cilium = network.cilium;
const flannel = network.flannel;
const cni = network.cni;
const plugin = network.plugin;

/// Тести для Cilium CNI плагіна
const CiliumTests = struct {
    /// Тестування ініціалізації конфігурації
    fn testConfigInit(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try cilium.CiliumConfig.init(allocator, "test-cilium");
        defer config.deinit();
        
        // Перевіряємо базові поля
        try testing.expectEqualStrings("test-cilium", config.cni_config.name);
        try testing.expectEqualStrings("cilium", config.cni_config.type);
        try testing.expectEqualStrings("tunnel", config.mode);
        
        // Перевіряємо IPAM конфігурацію
        try testing.expectEqualStrings("cilium-ipam", config.ipam.type);
        try testing.expectEqualStrings("10.0.0.0/8", config.ipam.subnet);
        try testing.expectEqual(@as(usize, 1), config.ipam.routes.len);
        try testing.expectEqualStrings("0.0.0.0/0", config.ipam.routes[0].dst);
        
        // Перевіряємо Kubernetes конфігурацію
        try testing.expectEqualStrings("/etc/kubernetes/kubeconfig", config.kubernetes.kubeconfig);
        
        // Перевіряємо конфігурацію політик
        try testing.expectEqualStrings("k8s", config.policy.type);
        try testing.expect(config.policy.enabled);
    }

    /// Тестування серіалізації конфігурації в JSON
    fn testConfigJson(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try cilium.CiliumConfig.init(allocator, "test-cilium");
        defer config.deinit();
        
        // Серіалізуємо в JSON
        const json_value = try config.toJson(allocator);
        defer json_value.deinit();
        
        // Перевіряємо основні поля
        try testing.expectEqualStrings("0.3.1", json_value.Object.get("cniVersion").?.String);
        try testing.expectEqualStrings("test-cilium", json_value.Object.get("name").?.String);
        try testing.expectEqualStrings("cilium", json_value.Object.get("type").?.String);
        try testing.expectEqualStrings("tunnel", json_value.Object.get("mode").?.String);
        
        // Перевіряємо IPAM
        const ipam = json_value.Object.get("ipam").?.Object;
        try testing.expectEqualStrings("cilium-ipam", ipam.get("type").?.String);
        try testing.expectEqualStrings("10.0.0.0/8", ipam.get("subnet").?.String);
        
        const routes = ipam.get("routes").?.Array;
        try testing.expectEqual(@as(usize, 1), routes.items.len);
        try testing.expectEqualStrings("0.0.0.0/0", routes.items[0].Object.get("dst").?.String);
        
        // Перевіряємо Kubernetes конфігурацію
        const kubernetes = json_value.Object.get("kubernetes").?.Object;
        try testing.expectEqualStrings("/etc/kubernetes/kubeconfig", kubernetes.get("kubeconfig").?.String);
        
        // Перевіряємо політики
        const policy = json_value.Object.get("policy").?.Object;
        try testing.expectEqualStrings("k8s", policy.get("type").?.String);
        try testing.expect(policy.get("enabled").?.Bool);
    }

    /// Тестування ініціалізації плагіна
    fn testPluginInit(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try cilium.CiliumConfig.init(allocator, "test-cilium");
        defer config.deinit();
        
        // Створюємо плагін
        const cilium_plugin = try cilium.CiliumPlugin.init(allocator, config);
        defer cilium_plugin.deinit();
        
        // Перевіряємо тип плагіна
        try testing.expectEqual(plugin.CNIPluginType.cilium, cilium_plugin.interface.plugin_type);
    }

    /// Тестування мережевих операцій
    fn testNetworkOperations(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію та плагін
        const config = try cilium.CiliumConfig.init(allocator, "test-cilium");
        const cilium_plugin = try cilium.CiliumPlugin.init(allocator, config);
        defer cilium_plugin.deinit();
        
        // Тестові дані
        const container_id = "test-container";
        const netns = "/var/run/netns/test";
        
        // Створюємо тестовий network namespace
        _ = try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "ip",
                "netns",
                "add",
                "test",
            },
        });
        defer {
            _ = std.ChildProcess.exec(.{
                .allocator = allocator,
                .argv = &[_][]const u8{
                    "ip",
                    "netns",
                    "del",
                    "test",
                },
            }) catch {};
        }
        
        // Тестуємо додавання мережі
        {
            const result = cilium_plugin.interface.add(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
        
        // Тестуємо перевірку стану
        {
            const result = cilium_plugin.interface.check(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
        
        // Тестуємо видалення мережі
        {
            const result = cilium_plugin.interface.delete(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
    }

    /// Тестування обробки помилок
    fn testErrorHandling(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію та плагін
        const config = try cilium.CiliumConfig.init(allocator, "test-cilium");
        const cilium_plugin = try cilium.CiliumPlugin.init(allocator, config);
        defer cilium_plugin.deinit();
        
        // Тестуємо з неіснуючим network namespace
        const result = cilium_plugin.interface.check("test-container", "/var/run/netns/nonexistent");
        try testing.expect(!result.success);
        try testing.expectEqual(@as(?[]const u8, null), result.error);
    }
};

/// Тести для Flannel CNI плагіна
const FlannelTests = struct {
    /// Тестування ініціалізації конфігурації
    fn testConfigInit(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try flannel.FlannelConfig.init(allocator, "test-flannel");
        defer config.deinit();
        
        // Перевіряємо базові поля
        try testing.expectEqualStrings("test-flannel", config.cni_config.name);
        try testing.expectEqualStrings("flannel", config.cni_config.type);
        try testing.expectEqualStrings("vxlan", config.backend_type);
        
        // Перевіряємо IPAM конфігурацію
        try testing.expectEqualStrings("host-local", config.ipam.type);
        try testing.expectEqualStrings("10.244.0.0/16", config.ipam.subnet);
        try testing.expectEqual(@as(usize, 1), config.ipam.routes.len);
        try testing.expectEqualStrings("0.0.0.0/0", config.ipam.routes[0].dst);
        
        // Перевіряємо конфігурацію делегування
        try testing.expectEqualStrings("cni0", config.delegate.bridge_name);
        try testing.expectEqual(@as(u32, 1450), config.delegate.mtu);
        try testing.expect(config.delegate.hairpin_mode);
    }

    /// Тестування серіалізації конфігурації в JSON
    fn testConfigJson(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try flannel.FlannelConfig.init(allocator, "test-flannel");
        defer config.deinit();
        
        // Серіалізуємо в JSON
        const json_value = try config.toJson(allocator);
        defer json_value.deinit();
        
        // Перевіряємо основні поля
        try testing.expectEqualStrings("0.3.1", json_value.Object.get("cniVersion").?.String);
        try testing.expectEqualStrings("test-flannel", json_value.Object.get("name").?.String);
        try testing.expectEqualStrings("flannel", json_value.Object.get("type").?.String);
        try testing.expectEqualStrings("vxlan", json_value.Object.get("backend_type").?.String);
        
        // Перевіряємо IPAM
        const ipam = json_value.Object.get("ipam").?.Object;
        try testing.expectEqualStrings("host-local", ipam.get("type").?.String);
        try testing.expectEqualStrings("10.244.0.0/16", ipam.get("subnet").?.String);
        
        const routes = ipam.get("routes").?.Array;
        try testing.expectEqual(@as(usize, 1), routes.items.len);
        try testing.expectEqualStrings("0.0.0.0/0", routes.items[0].Object.get("dst").?.String);
        
        // Перевіряємо делегування
        const delegate = json_value.Object.get("delegate").?.Object;
        try testing.expectEqualStrings("cni0", delegate.get("bridge_name").?.String);
        try testing.expectEqual(@as(i64, 1450), delegate.get("mtu").?.Integer);
        try testing.expect(delegate.get("hairpin_mode").?.Bool);
    }

    /// Тестування ініціалізації плагіна
    fn testPluginInit(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію
        const config = try flannel.FlannelConfig.init(allocator, "test-flannel");
        defer config.deinit();
        
        // Створюємо плагін
        const flannel_plugin = try flannel.FlannelPlugin.init(allocator, config);
        defer flannel_plugin.deinit();
        
        // Перевіряємо тип плагіна
        try testing.expectEqual(plugin.CNIPluginType.flannel, flannel_plugin.interface.plugin_type);
    }

    /// Тестування мережевих операцій
    fn testNetworkOperations(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію та плагін
        const config = try flannel.FlannelConfig.init(allocator, "test-flannel");
        const flannel_plugin = try flannel.FlannelPlugin.init(allocator, config);
        defer flannel_plugin.deinit();
        
        // Тестові дані
        const container_id = "test-container";
        const netns = "/var/run/netns/test";
        
        // Створюємо тестовий network namespace
        _ = try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &[_][]const u8{
                "ip",
                "netns",
                "add",
                "test",
            },
        });
        defer {
            _ = std.ChildProcess.exec(.{
                .allocator = allocator,
                .argv = &[_][]const u8{
                    "ip",
                    "netns",
                    "del",
                    "test",
                },
            }) catch {};
        }
        
        // Тестуємо додавання мережі
        {
            const result = flannel_plugin.interface.add(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
        
        // Тестуємо перевірку стану
        {
            const result = flannel_plugin.interface.check(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
        
        // Тестуємо видалення мережі
        {
            const result = flannel_plugin.interface.delete(container_id, netns);
            try testing.expect(result.success);
            try testing.expect(result.error == null);
        }
    }

    /// Тестування обробки помилок
    fn testErrorHandling(allocator: std.mem.Allocator) !void {
        // Створюємо конфігурацію та плагін
        const config = try flannel.FlannelConfig.init(allocator, "test-flannel");
        const flannel_plugin = try flannel.FlannelPlugin.init(allocator, config);
        defer flannel_plugin.deinit();
        
        // Тестуємо з неіснуючим network namespace
        const result = flannel_plugin.interface.check("test-container", "/var/run/netns/nonexistent");
        try testing.expect(!result.success);
        try testing.expectEqual(@as(?[]const u8, null), result.error);
    }
};

test "Cilium CNI - Config initialization" {
    try CiliumTests.testConfigInit(testing.allocator);
}

test "Cilium CNI - Config JSON serialization" {
    try CiliumTests.testConfigJson(testing.allocator);
}

test "Cilium CNI - Plugin initialization" {
    try CiliumTests.testPluginInit(testing.allocator);
}

test "Cilium CNI - Network operations" {
    try CiliumTests.testNetworkOperations(testing.allocator);
}

test "Cilium CNI - Error handling" {
    try CiliumTests.testErrorHandling(testing.allocator);
}

test "Flannel CNI - Config initialization" {
    try FlannelTests.testConfigInit(testing.allocator);
}

test "Flannel CNI - Config JSON serialization" {
    try FlannelTests.testConfigJson(testing.allocator);
}

test "Flannel CNI - Plugin initialization" {
    try FlannelTests.testPluginInit(testing.allocator);
}

test "Flannel CNI - Network operations" {
    try FlannelTests.testNetworkOperations(testing.allocator);
}

test "Flannel CNI - Error handling" {
    try FlannelTests.testErrorHandling(testing.allocator);
} 