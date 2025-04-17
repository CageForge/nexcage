const std = @import("std");
const testing = std.testing;
const Container = @import("../src/oci/container.zig").Container;
const ContainerMetadata = @import("../src/oci/container.zig").ContainerMetadata;
const ContainerError = @import("../src/oci/container.zig").ContainerError;
const Spec = @import("../src/oci/spec.zig").Spec;
const State = @import("../src/oci/container_state.zig").State;

test "Container - initialization" {
    var allocator = testing.allocator;
    
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
    
    // Додаємо мітки та анотації
    try metadata.addLabel("version", "1.0");
    try metadata.addAnnotation("description", "Test container instance");
    
    // Створюємо контейнер
    var container = try Container.init(allocator, &metadata, &spec);
    defer container.deinit();
    
    // Перевіряємо початковий стан
    try testing.expectEqual(State.created, container.getState());
    try testing.expectEqualStrings("test-container", container.metadata.id);
    try testing.expectEqualStrings("1.0", container.metadata.labels.get("version").?);
    try testing.expectEqualStrings("Test container instance", container.metadata.annotations.get("description").?);
}

test "Container - lifecycle operations" {
    var allocator = testing.allocator;
    
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    var metadata = try ContainerMetadata.init(
        allocator,
        "lifecycle-test",
        "Lifecycle Test Container",
    );
    defer metadata.deinit();
    
    var container = try Container.init(allocator, &metadata, &spec);
    defer container.deinit();
    
    // Перевіряємо початковий стан
    try testing.expectEqual(State.created, container.getState());
    
    // Запускаємо контейнер
    try container.start();
    try testing.expectEqual(State.running, container.getState());
    
    // Встановлюємо PID
    try container.setPid(1234);
    try testing.expectEqual(@as(i32, 1234), container.getPid());
    
    // Зупиняємо контейнер
    try container.stop();
    try testing.expectEqual(State.stopped, container.getState());
    
    // Встановлюємо код виходу
    try container.setExitCode(0, "Success");
    
    // Видаляємо контейнер
    try container.delete();
    try testing.expectEqual(State.deleting, container.getState());
}

test "Container - error handling" {
    var allocator = testing.allocator;
    
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    var metadata = try ContainerMetadata.init(
        allocator,
        "error-test",
        "Error Test Container",
    );
    defer metadata.deinit();
    
    var container = try Container.init(allocator, &metadata, &spec);
    defer container.deinit();
    
    // Спроба зупинити контейнер, який не запущено
    try testing.expectError(ContainerError.InvalidState, container.stop());
    
    // Запускаємо контейнер
    try container.start();
    
    // Спроба запустити вже запущений контейнер
    try testing.expectError(ContainerError.AlreadyRunning, container.start());
    
    // Спроба видалити запущений контейнер
    try testing.expectError(ContainerError.StillRunning, container.delete());
    
    // Зупиняємо контейнер
    try container.stop();
    
    // Спроба зупинити вже зупинений контейнер
    try testing.expectError(ContainerError.NotRunning, container.stop());
}

test "Container - паузи та відновлення" {
    var allocator = testing.allocator;
    
    var spec = try Spec.init(allocator);
    defer spec.deinit();
    
    var metadata = try ContainerMetadata.init(
        allocator,
        "pause-test",
        "Pause Test Container",
    );
    defer metadata.deinit();
    
    var container = try Container.init(allocator, &metadata, &spec);
    defer container.deinit();
    
    // Спроба призупинити не запущений контейнер
    try testing.expectError(ContainerError.NotRunning, container.pause());
    
    // Запускаємо контейнер
    try container.start();
    
    // Призупиняємо контейнер
    try container.pause();
    try testing.expectEqual(State.paused, container.getState());
    
    // Спроба призупинити вже призупинений контейнер
    try testing.expectError(ContainerError.AlreadyPaused, container.pause());
    
    // Відновлюємо контейнер
    try container.resume();
    try testing.expectEqual(State.running, container.getState());
    
    // Спроба відновити не призупинений контейнер
    try testing.expectError(ContainerError.NotPaused, container.resume());
} 