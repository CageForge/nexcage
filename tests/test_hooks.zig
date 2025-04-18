const std = @import("std");
const testing = std.testing;
const hooks = @import("oci").hooks;

test "Hook creation and execution" {
    const allocator = testing.allocator;
    
    // Створюємо тестовий хук
    const hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{"echo", "test"},
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
        &[_][]const u8{"echo", "prestart"},
        &[_][]const u8{},
        null,
    );
    
    const poststart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{"echo", "poststart"},
        &[_][]const u8{},
        null,
    );
    
    const poststop_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{"echo", "poststop"},
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
        &[_][]const u8{"echo", "prestart"},
        &[_][]const u8{},
        null,
    );
    
    const poststart_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{"echo", "poststart"},
        &[_][]const u8{},
        null,
    );
    
    const poststop_hook = try hooks.Hook.init(
        allocator,
        "/bin/echo",
        &[_][]const u8{"echo", "poststop"},
        &[_][]const u8{},
        null,
    );
    
    try container.addHook(.prestart, prestart_hook);
    try container.addHook(.poststart, poststart_hook);
    try container.addHook(.poststop, poststop_hook);
    
    // Перевіряємо виконання хуків при життєвому циклі контейнера
    try container.start();  // Має виконати prestart та poststart хуки
    try container.stop();   // Має виконати poststop хуки
}; 