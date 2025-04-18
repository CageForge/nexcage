const std = @import("std");
const testing = std.testing;
const cni = @import("cni.zig");

test "CNI basic configuration" {
    const allocator = testing.allocator;

    const config = cni.CNIConfig{
        .name = "test-net",
        .type = "bridge",
        .cniVersion = cni.CNI_VERSION,
        .args = null,
    };

    var plugin = try cni.CNIPlugin.init(
        allocator,
        config,
        "/opt/cni/bin",
    );
    defer plugin.deinit();

    try testing.expectEqual(@as([]const u8, "test-net"), plugin.config.name);
    try testing.expectEqual(@as([]const u8, "bridge"), plugin.config.type);
    try testing.expectEqual(@as([]const u8, cni.CNI_VERSION), plugin.config.cniVersion);
}

test "CNI plugin execution" {
    const allocator = testing.allocator;

    // Створюємо тимчасову директорію для тестового плагіна
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Створюємо тестовий плагін
    const plugin_path = try std.fs.path.join(allocator, 
        &[_][]const u8{tmp_dir.dir.path, "bridge"});
    defer allocator.free(plugin_path);

    const plugin_content =
        \\#!/bin/sh
        \\echo '{"cniVersion": "1.0.0", "ips": [{"version": "4", "address": "10.0.0.2/24", "gateway": "10.0.0.1"}]}'
        \\exit 0
    ;

    try tmp_dir.dir.writeFile(plugin_path, plugin_content);
    try std.os.chmodZ(plugin_path, 0o755);

    // Створюємо конфігурацію та плагін
    const config = cni.CNIConfig{
        .name = "test-net",
        .type = "bridge",
        .cniVersion = cni.CNI_VERSION,
        .args = null,
    };

    var plugin = try cni.CNIPlugin.init(
        allocator,
        config,
        tmp_dir.dir.path,
    );
    defer plugin.deinit();

    // Тестуємо ADD операцію
    const result = try plugin.add("test-container", "/proc/1234/ns/net");
    try testing.expectEqual(@as([]const u8, cni.CNI_VERSION), result.cniVersion);
    try testing.expect(result.ips != null);
    try testing.expectEqual(@as(usize, 1), result.ips.?.len);
    try testing.expectEqual(@as([]const u8, "4"), result.ips.?[0].version);
    try testing.expectEqual(@as([]const u8, "10.0.0.2/24"), result.ips.?[0].address);
    try testing.expectEqual(@as([]const u8, "10.0.0.1"), result.ips.?[0].gateway.?);

    // Тестуємо DELETE операцію
    try plugin.delete("test-container", "/proc/1234/ns/net");

    // Тестуємо CHECK операцію
    try plugin.check("test-container", "/proc/1234/ns/net");
}

test "CNI error handling" {
    const allocator = testing.allocator;

    // Створюємо тимчасову директорію
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const config = cni.CNIConfig{
        .name = "test-net",
        .type = "non-existent",
        .cniVersion = cni.CNI_VERSION,
        .args = null,
    };

    var plugin = try cni.CNIPlugin.init(
        allocator,
        config,
        tmp_dir.dir.path,
    );
    defer plugin.deinit();

    // Тестуємо помилку відсутнього плагіна
    try testing.expectError(
        error.PluginNotFound,
        plugin.add("test-container", "/proc/1234/ns/net"),
    );
}; 