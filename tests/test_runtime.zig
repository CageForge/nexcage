const std = @import("std");
const testing = std.testing;
const Runtime = @import("../src/oci/runtime.zig").Runtime;
const RuntimeError = @import("../src/oci/runtime.zig").RuntimeError;
const Container = @import("../src/oci/container.zig").Container;
const ContainerMetadata = @import("../src/oci/container.zig").ContainerMetadata;
const Spec = @import("../src/oci/spec.zig").Spec;
const State = @import("../src/oci/container_state.zig").State;
const proxmox = @import("../src/proxmox.zig");

test "Runtime - створення та видалення контейнера" {
    var allocator = testing.allocator;
    
    // Створюємо клієнт Proxmox
    var proxmox_client = try proxmox.ProxmoxClient.init(allocator);
    defer proxmox_client.deinit();
    
    // Створюємо рантайм
    var runtime = try Runtime.init(allocator, &proxmox_client);
    defer runtime.deinit();
    
    // Створюємо специфікацію
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    // Створюємо метадані
    var metadata = try ContainerMetadata.init(
        allocator,
        "test-container",
        "Test Container",
    );
    defer metadata.deinit();
    
    // Створюємо контейнер
    var container = try runtime.createContainer(&metadata, &spec);
    
    // Перевіряємо що контейнер створено
    try testing.expectEqual(State.created, container.getState());
    
    // Видаляємо контейнер
    try runtime.deleteContainer("test-container");
    
    // Перевіряємо що контейнер видалено
    try testing.expectError(RuntimeError.NotFound, runtime.getContainer("test-container"));
}

test "Runtime - життєвий цикл контейнера" {
    var allocator = testing.allocator;
    
    var proxmox_client = try proxmox.ProxmoxClient.init(allocator);
    defer proxmox_client.deinit();
    
    var runtime = try Runtime.init(allocator, &proxmox_client);
    defer runtime.deinit();
    
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    var metadata = try ContainerMetadata.init(
        allocator,
        "lifecycle-test",
        "Lifecycle Test Container",
    );
    defer metadata.deinit();
    
    // Створюємо контейнер
    var container = try runtime.createContainer(&metadata, &spec);
    try testing.expectEqual(State.created, container.getState());
    
    // Запускаємо контейнер
    try runtime.startContainer("lifecycle-test");
    try testing.expectEqual(State.running, container.getState());
    
    // Зупиняємо контейнер
    try runtime.stopContainer("lifecycle-test");
    try testing.expectEqual(State.stopped, container.getState());
    
    // Видаляємо контейнер
    try runtime.deleteContainer("lifecycle-test");
    try testing.expectError(RuntimeError.NotFound, runtime.getContainer("lifecycle-test"));
}

test "Runtime - список контейнерів" {
    var allocator = testing.allocator;
    
    var proxmox_client = try proxmox.ProxmoxClient.init(allocator);
    defer proxmox_client.deinit();
    
    var runtime = try Runtime.init(allocator, &proxmox_client);
    defer runtime.deinit();
    
    // Створюємо кілька контейнерів
    var spec1 = try Spec.init(allocator);
    defer spec1.deinit();
    
    var metadata1 = try ContainerMetadata.init(
        allocator,
        "container-1",
        "Container 1",
    );
    defer metadata1.deinit();
    
    var spec2 = try Spec.init(allocator);
    defer spec2.deinit();
    
    var metadata2 = try ContainerMetadata.init(
        allocator,
        "container-2",
        "Container 2",
    );
    defer metadata2.deinit();
    
    _ = try runtime.createContainer(&metadata1, &spec1);
    _ = try runtime.createContainer(&metadata2, &spec2);
    
    // Отримуємо список контейнерів
    var containers = try runtime.listContainers();
    defer containers.deinit();
    
    // Перевіряємо кількість контейнерів
    try testing.expectEqual(@as(usize, 2), containers.items.len);
    
    // Перевіряємо ID контейнерів
    try testing.expectEqualStrings("container-1", containers.items[0].metadata.id);
    try testing.expectEqualStrings("container-2", containers.items[1].metadata.id);
}

test "Runtime - обробка помилок" {
    var allocator = testing.allocator;
    
    var proxmox_client = try proxmox.ProxmoxClient.init(allocator);
    defer proxmox_client.deinit();
    
    var runtime = try Runtime.init(allocator, &proxmox_client);
    defer runtime.deinit();
    
    // Спроба отримати неіснуючий контейнер
    try testing.expectError(RuntimeError.NotFound, runtime.getContainer("non-existent"));
    
    // Спроба запустити неіснуючий контейнер
    try testing.expectError(RuntimeError.NotFound, runtime.startContainer("non-existent"));
    
    // Спроба зупинити неіснуючий контейнер
    try testing.expectError(RuntimeError.NotFound, runtime.stopContainer("non-existent"));
    
    // Спроба видалити неіснуючий контейнер
    try testing.expectError(RuntimeError.NotFound, runtime.deleteContainer("non-existent"));
    
    // Створюємо контейнер для тестування дублікатів
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    var metadata = try ContainerMetadata.init(
        allocator,
        "duplicate-test",
        "Duplicate Test Container",
    );
    defer metadata.deinit();
    
    _ = try runtime.createContainer(&metadata, &spec);
    
    // Спроба створити контейнер з існуючим ID
    try testing.expectError(RuntimeError.CreateError, runtime.createContainer(&metadata, &spec));
} 