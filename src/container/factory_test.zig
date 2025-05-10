const std = @import("std");
const testing = std.testing;
const factory = @import("factory.zig");
const types = @import("../types.zig");

test "ContainerFactory - create LXC container" {
    const allocator = testing.allocator;

    var container_factory = factory.ContainerFactory.init(allocator);

    const config = factory.ContainerConfig{
        .type = .lxc,
        .name = "test-lxc",
        .id = "test-id",
        .bundle = "/path/to/bundle",
        .root = .{
            .path = "/path/to/root",
            .readonly = false,
        },
    };

    var container = try container_factory.createContainer(config);
    defer container.deinit();

    try testing.expectEqual(container, .lxc);

    const state = try container.state();
    try testing.expectEqual(state, .created);

    try container.start();
    const running_state = try container.state();
    try testing.expectEqual(running_state, .running);

    try container.stop();
    const stopped_state = try container.state();
    try testing.expectEqual(stopped_state, .stopped);
}

test "ContainerFactory - create VM container" {
    const allocator = testing.allocator;

    var container_factory = factory.ContainerFactory.init(allocator);

    const config = factory.ContainerConfig{
        .type = .vm,
        .name = "test-vm",
        .id = "test-id",
        .bundle = "/path/to/bundle",
        .root = .{
            .path = "/path/to/root",
            .readonly = false,
        },
    };

    var container = try container_factory.createContainer(config);
    defer container.deinit();

    try testing.expectEqual(container, .vm);

    const state = try container.state();
    try testing.expectEqual(state, .created);

    try container.start();
    const running_state = try container.state();
    try testing.expectEqual(running_state, .running);

    try container.stop();
    const stopped_state = try container.state();
    try testing.expectEqual(stopped_state, .stopped);
}

test "ContainerFactory - container lifecycle" {
    const allocator = testing.allocator;

    var container_factory = factory.ContainerFactory.init(allocator);

    // Тестуємо LXC контейнер
    {
        const config = factory.ContainerConfig{
            .type = .lxc,
            .name = "lifecycle-test-lxc",
            .id = "test-id",
            .bundle = "/path/to/bundle",
            .root = .{
                .path = "/path/to/root",
                .readonly = false,
            },
        };

        var container = try container_factory.createContainer(config);
        defer container.deinit();

        // Перевіряємо початковий стан
        try testing.expectEqual(try container.state(), .created);

        // Запускаємо контейнер
        try container.start();
        try testing.expectEqual(try container.state(), .running);

        // Зупиняємо контейнер
        try container.stop();
        try testing.expectEqual(try container.state(), .stopped);
    }

    // Тестуємо VM контейнер
    {
        const config = factory.ContainerConfig{
            .type = .vm,
            .name = "lifecycle-test-vm",
            .id = "test-id",
            .bundle = "/path/to/bundle",
            .root = .{
                .path = "/path/to/root",
                .readonly = false,
            },
        };

        var container = try container_factory.createContainer(config);
        defer container.deinit();

        // Перевіряємо початковий стан
        try testing.expectEqual(try container.state(), .created);

        // Запускаємо контейнер
        try container.start();
        try testing.expectEqual(try container.state(), .running);

        // Зупиняємо контейнер
        try container.stop();
        try testing.expectEqual(try container.state(), .stopped);
    }
}
