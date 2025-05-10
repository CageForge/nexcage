const std = @import("std");
const testing = std.testing;
const storage = @import("../src/oci/storage.zig");

test "StorageManager - init/deinit" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();
}

test "StorageManager - add and get storage" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();

    const config = storage.StorageConfig{
        .id = "local-1",
        .storage_type = storage.StorageType.local,
        .path = "/var/lib/lxc",
        .default_size = 10,
    };

    try manager.addStorage(config);

    const retrieved = manager.getStorage("local-1").?;
    try testing.expectEqualStrings("local-1", retrieved.id);
    try testing.expectEqual(storage.StorageType.local, retrieved.storage_type);
    try testing.expectEqualStrings("/var/lib/lxc", retrieved.path);
    try testing.expectEqual(@as(u32, 10), retrieved.default_size);
}

test "StorageManager - add and get image" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();

    const config = storage.ImageConfig{
        .id = "ubuntu-22.04",
        .name = "Ubuntu 22.04",
        .image_type = storage.ImageType.base,
        .version = "22.04",
        .path = "/var/lib/lxc/images/ubuntu-22.04.tar.gz",
        .size = 1024 * 1024 * 100, // 100MB
        .hash = "sha256:1234567890",
    };

    try manager.addImage(config);

    const retrieved = manager.getImage("ubuntu-22.04").?;
    try testing.expectEqualStrings("ubuntu-22.04", retrieved.id);
    try testing.expectEqualStrings("Ubuntu 22.04", retrieved.name);
    try testing.expectEqual(storage.ImageType.base, retrieved.image_type);
    try testing.expectEqualStrings("22.04", retrieved.version);
    try testing.expectEqualStrings("/var/lib/lxc/images/ubuntu-22.04.tar.gz", retrieved.path);
    try testing.expectEqual(@as(u64, 1024 * 1024 * 100), retrieved.size);
    try testing.expectEqualStrings("sha256:1234567890", retrieved.hash);
}

test "StorageManager - storage not found" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();

    const storage_config = storage.StorageConfig{
        .id = "local-1",
        .storage_type = storage.StorageType.local,
        .path = "/var/lib/lxc",
        .default_size = 10,
    };

    try manager.addStorage(storage_config);
    try testing.expect(manager.getStorage("non-existent") == null);
}

test "StorageManager - image not found" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();

    const image_config = storage.ImageConfig{
        .id = "ubuntu-22.04",
        .name = "Ubuntu 22.04",
        .image_type = storage.ImageType.base,
        .version = "22.04",
        .path = "/var/lib/lxc/images/ubuntu-22.04.tar.gz",
        .size = 1024 * 1024 * 100,
        .hash = "sha256:1234567890",
    };

    try manager.addImage(image_config);
    try testing.expect(manager.getImage("non-existent") == null);
}

test "DiskConfig - create and delete disk" {
    var manager = storage.StorageManager.init(testing.allocator);
    defer manager.deinit();

    const storage_config = storage.StorageConfig{
        .id = "local-1",
        .storage_type = storage.StorageType.local,
        .path = "/var/lib/lxc",
        .default_size = 10,
    };

    try manager.addStorage(storage_config);

    const disk_config = storage.DiskConfig{
        .storage_id = "local-1",
        .size = 20,
        .format = "raw",
    };

    try manager.createDisk("local-1", disk_config);
    try manager.deleteDisk("local-1", "/var/lib/lxc/test-container/rootfs.raw");
}
