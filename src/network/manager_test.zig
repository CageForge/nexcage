const std = @import("std");
const testing = std.testing;
const types = @import("../types/pod.zig");
const network = @import("manager.zig");

test "NetworkManager basic operations" {
    const allocator = testing.allocator;

    // Створюємо тимчасову директорію для CNI плагінів
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Створюємо тестовий CNI плагін
    const plugin_content =
        \\#!/bin/sh
        \\echo '{"cniVersion": "1.0.0", "ips": [{"version": "4", "address": "10.0.0.2/24", "gateway": "10.0.0.1"}]}'
        \\exit 0
    ;

    try tmp_dir.dir.writeFile("bridge", plugin_content);
    try std.os.chmodZ(try std.fs.path.join(allocator, &[_][]const u8{tmp_dir.dir.path, "bridge"}), 0o755);

    // Ініціалізуємо NetworkManager
    var manager = try network.NetworkManager.init(allocator, tmp_dir.dir.path);
    defer manager.deinit();

    // Створюємо тестову конфігурацію мережі
    const net_config = types.NetworkConfig{
        .mode = .bridge,
        .dns = .{
            .servers = &[_][]const u8{"8.8.8.8", "1.1.1.1"},
            .search = &[_][]const u8{"example.com"},
            .options = &[_][]const u8{"ndots:5"},
        },
        .port_mappings = &[_]types.PortMapping{
            .{
                .protocol = .tcp,
                .container_port = 80,
                .host_port = 8080,
                .host_ip = null,
            },
        },
    };

    // Тестуємо створення мережі
    try manager.createNetwork("test-pod", net_config);

    // Перевіряємо що мережа створена
    try testing.expect(manager.networks.get("test-pod") != null);

    // Тестуємо запуск мережі
    try manager.startNetwork("test-pod");

    // Перевіряємо статус
    const status = try manager.getNetworkStatus("test-pod");
    try testing.expectEqual(network.NetworkStatus.Running, status);

    // Тестуємо зупинку мережі
    try manager.stopNetwork("test-pod");
    const stopped_status = try manager.getNetworkStatus("test-pod");
    try testing.expectEqual(network.NetworkStatus.Stopped, stopped_status);

    // Тестуємо видалення мережі
    try manager.deleteNetwork("test-pod");
    try testing.expect(manager.networks.get("test-pod") == null);
}

test "NetworkManager error handling" {
    const allocator = testing.allocator;

    // Створюємо тимчасову директорію
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Ініціалізуємо NetworkManager
    var manager = try network.NetworkManager.init(allocator, tmp_dir.dir.path);
    defer manager.deinit();

    // Тестуємо помилку при спробі отримати неіснуючу мережу
    try testing.expectError(
        error.NetworkNotFound,
        manager.getNetworkStatus("non-existent"),
    );

    // Створюємо тестову конфігурацію
    const net_config = types.NetworkConfig{
        .mode = .bridge,
        .dns = .{
            .servers = &[_][]const u8{},
            .search = &[_][]const u8{},
            .options = &[_][]const u8{},
        },
        .port_mappings = &[_]types.PortMapping{},
    };

    // Тестуємо створення мережі
    try manager.createNetwork("test-pod", net_config);

    // Тестуємо помилку при повторному створенні
    try testing.expectError(
        error.NetworkAlreadyExists,
        manager.createNetwork("test-pod", net_config),
    );

    // Тестуємо помилку при спробі зупинити незапущену мережу
    try testing.expectError(
        error.InvalidState,
        manager.stopNetwork("test-pod"),
    );
}; 