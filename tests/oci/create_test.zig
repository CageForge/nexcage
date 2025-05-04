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

test "Create container with network configuration" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з мережевою конфігурацією
    try createTestBundle(allocator, bundle_path, .{
        .network = .{
            .bridge = "vmbr0",
            .ip = "10.0.0.2/24",
            .gateway = "10.0.0.1",
            .dns = .{ "8.8.8.8", "8.8.4.4" },
        },
    });

    // Створюємо контейнер
    const container_id = "test-network";
    try create(allocator, container_id, bundle_path);

    // Перевіряємо мережеві налаштування
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);

    // Перевіряємо наявність мережевих налаштувань
    try std.testing.expect(std.mem.indexOf(u8, config_content, "net0: bridge=vmbr0,ip=10.0.0.2/24,gw=10.0.0.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "nameserver: 8.8.8.8") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "nameserver: 8.8.4.4") != null);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Create container with multiple network interfaces" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з кількома мережевими інтерфейсами
    try createTestBundle(allocator, bundle_path, .{
        .networks = &.{
            .{
                .bridge = "vmbr0",
                .ip = "10.0.0.2/24",
                .gateway = "10.0.0.1",
            },
            .{
                .bridge = "vmbr1",
                .ip = "192.168.1.2/24",
            },
        },
    });

    // Створюємо контейнер
    const container_id = "test-multi-network";
    try create(allocator, container_id, bundle_path);

    // Перевіряємо мережеві налаштування
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);

    // Перевіряємо наявність налаштувань для обох інтерфейсів
    try std.testing.expect(std.mem.indexOf(u8, config_content, "net0: bridge=vmbr0,ip=10.0.0.2/24,gw=10.0.0.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "net1: bridge=vmbr1,ip=192.168.1.2/24") != null);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Full container lifecycle" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle
    try createTestBundle(allocator, bundle_path, .{
        .network = .{
            .bridge = "vmbr0",
            .ip = "10.0.0.2/24",
            .gateway = "10.0.0.1",
        },
        .resources = .{
            .memory = 512 * 1024 * 1024, // 512MB
            .cpu = 1,
        },
    });

    const container_id = "test-lifecycle";
    
    // 1. Створення контейнера
    try create(allocator, container_id, bundle_path);
    
    // Перевіряємо стан після створення
    const state = try getContainerState(allocator, container_id);
    try std.testing.expectEqual(ContainerState.created, state);

    // 2. Запуск контейнера
    try start(allocator, container_id);
    
    // Перевіряємо стан після запуску
    const running_state = try getContainerState(allocator, container_id);
    try std.testing.expectEqual(ContainerState.running, running_state);

    // 3. Перевіряємо процеси в контейнері
    const processes = try getContainerProcesses(allocator, container_id);
    try std.testing.expect(processes.len > 0);

    // 4. Зупинка контейнера
    try stop(allocator, container_id);
    
    // Перевіряємо стан після зупинки
    const stopped_state = try getContainerState(allocator, container_id);
    try std.testing.expectEqual(ContainerState.stopped, stopped_state);

    // 5. Видалення контейнера
    try delete(allocator, container_id);
    
    // Перевіряємо що контейнер видалено
    const exists = try containerExists(allocator, container_id);
    try std.testing.expect(!exists);

    // Очищаємо
    try cleanupTestBundle(allocator, bundle_path);
}

test "Container lifecycle with hooks" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з hooks
    try createTestBundle(allocator, bundle_path, .{
        .hooks = .{
            .prestart = &.{
                .{
                    .path = "/bin/echo",
                    .args = &.{ "echo", "prestart hook executed" },
                },
            },
            .poststop = &.{
                .{
                    .path = "/bin/echo",
                    .args = &.{ "echo", "poststop hook executed" },
                },
            },
        },
    });

    const container_id = "test-hooks";
    
    // 1. Створення контейнера
    try create(allocator, container_id, bundle_path);
    
    // 2. Запуск контейнера (виконається prestart hook)
    try start(allocator, container_id);
    
    // 3. Зупинка контейнера (виконається poststop hook)
    try stop(allocator, container_id);
    
    // 4. Видалення контейнера
    try delete(allocator, container_id);

    // Очищаємо
    try cleanupTestBundle(allocator, bundle_path);
}

test "Create container with resource limits" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з обмеженнями ресурсів
    try createTestBundle(allocator, bundle_path, .{
        .resources = .{
            .memory = 1024 * 1024 * 1024, // 1GB
            .memory_swap = 2048 * 1024 * 1024, // 2GB
            .cpu = 2,
            .cpu_shares = 512,
            .cpu_quota = 50000, // 50%
            .cpu_period = 100000,
        },
    });

    const container_id = "test-resources";
    try create(allocator, container_id, bundle_path);

    // Перевіряємо налаштування ресурсів
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);

    // Перевіряємо налаштування пам'яті
    try std.testing.expect(std.mem.indexOf(u8, config_content, "memory: 1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "swap: 2048") != null);
    
    // Перевіряємо налаштування CPU
    try std.testing.expect(std.mem.indexOf(u8, config_content, "cores: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "cpulimit: 50") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "cpuunits: 512") != null);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Create container with rootfs configuration" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з налаштуваннями rootfs
    try createTestBundle(allocator, bundle_path, .{
        .rootfs = .{
            .readonly = true,
            .mounts = &.{
                .{
                    .source = "/host/path",
                    .destination = "/container/path",
                    .options = "bind,ro",
                },
            },
        },
    });

    const container_id = "test-rootfs";
    try create(allocator, container_id, bundle_path);

    // Перевіряємо налаштування rootfs
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);

    // Перевіряємо налаштування rootfs
    try std.testing.expect(std.mem.indexOf(u8, config_content, "rootfs: ro") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_content, "mp0: /host/path,/container/path,bind,ro") != null);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Create container with security profiles" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з профілями безпеки
    try createTestBundle(allocator, bundle_path, .{
        .security = .{
            .apparmor = "lxc-container-default",
            .selinux = "container_t",
            .seccomp = &.{
                .{
                    .action = "SCMP_ACT_ALLOW",
                    .syscall = "read",
                },
                .{
                    .action = "SCMP_ACT_ERRNO",
                    .syscall = "mount",
                },
            },
            .capabilities = &.{
                "CAP_NET_BIND_SERVICE",
                "CAP_SYS_ADMIN",
            },
        },
    });

    const container_id = "test-security";
    try create(allocator, container_id, bundle_path);

    // Перевіряємо налаштування безпеки
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);

    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();

    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);

    // Перевіряємо налаштування AppArmor
    try std.testing.expect(std.mem.indexOf(u8, config_content, "lxc.apparmor.profile: lxc-container-default") != null);
    
    // Перевіряємо налаштування SELinux
    try std.testing.expect(std.mem.indexOf(u8, config_content, "lxc.selinux.context: container_t") != null);
    
    // Перевіряємо налаштування seccomp
    try std.testing.expect(std.mem.indexOf(u8, config_content, "lxc.seccomp.profile:") != null);
    
    // Перевіряємо налаштування capabilities
    try std.testing.expect(std.mem.indexOf(u8, config_content, "lxc.cap.drop:") != null);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Create containers in parallel" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle
    try createTestBundle(allocator, bundle_path, .{});

    // Створюємо 5 контейнерів паралельно
    var threads: [5]std.Thread = undefined;
    var containers: [5][]const u8 = undefined;
    
    for (0..5) |i| {
        containers[i] = try std.fmt.allocPrint(allocator, "test-parallel-{d}", .{i});
        defer allocator.free(containers[i]);
        
        threads[i] = try std.Thread.spawn(.{}, struct {
            fn createContainer(id: []const u8, path: []const u8) !void {
                try create(allocator, id, path);
            }
        }.createContainer, .{ containers[i], bundle_path });
    }

    // Чекаємо завершення всіх потоків
    for (threads) |thread| {
        thread.join();
    }

    // Перевіряємо що всі контейнери створені
    for (containers) |container_id| {
        const exists = try containerExists(allocator, container_id);
        try std.testing.expect(exists);
        
        // Очищаємо
        try cleanupTestContainer(allocator, container_id);
    }

    try cleanupTestBundle(allocator, bundle_path);
}

