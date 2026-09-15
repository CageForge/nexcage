const std = @import("std");
const testing = std.testing;
const spec = @import("../src/oci/spec.zig");
const builder = @import("../src/oci/builder.zig");
const resources = @import("../src/oci/resources.zig");

test "OCI Spec - basic container spec" {
    const allocator = testing.allocator;

    // Створюємо базову специфікацію контейнера
    var container_spec = spec.Spec{
        .oci_version = try allocator.dupe(u8, "1.0.0"),
        .process = .{
            .terminal = true,
            .console_size = null,
            .user = .{
                .uid = 1000,
                .gid = 1000,
                .additional_gids = null,
            },
            .args = try allocator.dupe([]const u8, &[_][]const u8{"sh"}),
            .env = try allocator.dupe([]const u8, &[_][]const u8{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"}),
            .cwd = try allocator.dupe(u8, "/"),
            .capabilities = null,
            .rlimits = &[_]spec.Rlimit{},
            .no_new_privileges = true,
        },
        .root = .{
            .path = try allocator.dupe(u8, "rootfs"),
            .readonly = false,
        },
        .mounts = try allocator.dupe(spec.Mount, &[_]spec.Mount{
            .{
                .destination = try allocator.dupe(u8, "/proc"),
                .source = try allocator.dupe(u8, "proc"),
                .type = try allocator.dupe(u8, "proc"),
                .options = null,
            },
        }),
        .hostname = try allocator.dupe(u8, "container"),
        .linux = .{
            .devices = &[_]spec.Device{},
            .resources = null,
            .cgroups_path = null,
            .namespaces = try allocator.dupe(spec.Namespace, &[_]spec.Namespace{
                .{
                    .type = try allocator.dupe(u8, "pid"),
                    .path = null,
                },
                .{
                    .type = try allocator.dupe(u8, "network"),
                    .path = null,
                },
                .{
                    .type = try allocator.dupe(u8, "ipc"),
                    .path = null,
                },
                .{
                    .type = try allocator.dupe(u8, "uts"),
                    .path = null,
                },
                .{
                    .type = try allocator.dupe(u8, "mount"),
                    .path = null,
                },
            }),
            .masked_paths = &[_][]const u8{},
            .readonly_paths = &[_][]const u8{},
            .mount_label = null,
        },
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    defer container_spec.deinit(allocator);

    // Перевіряємо базові поля
    try testing.expectEqualStrings("1.0.0", container_spec.oci_version);
    try testing.expectEqual(true, container_spec.process.terminal);
    try testing.expectEqual(@as(u32, 1000), container_spec.process.user.uid);
    try testing.expectEqualStrings("rootfs", container_spec.root.path);
    try testing.expectEqual(false, container_spec.root.readonly);
    try testing.expectEqualStrings("container", container_spec.hostname.?);
    try testing.expectEqual(@as(usize, 5), container_spec.linux.?.namespaces.len);
}

test "OCI Spec - container with resources" {
    const allocator = testing.allocator;

    // Створюємо ресурси для контейнера
    var container_resources = resources.Resources{
        .cpu = .{
            .shares = 1024,
            .quota = 100000,
            .period = 100000,
            .realtime_runtime = null,
            .realtime_period = null,
            .cpus = try allocator.dupe(u8, "0-3"),
            .mems = null,
        },
        .memory = .{
            .limit = 536870912, // 512MB
            .reservation = 268435456, // 256MB
            .swap = null,
            .kernel = null,
            .kernel_tcp = null,
            .swappiness = null,
            .disable_oom_killer = null,
        },
        .pids = .{
            .limit = 1000,
        },
        .block_io = null,
        .hugepage_limits = null,
        .network = null,
    };
    defer container_resources.deinit(allocator);

    // Перевіряємо ресурси
    try testing.expectEqual(@as(u64, 1024), container_resources.cpu.?.shares.?);
    try testing.expectEqual(@as(i64, 100000), container_resources.cpu.?.quota.?);
    try testing.expectEqualStrings("0-3", container_resources.cpu.?.cpus.?);
    try testing.expectEqual(@as(i64, 536870912), container_resources.memory.?.limit.?);
    try testing.expectEqual(@as(i64, 1000), container_resources.pids.?.limit);
}

test "OCI Spec - container with capabilities" {
    const allocator = testing.allocator;

    // Створюємо capabilities для контейнера
    var container_capabilities = spec.Capabilities{
        .bounding = try allocator.dupe([]const u8, &[_][]const u8{
            try allocator.dupe(u8, "CAP_CHOWN"),
            try allocator.dupe(u8, "CAP_DAC_OVERRIDE"),
            try allocator.dupe(u8, "CAP_FSETID"),
        }),
        .effective = try allocator.dupe([]const u8, &[_][]const u8{
            try allocator.dupe(u8, "CAP_CHOWN"),
            try allocator.dupe(u8, "CAP_DAC_OVERRIDE"),
        }),
        .inheritable = null,
        .permitted = null,
        .ambient = null,
    };
    defer container_capabilities.deinit(allocator);

    // Перевіряємо capabilities
    try testing.expectEqual(@as(usize, 3), container_capabilities.bounding.?.len);
    try testing.expectEqual(@as(usize, 2), container_capabilities.effective.?.len);
    try testing.expectEqualStrings("CAP_CHOWN", container_capabilities.bounding.?[0]);
    try testing.expectEqualStrings("CAP_DAC_OVERRIDE", container_capabilities.effective.?[1]);
}

test "SpecBuilder - basic container spec" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var spec_builder = try builder.SpecBuilder.init(allocator);
    defer spec_builder.deinit();

    // Встановлюємо процес
    try spec_builder.setProcess(spec.Process{
        .args = &[_][]const u8{ "/bin/sh", "-c", "echo hello" },
        .env = &[_][]const u8{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
        .cwd = "/",
        .capabilities = null,
    });

    // Встановлюємо root
    try spec_builder.setRoot(spec.Root{
        .path = "/rootfs",
        .readonly = false,
    });

    // Встановлюємо хостнейм
    try spec_builder.setHostname("test-container");

    // Будуємо специфікацію
    const container_spec = try spec_builder.build();

    try testing.expectEqualStrings("1.0.0", container_spec.oci_version);
    try testing.expectEqualStrings("/bin/sh", container_spec.process.args[0]);
    try testing.expectEqualStrings("/rootfs", container_spec.root.path);
    try testing.expectEqualStrings("test-container", container_spec.hostname.?);
}

test "SpecBuilder - mounts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var spec_builder = try builder.SpecBuilder.init(allocator);
    defer spec_builder.deinit();

    // Встановлюємо необхідні поля
    try spec_builder.setProcess(spec.Process{
        .args = &[_][]const u8{"/bin/sh"},
        .env = &[_][]const u8{},
        .cwd = "/",
        .capabilities = null,
    });

    try spec_builder.setRoot(spec.Root{
        .path = "/rootfs",
        .readonly = false,
    });

    // Додаємо точки монтування
    try spec_builder.addMount(spec.Mount{
        .destination = "/proc",
        .type = "proc",
        .source = "proc",
        .options = &[_][]const u8{},
    });

    try spec_builder.addMount(spec.Mount{
        .destination = "/dev",
        .type = "tmpfs",
        .source = "tmpfs",
        .options = &[_][]const u8{ "nosuid", "strictatime", "mode=755", "size=65536k" },
    });

    const container_spec = try spec_builder.build();

    try testing.expectEqual(@as(usize, 2), container_spec.mounts.len);
    try testing.expectEqualStrings("/proc", container_spec.mounts[0].destination);
    try testing.expectEqualStrings("/dev", container_spec.mounts[1].destination);
}

test "SpecBuilder - validation errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var spec_builder = try builder.SpecBuilder.init(allocator);
    defer spec_builder.deinit();

    // Спроба побудувати без процесу та root
    try testing.expectError(builder.SpecError.InvalidProcess, spec_builder.build());

    // Встановлюємо процес без аргументів
    try spec_builder.setProcess(spec.Process{
        .args = &[_][]const u8{},
        .env = &[_][]const u8{},
        .cwd = "/",
        .capabilities = null,
    });

    try testing.expectError(builder.SpecError.InvalidProcess, spec_builder.build());

    // Встановлюємо процес з аргументами, але без root
    try spec_builder.setProcess(spec.Process{
        .args = &[_][]const u8{"/bin/sh"},
        .env = &[_][]const u8{},
        .cwd = "/",
        .capabilities = null,
    });

    try testing.expectError(builder.SpecError.InvalidRoot, spec_builder.build());

    // Встановлюємо root з пустим шляхом
    try spec_builder.setRoot(spec.Root{
        .path = "",
        .readonly = false,
    });

    try testing.expectError(builder.SpecError.InvalidRoot, spec_builder.build());
}
