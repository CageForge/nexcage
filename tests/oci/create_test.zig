const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const json = std.json;
const logger = std.log.scoped(.oci_create_test);

const Create = @import("../../src/oci/create.zig").Create;
const CreateOptions = @import("../../src/oci/create.zig").CreateOptions;
const StorageType = @import("../../src/oci/create.zig").StorageType;
const StorageConfig = @import("../../src/oci/create.zig").StorageConfig;
const spec = @import("../../src/oci/spec.zig");

// Функція для перевірки витоку пам'яті
fn checkMemoryLeaks(allocator: *std.mem.Allocator) !void {
    const info = try allocator.detectLeaks();
    if (info.leak_count > 0) {
        logger.err("Memory leak detected: {d} allocations not freed", .{info.leak_count});
        return error.MemoryLeak;
    }
}

test "create container with raw image and raw storage" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    // Створюємо темпову директорію для тесту
    const tmp_dir = try fs.cwd().makeOpenPath("/tmp/oci-test", .{});
    defer {
        fs.cwd().deleteTree("/tmp/oci-test") catch {};
    }

    // Створюємо bundle директорію
    const bundle_path = "/tmp/oci-test/bundle";
    try fs.cwd().makePath(bundle_path);

    // Створюємо rootfs директорію
    const rootfs_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "rootfs" });
    defer allocator.free(rootfs_path);
    try fs.cwd().makePath(rootfs_path);

    // Створюємо config.json
    const config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "config.json" });
    defer allocator.free(config_path);
    const config_file = try fs.cwd().createFile(config_path, .{});
    defer config_file.close();

    const config_content = 
        \\{
        \\  "ociVersion": "1.0.0",
        \\  "process": {
        \\    "terminal": true,
        \\    "user": {
        \\      "uid": 0,
        \\      "gid": 0
        \\    },
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
        \\    "cwd": "/"
        \\  },
        \\  "root": {
        \\    "path": "rootfs",
        \\    "readonly": false
        \\  },
        \\  "hostname": "test-container",
        \\  "mounts": [],
        \\  "linux": {
        \\    "namespaces": [
        \\      {
        \\        "type": "pid"
        \\      },
        \\      {
        \\        "type": "network"
        \\      },
        \\      {
        \\        "type": "ipc"
        \\      },
        \\      {
        \\        "type": "uts"
        \\      },
        \\      {
        \\        "type": "mount"
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);

    // Створюємо OCI конфігурацію
    const oci_config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "test-container.json" });
    defer allocator.free(oci_config_path);
    const oci_config_file = try fs.cwd().createFile(oci_config_path, .{});
    defer oci_config_file.close();

    const oci_config_content = 
        \\{
        \\  "storage": {
        \\    "type": "raw",
        \\    "storage_path": "/tmp/oci-test/storage"
        \\  },
        \\  "raw_image": true,
        \\  "raw_image_size": 1073741824
        \\}
    ;
    try oci_config_file.writeAll(oci_config_content);

    // Створюємо тестовий образ
    const image_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "rootfs", "bin" });
    defer allocator.free(image_path);
    try fs.cwd().makePath(image_path);

    const sh_path = try fs.path.join(allocator, &[_][]const u8{ image_path, "sh" });
    defer allocator.free(sh_path);
    const sh_file = try fs.cwd().createFile(sh_path, .{});
    defer sh_file.close();
    try sh_file.writeAll("#!/bin/sh\necho 'Hello from test container'");

    // Створюємо опції для створення контейнера
    const options = CreateOptions{
        .container_id = "test-container",
        .bundle_path = bundle_path,
        .image_name = "test-image",
        .image_tag = "latest",
        .zfs_dataset = "tank/lxc",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };

    // Створюємо менеджери
    var image_manager = try @import("../../src/oci/image/manager.zig").ImageManager.init(allocator, "/tmp/oci-test/images");
    defer image_manager.deinit();

    var zfs_manager = try @import("../../src/zfs/manager.zig").ZFSManager.init(allocator);
    defer zfs_manager.deinit();

    var lxc_manager = try @import("../../src/lxc/container.zig").LXCManager.init(allocator);
    defer lxc_manager.deinit();

    var proxmox_client = try @import("../../src/proxmox/client.zig").ProxmoxClient.init(allocator, "https://pve.example.com", "root@pam", "password");
    defer proxmox_client.deinit();

    // Створюємо контейнер
    var create = try Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
        options,
    );
    defer create.deinit();

    try create.create();

    // Перевіряємо чи контейнер створений
    try testing.expect(try lxc_manager.containerExists("test-container"));

    // Перевіряємо чи raw файл створений
    const raw_path = try fs.path.join(allocator, &[_][]const u8{ "/tmp/oci-test/storage", "test-container", "test-container.raw" });
    defer allocator.free(raw_path);
    try testing.expect(try fs.cwd().access(raw_path, .{}));

    // Перевіряємо чи всі ресурси звільнені
    try testing.expect(!try lxc_manager.containerExists("test-container"));
    try testing.expect(!try fs.cwd().access(raw_path, .{}));
}