test "Container recovery after errors" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle
    try createTestBundle(allocator, bundle_path, .{});

    const container_id = "test-recovery";
    
    // 1. Створюємо контейнер
    try create(allocator, container_id, bundle_path);
    
    // 2. Симулюємо помилку (видаляємо конфігурацію)
    const config_path = try std.fs.path.join(allocator, &.{ "/etc/pve/lxc", container_id, "config" });
    defer allocator.free(config_path);
    try std.fs.deleteFileAbsolute(config_path);
    
    // 3. Спробуємо відновити контейнер
    try create(allocator, container_id, bundle_path);
    
    // 4. Перевіряємо що контейнер відновлено
    const exists = try containerExists(allocator, container_id);
    try std.testing.expect(exists);
    
    // 5. Перевіряємо що конфігурація відновлена
    const config_file = try std.fs.openFileAbsolute(config_path, .{});
    defer config_file.close();
    
    var buffer: [1024]u8 = undefined;
    const config_content = try config_file.readAll(&buffer);
    try std.testing.expect(config_content.len > 0);

    // Очищаємо
    try cleanupTestContainer(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
}

test "Container security verification" {
    const allocator = std.testing.allocator;
    const bundle_path = try std.fs.path.join(allocator, &.{ "test", "bundle" });
    defer allocator.free(bundle_path);

    // Створюємо тестовий bundle з обмеженими правами
    try createTestBundle(allocator, bundle_path, .{
        .security = .{
            .apparmor = "lxc-container-default",
            .capabilities = &.{},
        },
    });

    const container_id = "test-security-verify";
    try create(allocator, container_id, bundle_path);
    
    // Запускаємо контейнер
    try start(allocator, container_id);
    
    // Перевіряємо безпеку
    const cmd = try std.fmt.allocPrint(allocator, "lxc-attach -n {s} -- /bin/sh -c 'mount'", .{container_id});
    defer allocator.free(cmd);
    
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "/bin/sh", "-c", cmd },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    
    // Перевіряємо що mount команда заблокована
    try std.testing.expect(result.stderr.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "Permission denied") != null);

    // Очищаємо
    try stop(allocator, container_id);
    try delete(allocator, container_id);
    try cleanupTestBundle(allocator, bundle_path);
} 