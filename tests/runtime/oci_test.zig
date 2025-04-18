const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime");
const types = @import("types");
const oci = runtime.oci;

test "OCIRuntime initialization" {
    const allocator = testing.allocator;
    
    const rt = try oci.OCIRuntime.init(
        allocator,
        "/tmp/test-root",
        "/tmp/test-state",
    );
    defer rt.deinit();

    try testing.expectEqual(runtime.RuntimeInterface.RuntimeType.oci, rt.interface.config.runtime_type);
    try testing.expectEqualStrings("/tmp/test-root", rt.interface.config.root_dir);
    try testing.expectEqualStrings("/tmp/test-state", rt.interface.config.state_dir);
}

test "OCIRuntime container lifecycle" {
    const allocator = testing.allocator;
    
    const rt = try oci.OCIRuntime.init(
        allocator,
        "/tmp/test-root",
        "/tmp/test-state",
    );
    defer rt.deinit();

    // Створення контейнера
    const config = types.ContainerConfig{
        .id = "test-container",
        .name = "test",
        .root_path = "/tmp/test-root/test-container",
        .hostname = "test-host",
        .resources = null,
    };
    try rt.interface.create(config);

    // Перевірка стану після створення
    const initial_state = try rt.interface.state("test-container");
    try testing.expectEqual(runtime.RuntimeInterface.State.created, initial_state);

    // Запуск контейнера
    try rt.interface.start("test-container");
    const running_state = try rt.interface.state("test-container");
    try testing.expectEqual(runtime.RuntimeInterface.State.running, running_state);

    // Зупинка контейнера
    try rt.interface.stop("test-container");
    const stopped_state = try rt.interface.state("test-container");
    try testing.expectEqual(runtime.RuntimeInterface.State.stopped, stopped_state);

    // Видалення контейнера
    try rt.interface.delete("test-container");
    try testing.expectError(error.NotFound, rt.interface.state("test-container"));
}

test "OCIRuntime resource management" {
    const allocator = testing.allocator;
    
    const rt = try oci.OCIRuntime.init(
        allocator,
        "/tmp/test-root",
        "/tmp/test-state",
    );
    defer rt.deinit();

    // Створення контейнера з ресурсами
    const config = types.ContainerConfig{
        .id = "test-container",
        .name = "test",
        .root_path = "/tmp/test-root/test-container",
        .hostname = "test-host",
        .resources = .{
            .cpu = .{
                .shares = 1024,
                .quota = 100000,
                .period = 100000,
            },
            .memory = .{
                .limit = 256 * 1024 * 1024, // 256MB
                .swap = 512 * 1024 * 1024,  // 512MB
            },
        },
    };
    try rt.interface.create(config);

    // Оновлення ресурсів
    const new_resources = types.Resources{
        .cpu = .{
            .shares = 2048,
            .quota = 200000,
            .period = 100000,
        },
        .memory = .{
            .limit = 512 * 1024 * 1024, // 512MB
            .swap = 1024 * 1024 * 1024, // 1GB
        },
    };
    try rt.interface.updateResources("test-container", new_resources);

    // Отримання статистики
    const stats = try rt.interface.stats("test-container");
    try testing.expect(stats.cpu.usage > 0);
    try testing.expect(stats.memory.usage > 0);
}

test "OCIRuntime error handling" {
    const allocator = testing.allocator;
    
    const rt = try oci.OCIRuntime.init(
        allocator,
        "/tmp/test-root",
        "/tmp/test-state",
    );
    defer rt.deinit();

    // Спроба роботи з неіснуючим контейнером
    try testing.expectError(error.NotFound, rt.interface.start("non-existent"));
    try testing.expectError(error.NotFound, rt.interface.stop("non-existent"));
    try testing.expectError(error.NotFound, rt.interface.delete("non-existent"));
    try testing.expectError(error.NotFound, rt.interface.state("non-existent"));
    try testing.expectError(error.NotFound, rt.interface.updateResources("non-existent", .{}));
    try testing.expectError(error.NotFound, rt.interface.stats("non-existent"));
}; 