test "create container with zfs storage" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    // Створюємо темпову директорію для тесту
    const tmp_dir = try fs.cwd().makeOpenPath("/tmp/oci-test", .{});
    defer {
        fs.cwd().deleteTree("/tmp/oci-test") catch {};
    }

    // Створюємо bundle директорію
    const bundle_path = "/tmp/oci-test/bundle";
    try fs.cwd().makePath(bundle_path);

    // Створюємо rootfs директорію
    const rootfs_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "rootfs" });
    defer allocator.free(rootfs_path);
    try fs.cwd().makePath(rootfs_path);

    // Створюємо config.json
    const config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "config.json" });
    defer allocator.free(config_path);
    const config_file = try fs.cwd().createFile(config_path, .{});
    defer config_file.close();

    const config_content = 
        \\{
        \\  "ociVersion": "1.0.0",
        \\  "process": {
        \\    "terminal": true,
        \\    "user": {
        \\      "uid": 0,
        \\      "gid": 0
        \\    },
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
        \\    "cwd": "/"
        \\  },
        \\  "root": {
        \\    "path": "rootfs",
        \\    "readonly": false
        \\  },
        \\  "hostname": "test-container",
        \\  "mounts": [],
        \\  "linux": {
        \\    "namespaces": [
        \\      {
        \\        "type": "pid"
        \\      },
        \\      {
        \\        "type": "network"
        \\      },
        \\      {
        \\        "type": "ipc"
        \\      },
        \\      {
        \\        "type": "uts"
        \\      },
        \\      {
        \\        "type": "mount"
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);

    // Створюємо OCI конфігурацію
    const oci_config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "test-container.json" });
    defer allocator.free(oci_config_path);
    const oci_config_file = try fs.cwd().createFile(oci_config_path, .{});
    defer oci_config_file.close();

    const oci_config_content = 
        \\{
        \\  "storage": {
        \\    "type": "zfs",
        \\    "storage_pool": "tank/lxc"
        \\  },
        \\  "raw_image": false
        \\}
    ;
    try oci_config_file.writeAll(oci_config_content);

    // Створюємо тестовий образ
    const image_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "rootfs", "bin" });
    defer allocator.free(image_path);
    try fs.cwd().makePath(image_path);

    const sh_path = try fs.path.join(allocator, &[_][]const u8{ image_path, "sh" });
    defer allocator.free(sh_path);
    const sh_file = try fs.cwd().createFile(sh_path, .{});
    defer sh_file.close();
    try sh_file.writeAll("#!/bin/sh\necho 'Hello from test container'");

    // Створюємо опції для створення контейнера
    const options = CreateOptions{
        .container_id = "test-container",
        .bundle_path = bundle_path,
        .image_name = "test-image",
        .image_tag = "latest",
        .zfs_dataset = "tank/lxc",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };

    // Створюємо менеджери
    var image_manager = try @import("../../src/oci/image/manager.zig").ImageManager.init(allocator, "/tmp/oci-test/images");
    defer image_manager.deinit();

    var zfs_manager = try @import("../../src/zfs/manager.zig").ZFSManager.init(allocator);
    defer zfs_manager.deinit();

    var lxc_manager = try @import("../../src/lxc/container.zig").LXCManager.init(allocator);
    defer lxc_manager.deinit();

    var proxmox_client = try @import("../../src/proxmox/client.zig").ProxmoxClient.init(allocator, "https://pve.example.com", "root@pam", "password");
    defer proxmox_client.deinit();

    // Створюємо контейнер
    var create = try Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
        options,
    );
    defer create.deinit();

    try create.create();

    // Перевіряємо чи контейнер створений
    try testing.expect(try lxc_manager.containerExists("test-container"));

    // Перевіряємо чи ZFS dataset створений
    const dataset_path = try fs.path.join(allocator, &[_][]const u8{ "tank/lxc", "test-container" });
    defer allocator.free(dataset_path);
    try testing.expect(try zfs_manager.datasetExists(dataset_path));

    // Перевіряємо чи всі ресурси звільнені
    try testing.expect(!try lxc_manager.containerExists("test-container"));
    try testing.expect(!try zfs_manager.datasetExists(dataset_path));
}

