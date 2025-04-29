const std = @import("std");
const testing = std.testing;
const oci = @import("oci");
const runtime = oci.runtime;
const types = oci.types;

test "Runtime initialization" {
    const allocator = testing.allocator;
    
    var rt = try runtime.Runtime.init(allocator);
    defer rt.deinit();
    
    try testing.expect(rt.containers.count() == 0);
}

test "Runtime container lifecycle" {
    const allocator = testing.allocator;
    
    var rt = try runtime.Runtime.init(allocator);
    defer rt.deinit();
    
    // Створюємо тестовий контейнер
    const container_id = "test-container";
    const bundle_path = "/tmp/bundle";
    
    try rt.createContainer(container_id, bundle_path, null);
    
    // Перевіряємо що контейнер створено
    try testing.expect(rt.containers.count() == 1);
    try testing.expect(rt.containers.contains(container_id));
    
    // Отримуємо стан контейнера
    const state = try rt.state(container_id);
    try testing.expectEqual(state.status, .created);
    
    // Запускаємо контейнер
    try rt.startContainer(container_id);
    const running_state = try rt.state(container_id);
    try testing.expectEqual(running_state.status, .running);
    
    // Зупиняємо контейнер
    try rt.stopContainer(container_id);
    const stopped_state = try rt.state(container_id);
    try testing.expectEqual(stopped_state.status, .stopped);
    
    // Видаляємо контейнер
    try rt.deleteContainer(container_id);
    try testing.expect(rt.containers.count() == 0);
}

test "Runtime error handling" {
    const allocator = testing.allocator;
    
    var rt = try runtime.Runtime.init(allocator);
    defer rt.deinit();
    
    // Перевіряємо помилку при спробі отримати стан неіснуючого контейнера
    try testing.expectError(
        error.ContainerNotFound,
        rt.state("nonexistent"),
    );
    
    // Перевіряємо помилку при спробі запустити неіснуючий контейнер
    try testing.expectError(
        error.ContainerNotFound,
        rt.startContainer("nonexistent"),
    );
    
    // Створюємо контейнер
    try rt.createContainer("test", "/tmp/bundle", null);
    
    // Перевіряємо помилку при спробі створити контейнер з існуючим ID
    try testing.expectError(
        error.ContainerAlreadyExists,
        rt.createContainer("test", "/tmp/bundle", null),
    );
    
    // Запускаємо контейнер
    try rt.startContainer("test");
    
    // Перевіряємо помилку при спробі запустити вже запущений контейнер
    try testing.expectError(
        error.ContainerAlreadyRunning,
        rt.startContainer("test"),
    );
}

test "Runtime container kill" {
    const allocator = testing.allocator;
    
    var rt = try runtime.Runtime.init(allocator);
    defer rt.deinit();
    
    // Створюємо та запускаємо контейнер
    try rt.createContainer("test", "/tmp/bundle", null);
    try rt.startContainer("test");
    
    // Надсилаємо сигнал SIGTERM
    try rt.killContainer("test", .sigterm);
    
    // Перевіряємо що контейнер зупинено
    const state = try rt.state("test");
    try testing.expectEqual(state.status, .stopped);
    
    // Перевіряємо помилку при спробі надіслати сигнал зупиненому контейнеру
    try testing.expectError(
        error.ContainerNotRunning,
        rt.killContainer("test", .sigterm),
    );
} 