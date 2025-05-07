const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const logger = std.log.scoped(.proxmox_client_test);

const ProxmoxClient = @import("../../src/proxmox/client.zig").ProxmoxClient;

// Функція для перевірки витоку пам'яті
fn checkMemoryLeaks(allocator: *std.mem.Allocator) !void {
    const info = try allocator.detectLeaks();
    if (info.leak_count > 0) {
        logger.err("Memory leak detected: {d} allocations not freed", .{info.leak_count});
        return error.MemoryLeak;
    }
}

test "Proxmox client memory management" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var client = try ProxmoxClient.init(allocator, "https://proxmox.example.com", "root@pam", "password");
    defer client.deinit();

    // Перевіряємо підключення
    try testing.expect(try client.isConnected());

    // Перевіряємо отримання версії
    const version = try client.getVersion();
    defer allocator.free(version);
    try testing.expect(version.len > 0);
}

test "Proxmox client node operations" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var client = try ProxmoxClient.init(allocator, "https://proxmox.example.com", "root@pam", "password");
    defer client.deinit();

    // Отримуємо список вузлів
    const nodes = try client.getNodes();
    defer {
        for (nodes) |node| {
            allocator.free(node);
        }
        allocator.free(nodes);
    }

    // Перевіряємо чи є хоча б один вузол
    try testing.expect(nodes.len > 0);

    // Перевіряємо статус першого вузла
    const node_status = try client.getNodeStatus(nodes[0]);
    defer allocator.free(node_status);
    try testing.expect(node_status.len > 0);
}

test "Proxmox client container operations" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var client = try ProxmoxClient.init(allocator, "https://proxmox.example.com", "root@pam", "password");
    defer client.deinit();

    const node = "pve";
    const vmid = 100;

    // Створюємо контейнер
    try client.createContainer(node, vmid, "test-container", 512, 1024);

    // Перевіряємо чи контейнер створений
    try testing.expect(try client.containerExists(node, vmid));

    // Отримуємо статус контейнера
    const status = try client.getContainerStatus(node, vmid);
    defer allocator.free(status);
    try testing.expect(status.len > 0);

    // Видаляємо контейнер
    try client.deleteContainer(node, vmid);

    // Перевіряємо чи контейнер видалений
    try testing.expect(!try client.containerExists(node, vmid));
} 