const std = @import("std");
const testing = std.testing;
const oci = @import("oci");
const state = oci.state;
const types = oci.types;

test "Container state initialization" {
    const allocator = testing.allocator;

    var container_state = try state.ContainerState.init(
        allocator,
        "test-container",
        .created,
        1234,
        "/run/container/test-container",
    );
    defer container_state.deinit();

    try testing.expectEqualStrings("test-container", container_state.id);
    try testing.expectEqual(state.Status.created, container_state.status);
    try testing.expectEqual(@as(i32, 1234), container_state.pid);
    try testing.expectEqualStrings("/run/container/test-container", container_state.bundle);
}

test "Container state transitions" {
    const allocator = testing.allocator;

    var container_state = try state.ContainerState.init(
        allocator,
        "test-container",
        .created,
        1234,
        "/run/container/test-container",
    );
    defer container_state.deinit();

    // Перевіряємо перехід created -> running
    try container_state.transition(.running);
    try testing.expectEqual(state.Status.running, container_state.status);

    // Перевіряємо перехід running -> stopped
    try container_state.transition(.stopped);
    try testing.expectEqual(state.Status.stopped, container_state.status);

    // Перевіряємо перехід stopped -> deleted
    try container_state.transition(.deleted);
    try testing.expectEqual(state.Status.deleted, container_state.status);
}

test "Invalid state transitions" {
    const allocator = testing.allocator;

    var container_state = try state.ContainerState.init(
        allocator,
        "test-container",
        .created,
        1234,
        "/run/container/test-container",
    );
    defer container_state.deinit();

    // Не можна перейти з created в stopped
    try testing.expectError(
        error.InvalidStateTransition,
        container_state.transition(.stopped),
    );

    // Переходимо в running
    try container_state.transition(.running);

    // Не можна перейти з running в created
    try testing.expectError(
        error.InvalidStateTransition,
        container_state.transition(.created),
    );

    // Переходимо в stopped
    try container_state.transition(.stopped);

    // Не можна перейти з stopped в running
    try testing.expectError(
        error.InvalidStateTransition,
        container_state.transition(.running),
    );
}

test "Container state serialization" {
    const allocator = testing.allocator;

    var container_state = try state.ContainerState.init(
        allocator,
        "test-container",
        .running,
        1234,
        "/run/container/test-container",
    );
    defer container_state.deinit();

    // Серіалізуємо стан
    const json = try container_state.toJson(allocator);
    defer allocator.free(json);

    // Десеріалізуємо стан
    var parsed_state = try state.ContainerState.fromJson(allocator, json);
    defer parsed_state.deinit();

    // Перевіряємо що всі поля збереглися
    try testing.expectEqualStrings(container_state.id, parsed_state.id);
    try testing.expectEqual(container_state.status, parsed_state.status);
    try testing.expectEqual(container_state.pid, parsed_state.pid);
    try testing.expectEqualStrings(container_state.bundle, parsed_state.bundle);
}

test "Container state with annotations" {
    const allocator = testing.allocator;

    var container_state = try state.ContainerState.init(
        allocator,
        "test-container",
        .created,
        1234,
        "/run/container/test-container",
    );
    defer container_state.deinit();

    // Додаємо анотації
    try container_state.addAnnotation("com.example.key1", "value1");
    try container_state.addAnnotation("com.example.key2", "value2");

    // Перевіряємо наявність анотацій
    try testing.expectEqualStrings(
        "value1",
        container_state.getAnnotation("com.example.key1") orelse return error.AnnotationNotFound,
    );
    try testing.expectEqualStrings(
        "value2",
        container_state.getAnnotation("com.example.key2") orelse return error.AnnotationNotFound,
    );

    // Видаляємо анотацію
    try container_state.removeAnnotation("com.example.key1");
    try testing.expect(container_state.getAnnotation("com.example.key1") == null);

    // Оновлюємо анотацію
    try container_state.addAnnotation("com.example.key2", "new_value");
    try testing.expectEqualStrings(
        "new_value",
        container_state.getAnnotation("com.example.key2") orelse return error.AnnotationNotFound,
    );
}
