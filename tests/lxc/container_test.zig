const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const logger = std.log.scoped(.lxc_container_test);

const LXCManager = @import("../../src/lxc/container.zig").LXCManager;

// Функція для перевірки витоку пам'яті
fn checkMemoryLeaks(allocator: *std.mem.Allocator) !void {
    const info = try allocator.detectLeaks();
    if (info.leak_count > 0) {
        logger.err("Memory leak detected: {d} allocations not freed", .{info.leak_count});
        return error.MemoryLeak;
    }
}

test "LXC container memory management" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try LXCManager.init(allocator);
    defer manager.deinit();

    const container_name = "test-container";
    const config_path = "/tmp/lxc-test/config";

    // Створюємо темпову директорію для конфігурації
    try fs.cwd().makePath("/tmp/lxc-test");
    defer fs.cwd().deleteTree("/tmp/lxc-test") catch {};

    // Створюємо базову конфігурацію
    const config_content = 
        \\lxc.uts.name = test-container
        \\lxc.rootfs.path = /tmp/lxc-test/rootfs
        \\lxc.net.0.type = empty
    ;
    try fs.cwd().writeFile("/tmp/lxc-test/config", config_content);

    // Створюємо контейнер
    try manager.createContainer(container_name, config_path);

    // Перевіряємо чи контейнер створений
    try testing.expect(try manager.containerExists(container_name));

    // Видаляємо контейнер
    try manager.destroyContainer(container_name);

    // Перевіряємо чи контейнер видалений
    try testing.expect(!try manager.containerExists(container_name));
}

test "LXC container state management" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try LXCManager.init(allocator);
    defer manager.deinit();

    const container_name = "test-container";
    const config_path = "/tmp/lxc-test/config";

    // Створюємо темпову директорію для конфігурації
    try fs.cwd().makePath("/tmp/lxc-test");
    defer fs.cwd().deleteTree("/tmp/lxc-test") catch {};

    // Створюємо базову конфігурацію
    const config_content = 
        \\lxc.uts.name = test-container
        \\lxc.rootfs.path = /tmp/lxc-test/rootfs
        \\lxc.net.0.type = empty
    ;
    try fs.cwd().writeFile("/tmp/lxc-test/config", config_content);

    // Створюємо контейнер
    try manager.createContainer(container_name, config_path);
    defer manager.destroyContainer(container_name);

    // Перевіряємо початковий стан
    try testing.expectEqual(@as(u8, 0), try manager.getContainerState(container_name));

    // Запускаємо контейнер
    try manager.startContainer(container_name);
    try testing.expectEqual(@as(u8, 1), try manager.getContainerState(container_name));

    // Зупиняємо контейнер
    try manager.stopContainer(container_name);
    try testing.expectEqual(@as(u8, 0), try manager.getContainerState(container_name));
}

test "LXC container configuration" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try LXCManager.init(allocator);
    defer manager.deinit();

    const container_name = "test-container";
    const config_path = "/tmp/lxc-test/config";

    // Створюємо темпову директорію для конфігурації
    try fs.cwd().makePath("/tmp/lxc-test");
    defer fs.cwd().deleteTree("/tmp/lxc-test") catch {};

    // Створюємо базову конфігурацію
    const config_content = 
        \\lxc.uts.name = test-container
        \\lxc.rootfs.path = /tmp/lxc-test/rootfs
        \\lxc.net.0.type = empty
    ;
    try fs.cwd().writeFile("/tmp/lxc-test/config", config_content);

    // Створюємо контейнер
    try manager.createContainer(container_name, config_path);
    defer manager.destroyContainer(container_name);

    // Встановлюємо конфігурацію
    try manager.setConfigItem(container_name, "lxc.cap.drop", "sys_admin");
    try manager.setConfigItem(container_name, "lxc.cgroup.cpu.shares", "512");

    // Перевіряємо конфігурацію
    const cap_drop = try manager.getConfigItem(container_name, "lxc.cap.drop");
    const cpu_shares = try manager.getConfigItem(container_name, "lxc.cgroup.cpu.shares");

    try testing.expectEqualStrings("sys_admin", cap_drop);
    try testing.expectEqualStrings("512", cpu_shares);

    // Звільняємо пам'ять
    allocator.free(cap_drop);
    allocator.free(cpu_shares);
} 