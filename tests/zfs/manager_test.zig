const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const logger = std.log.scoped(.zfs_manager_test);

const ZFSManager = @import("../../src/zfs/manager.zig").ZFSManager;

// Функція для перевірки витоку пам'яті
fn checkMemoryLeaks(allocator: *std.mem.Allocator) !void {
    const info = try allocator.detectLeaks();
    if (info.leak_count > 0) {
        logger.err("Memory leak detected: {d} allocations not freed", .{info.leak_count});
        return error.MemoryLeak;
    }
}

test "ZFS manager memory management" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    // Створюємо менеджер
    var manager = try ZFSManager.init(allocator);
    defer manager.deinit();

    // Створюємо тестовий dataset
    const dataset_name = "tank/test-dataset";
    try manager.createDataset(dataset_name);

    // Перевіряємо чи dataset створений
    try testing.expect(try manager.datasetExists(dataset_name));

    // Видаляємо dataset
    try manager.destroyDataset(dataset_name);

    // Перевіряємо чи dataset видалений
    try testing.expect(!try manager.datasetExists(dataset_name));
}

test "ZFS manager multiple datasets" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try ZFSManager.init(allocator);
    defer manager.deinit();

    // Створюємо кілька datasets
    const datasets = [_][]const u8{
        "tank/test-dataset-1",
        "tank/test-dataset-2",
        "tank/test-dataset-3",
    };

    // Створюємо datasets
    for (datasets) |dataset| {
        try manager.createDataset(dataset);
        try testing.expect(try manager.datasetExists(dataset));
    }

    // Видаляємо datasets
    for (datasets) |dataset| {
        try manager.destroyDataset(dataset);
        try testing.expect(!try manager.datasetExists(dataset));
    }
}

test "ZFS manager properties" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try ZFSManager.init(allocator);
    defer manager.deinit();

    const dataset_name = "tank/test-dataset";
    try manager.createDataset(dataset_name);
    defer manager.destroyDataset(dataset_name);

    // Встановлюємо властивості
    try manager.setProperty(dataset_name, "compression", "lz4");
    try manager.setProperty(dataset_name, "atime", "off");

    // Перевіряємо властивості
    const compression = try manager.getProperty(dataset_name, "compression");
    const atime = try manager.getProperty(dataset_name, "atime");

    try testing.expectEqualStrings("lz4", compression);
    try testing.expectEqualStrings("off", atime);

    // Звільняємо пам'ять
    allocator.free(compression);
    allocator.free(atime);
} 