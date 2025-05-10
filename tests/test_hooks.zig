const std = @import("std");
const testing = std.testing;
const hooks = @import("oci").hooks;
const types = @import("oci").types;

test "Hook creation and execution" {
    const allocator = testing.allocator;

    // Створюємо тестовий хук
    const hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "test" },
        &[_][]const u8{"TEST=1"},
        5,
    );
    defer hook.deinit(allocator);

    // Перевіряємо поля хука
    try testing.expectEqualStrings("/bin/echo", hook.path);
    try testing.expectEqual(@as(usize, 2), hook.args.len);
    try testing.expectEqual(@as(usize, 1), hook.env.len);
    try testing.expectEqual(@as(i64, 5), hook.timeout.?);

    // Виконуємо хук
    try hook.execute();
}

test "HookManager lifecycle" {
    const allocator = testing.allocator;

    var manager = hooks.HookManager.init(allocator);
    defer manager.deinit();

    // Створюємо тестові хуки
    const prestart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "prestart" },
        &[_][]const u8{},
        null,
    );

    const poststart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "poststart" },
        &[_][]const u8{},
        null,
    );

    const poststop_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "poststop" },
        &[_][]const u8{},
        null,
    );

    // Додаємо хуки
    try manager.addHook(.prestart, prestart_hook);
    try manager.addHook(.poststart, poststart_hook);
    try manager.addHook(.poststop, poststop_hook);

    // Перевіряємо кількість хуків
    try testing.expectEqual(@as(usize, 1), manager.prestart_hooks.items.len);
    try testing.expectEqual(@as(usize, 1), manager.poststart_hooks.items.len);
    try testing.expectEqual(@as(usize, 1), manager.poststop_hooks.items.len);

    // Виконуємо всі хуки
    try manager.executeHooks(.prestart);
    try manager.executeHooks(.poststart);
    try manager.executeHooks(.poststop);
}

test "Container hooks integration" {
    const allocator = testing.allocator;

    // Створюємо контейнер
    var metadata = try ContainerMetadata.init(
        allocator,
        "test-container",
        "Test Container",
    );
    defer metadata.deinit();

    var spec = try ContainerSpec.init(allocator);
    defer spec.deinit();

    var container = try Container.init(allocator, &metadata, &spec);
    defer container.deinit();

    // Створюємо та додаємо хуки
    const prestart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "prestart" },
        &[_][]const u8{},
        null,
    );

    const poststart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "poststart" },
        &[_][]const u8{},
        null,
    );

    const poststop_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{ "echo", "poststop" },
        &[_][]const u8{},
        null,
    );

    try container.addHook(.prestart, prestart_hook);
    try container.addHook(.poststart, poststart_hook);
    try container.addHook(.poststop, poststop_hook);

    // Перевіряємо виконання хуків при життєвому циклі контейнера
    try container.start(); // Має виконати prestart та poststart хуки
    try container.stop(); // Має виконати poststop хуки
}

test "HookExecutor initialization and execution" {
    const allocator = testing.allocator;

    var executor = try hooks.HookExecutor.init(allocator);
    defer executor.deinit();

    // Створюємо тестовий хук
    const test_hook = types.Hook{
        .path = "/bin/echo",
        .args = &[_][]const u8{"test"},
        .env = &[_][]const u8{"TEST=1"},
        .timeout = 5,
    };

    // Додаємо хук до prestart
    if (executor.hooks.prestart == null) {
        executor.hooks.prestart = &[_]types.Hook{test_hook};
    }

    // Виконуємо prestart хуки
    try executor.executePrestart("test-container");
}

test "HookExecutor error handling" {
    const allocator = testing.allocator;

    var executor = try hooks.HookExecutor.init(allocator);
    defer executor.deinit();

    // Створюємо хук з неіснуючим шляхом
    const invalid_hook = types.Hook{
        .path = "/nonexistent/binary",
        .args = null,
        .env = null,
        .timeout = null,
    };

    // Додаємо хук до poststart
    if (executor.hooks.poststart == null) {
        executor.hooks.poststart = &[_]types.Hook{invalid_hook};
    }

    // Перевіряємо, що виконання призводить до помилки
    try testing.expectError(
        hooks.HookError.ExecutionFailed,
        executor.executePoststart("test-container"),
    );
}

test "HookExecutor timeout handling" {
    const allocator = testing.allocator;

    var executor = try hooks.HookExecutor.init(allocator);
    defer executor.deinit();

    // Створюємо хук, який буде виконуватись довше за таймаут
    const slow_hook = types.Hook{
        .path = "/bin/sleep",
        .args = &[_][]const u8{"2"},
        .env = null,
        .timeout = 1,
    };

    // Додаємо хук до poststop
    if (executor.hooks.poststop == null) {
        executor.hooks.poststop = &[_]types.Hook{slow_hook};
    }

    // Перевіряємо, що виконання призводить до помилки таймауту
    try testing.expectError(
        hooks.HookError.TimeoutExceeded,
        executor.executePoststop("test-container"),
    );
}
