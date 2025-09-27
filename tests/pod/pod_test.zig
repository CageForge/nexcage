const std = @import("std");
const testing = std.testing;
const Pod = @import("../../src/pod/pod.zig").Pod;
const PodSpec = @import("../../src/pod/pod.zig").PodSpec;
const oci = @import("../../src/oci/spec.zig");
const proxmox = @import("../../src/proxmox/api.zig");

test "pod with pause container" {
    const allocator = testing.allocator;

    // Створюємо специфікацію поду
    var spec = PodSpec{
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
            .uid = "123",
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
        .linux = .{
            .namespaces = &.{
                .{ .type = "network", .path = null },
                .{ .type = "pid", .path = null },
            },
        },
        .containers = &.{
            .{
                .ociVersion = "1.0.2",
                .process = .{
                    .terminal = false,
                    .user = .{ .uid = 0, .gid = 0 },
                    .args = &.{ "/bin/sleep", "infinity" },
                    .env = &.{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
                    .cwd = "/",
                },
                .root = .{
                    .path = "/var/lib/containers/test-pod/rootfs",
                    .readonly = false,
                },
                .hostname = "test-pod",
                .mounts = &.{},
                .linux = .{
                    .namespaces = &.{
                        .{ .type = "network", .path = null },
                        .{ .type = "pid", .path = null },
                    },
                },
            },
        },
    };

    // Створюємо конфігурацію Proxmox
    const proxmox_config = proxmox.ProxmoxConfig{
        .host = "localhost",
        .port = 8006,
        .token = "test-token",
        .verify_ssl = false,
    };

    // Створюємо под
    const pod = try Pod.init(allocator, spec, proxmox_config);
    defer pod.deinit();

    // Тестуємо створення
    try pod.create();
    try testing.expect(pod.pause_container != null);
    try testing.expectEqualStrings("test-pod-pause", pod.pause_container.?.config.id);

    // Тестуємо запуск
    try pod.start();
    try testing.expectEqual(oci.ContainerState.Status.running, pod.pause_container.?.state.status);

    // Тестуємо зупинку
    try pod.stop();
    try testing.expectEqual(oci.ContainerState.Status.stopped, pod.pause_container.?.state.status);

    // Тестуємо видалення
    try pod.delete();
    try testing.expect(pod.pause_container == null);
}