test "create container with registry image" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    // Створюємо темпову директорію для тесту
    const tmp_dir = try fs.cwd().makeOpenPath("/tmp/oci-test", .{});
    defer {
        fs.cwd().deleteTree("/tmp/oci-test") catch {};
    }

    // Створюємо bundle директорію
    const bundle_path = "/tmp/oci-test/bundle";
    try fs.cwd().makePath(bundle_path);

    // Створюємо rootfs директорію
    const rootfs_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "rootfs" });
    defer allocator.free(rootfs_path);
    try fs.cwd().makePath(rootfs_path);

    // Створюємо config.json
    const config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "config.json" });
    defer allocator.free(config_path);
    const config_file = try fs.cwd().createFile(config_path, .{});
    defer config_file.close();

    const config_content = 
        \\{
        \\  "ociVersion": "1.0.0",
        \\  "process": {
        \\    "terminal": true,
        \\    "user": {
        \\      "uid": 0,
        \\      "gid": 0
        \\    },
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
        \\    "cwd": "/"
        \\  },
        \\  "root": {
        \\    "path": "rootfs",
        \\    "readonly": false
        \\  },
        \\  "hostname": "test-container",
        \\  "mounts": [],
        \\  "linux": {
        \\    "namespaces": [
        \\      {
        \\        "type": "pid"
        \\      },
        \\      {
        \\        "type": "network"
        \\      },
        \\      {
        \\        "type": "ipc"
        \\      },
        \\      {
        \\        "type": "uts"
        \\      },
        \\      {
        \\        "type": "mount"
        \\      }
        \\    ]
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);

    // Створюємо OCI конфігурацію
    const oci_config_path = try fs.path.join(allocator, &[_][]const u8{ bundle_path, "test-container.json" });
    defer allocator.free(oci_config_path);
    const oci_config_file = try fs.cwd().createFile(oci_config_path, .{});
    defer oci_config_file.close();

    const oci_config_content = 
        \\{
        \\  "storage": {
        \\    "type": "raw",
        \\    "storage_path": "/tmp/oci-test/storage"
        \\  },
        \\  "raw_image": true,
        \\  "raw_image_size": 1073741824,
        \\  "registry_url": "registry.example.com",
        \\  "registry_username": "test-user",
        \\  "registry_password": "test-password"
        \\}
    ;
    try oci_config_file.writeAll(oci_config_content);

    // Створюємо опції для створення контейнера
    const options = CreateOptions{
        .container_id = "test-container",
        .bundle_path = bundle_path,
        .image_name = "test-image",
        .image_tag = "latest",
        .zfs_dataset = "tank/lxc",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };

    // Створюємо менеджери
    var image_manager = try @import("../../src/oci/image/manager.zig").ImageManager.init(allocator, "/tmp/oci-test/images");
    defer image_manager.deinit();

    var zfs_manager = try @import("../../src/zfs/manager.zig").ZFSManager.init(allocator);
    defer zfs_manager.deinit();

    var lxc_manager = try @import("../../src/lxc/container.zig").LXCManager.init(allocator);
    defer lxc_manager.deinit();

    var proxmox_client = try @import("../../src/proxmox/client.zig").ProxmoxClient.init(allocator, "https://pve.example.com", "root@pam", "password");
    defer proxmox_client.deinit();

    // Створюємо контейнер
    var create = try Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
        options,
    );
    defer create.deinit();

    try create.create();

    // Перевіряємо чи контейнер створений
    try testing.expect(try lxc_manager.containerExists("test-container"));

    // Перевіряємо чи raw файл створений
    const raw_path = try fs.path.join(allocator, &[_][]const u8{ "/tmp/oci-test/storage", "test-container", "test-container.raw" });
    defer allocator.free(raw_path);
    try testing.expect(try fs.cwd().access(raw_path, .{}));

    // Перевіряємо чи образ завантажений
    const image_path = try fs.path.join(allocator, &[_][]const u8{ "/tmp/oci-test/images", "test-image:latest" });
    defer allocator.free(image_path);
    try testing.expect(try fs.cwd().access(image_path, .{}));

    // Перевіряємо чи всі ресурси звільнені
    try testing.expect(!try lxc_manager.containerExists("test-container"));
    try testing.expect(!try fs.cwd().access(raw_path, .{}));
    try testing.expect(!try fs.cwd().access(image_path, .{}));
} 