const std = @import("std");
const testing = std.testing;
const PauseContainer = @import("../../src/pause/pause.zig").PauseContainer;
const ContainerConfig = @import("../../src/types.zig").ContainerConfig;
const ContainerState = @import("../../src/types.zig").ContainerState;

test "pause container initialization" {
    const allocator = testing.allocator;
    const config = ContainerConfig{
        .id = "test-pause",
        .bundle = "/var/lib/containers/test-pause",
        .annotations = &.{},
    };

    const container = try PauseContainer.init(allocator, config);
    defer container.deinit();

    try testing.expectEqualStrings("test-pause", container.config.id);
    try testing.expectEqualStrings("/var/lib/containers/test-pause", container.config.bundle);
    try testing.expectEqual(ContainerState.Status.created, container.state.status);
}

test "pause container rootfs preparation" {
    const allocator = testing.allocator;
    const config = ContainerConfig{
        .id = "test-pause",
        .bundle = "/var/lib/containers/test-pause",
        .annotations = &.{},
    };

    const container = try PauseContainer.init(allocator, config);
    defer container.deinit();

    // Тестуємо підготовку rootfs
    try container.prepareRootfs();

    // Перевіряємо чи створено ZFS dataset
    const dataset_name = try std.fmt.allocPrint(allocator, "rpool/containers/{s}", .{config.id});
    defer allocator.free(dataset_name);

    try testing.expect(container.zfs_manager.datasetExists(dataset_name));

    // Перевіряємо чи існує rootfs
    try testing.expect(std.fs.accessAbsolute(config.bundle, .{}));
}

test "pause container start and stop" {
    const allocator = testing.allocator;
    const config = ContainerConfig{
        .id = "test-pause",
        .bundle = "/var/lib/containers/test-pause",
        .annotations = &.{},
    };

    const container = try PauseContainer.init(allocator, config);
    defer container.deinit();

    // Тестуємо запуск
    try container.start();
    try testing.expectEqual(ContainerState.Status.running, container.state.status);

    // Перевіряємо чи створено конфігурацію
    const config_path = try std.fmt.allocPrint(allocator, "{s}/config.json", .{config.bundle});
    defer allocator.free(config_path);

    try testing.expect(std.fs.accessAbsolute(config_path, .{}));

    // Тестуємо зупинку
    try container.stop();
    try testing.expectEqual(ContainerState.Status.stopped, container.state.status);

    // Перевіряємо чи видалено ZFS dataset
    const dataset_name = try std.fmt.allocPrint(allocator, "rpool/containers/{s}", .{config.id});
    defer allocator.free(dataset_name);

    try testing.expect(!container.zfs_manager.datasetExists(dataset_name));
}

test "pause container state management" {
    const allocator = testing.allocator;
    const config = ContainerConfig{
        .id = "test-pause",
        .bundle = "/var/lib/containers/test-pause",
        .annotations = &.{},
    };

    const container = try PauseContainer.init(allocator, config);
    defer container.deinit();

    const state = container.getState();
    try testing.expectEqual(ContainerState.Status.created, state.status);
    try testing.expectEqualStrings("/var/lib/containers/test-pause", state.bundle);
} 