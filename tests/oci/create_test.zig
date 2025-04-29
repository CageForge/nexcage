const std = @import("std");
const testing = std.testing;
const oci = @import("oci");
const create = oci.create;
const types = oci.types;

test "Create container with minimal options" {
    const allocator = testing.allocator;
    
    const options = create.CreateOptions{
        .container_id = "test-container",
        .bundle_path = "/tmp/bundle",
        .image_name = "alpine",
        .image_tag = "latest",
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };
    
    var creator = try create.Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
    );
    defer creator.deinit();
    
    try creator.create(options);
    
    // Перевіряємо що контейнер створено
    const container = try lxc_manager.getContainer("test-container");
    try testing.expect(container != null);
}

test "Create container with custom config" {
    const allocator = testing.allocator;
    
    var config = types.ImageConfig{
        .env = std.StringHashMap([]const u8).init(allocator),
        .cmd = &[_][]const u8{"/bin/sh"},
        .working_dir = "/app",
        .user = "1000:1000",
    };
    try config.env.put("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    try config.env.put("TERM", "xterm");
    
    const options = create.CreateOptions{
        .container_id = "test-container",
        .bundle_path = "/tmp/bundle",
        .image_name = "alpine",
        .image_tag = "latest",
        .config = config,
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };
    
    var creator = try create.Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
    );
    defer creator.deinit();
    
    try creator.create(options);
    
    // Перевіряємо конфігурацію створеного контейнера
    const container = try lxc_manager.getContainer("test-container");
    try testing.expect(container != null);
    try testing.expectEqualStrings("/app", container.?.config.working_dir);
    try testing.expectEqualStrings("1000:1000", container.?.config.user);
}

test "Create container with hooks" {
    const allocator = testing.allocator;
    
    var hooks = types.Hooks{
        .prestart = &[_]types.Hook{
            .{
                .path = "/usr/bin/echo",
                .args = &[_][]const u8{"prestart"},
            },
        },
        .poststart = &[_]types.Hook{
            .{
                .path = "/usr/bin/echo",
                .args = &[_][]const u8{"poststart"},
            },
        },
    };
    
    const options = create.CreateOptions{
        .container_id = "test-container",
        .bundle_path = "/tmp/bundle",
        .image_name = "alpine",
        .image_tag = "latest",
        .hooks = hooks,
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };
    
    var creator = try create.Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
    );
    defer creator.deinit();
    
    try creator.create(options);
    
    // Перевіряємо що хуки виконались
    // TODO: додати перевірку логів або іншого способу підтвердження виконання хуків
}

test "Create container error handling" {
    const allocator = testing.allocator;
    
    // Тест з неіснуючим образом
    const invalid_image_options = create.CreateOptions{
        .container_id = "test-container",
        .bundle_path = "/tmp/bundle",
        .image_name = "nonexistent",
        .image_tag = "latest",
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };
    
    var creator = try create.Create.init(
        allocator,
        &image_manager,
        &zfs_manager,
        &lxc_manager,
        &proxmox_client,
    );
    defer creator.deinit();
    
    try testing.expectError(
        error.ImageNotFound,
        creator.create(invalid_image_options),
    );
    
    // Тест з неіснуючим bundle path
    const invalid_bundle_options = create.CreateOptions{
        .container_id = "test-container",
        .bundle_path = "/nonexistent/bundle",
        .image_name = "alpine",
        .image_tag = "latest",
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    };
    
    try testing.expectError(
        error.BundleNotFound,
        creator.create(invalid_bundle_options),
    );
    
    // Тест з існуючим контейнером
    try creator.create(create.CreateOptions{
        .container_id = "existing",
        .bundle_path = "/tmp/bundle",
        .image_name = "alpine",
        .image_tag = "latest",
        .zfs_dataset = "zroot/containers",
        .proxmox_node = "pve",
        .proxmox_storage = "local",
    });
    
    try testing.expectError(
        error.ContainerExists,
        creator.create(create.CreateOptions{
            .container_id = "existing",
            .bundle_path = "/tmp/bundle",
            .image_name = "alpine",
            .image_tag = "latest",
            .zfs_dataset = "zroot/containers",
            .proxmox_node = "pve",
            .proxmox_storage = "local",
        }),
    );
} 