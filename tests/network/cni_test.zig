const std = @import("std");
const testing = std.testing;
const network = @import("network");
const proxmox = @import("proxmox");

test "CNI configuration for LXC container" {
    const allocator = testing.allocator;

    // Створюємо тестові анотації
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    try annotations.put("k8s.v1.cni.cncf.io/networks", "default");
    try annotations.put("k8s.v1.cni.cncf.io/network-status", "");

    // Створюємо тестову конфігурацію LXC
    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    try config.put("vmid", "100");
    try config.put("hostname", "test-container");

    // Тестуємо налаштування мережі
    try proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations);

    // Перевіряємо результати
    const net_config = config.get("net0") orelse {
        try testing.expect(false);
        return;
    };

    // Базові перевірки конфігурації мережі
    try testing.expect(std.mem.indexOf(u8, net_config, "name=eth0") != null);
    try testing.expect(std.mem.indexOf(u8, net_config, "type=veth") != null);
    try testing.expect(std.mem.indexOf(u8, net_config, "bridge=") != null);

    // Перевіряємо наявність DNS налаштувань
    if (config.get("nameserver")) |ns| {
        try testing.expect(ns.len > 0);
    }

    if (config.get("searchdomain")) |sd| {
        try testing.expect(sd.len > 0);
    }
}

test "CNI error handling" {
    const allocator = testing.allocator;

    // Створюємо неправильні анотації
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    // Очікуємо помилку при відсутності необхідних анотацій
    try testing.expectError(
        network.NetworkError.CNIConfigError,
        proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations)
    );
}

test "CNI cleanup on error" {
    const allocator = testing.allocator;

    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();
    try annotations.put("k8s.v1.cni.cncf.io/networks", "invalid-network");

    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    try config.put("vmid", "100");

    // Очікуємо, що при помилці всі ресурси будуть правильно звільнені
    _ = proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations) catch |err| {
        try testing.expect(err == network.NetworkError.CNIError);
        return;
    };

    try testing.expect(false);
} 