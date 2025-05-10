const std = @import("std");
const testing = std.testing;
const container_state = @import("../src/oci/container_state.zig");

test "ContainerState - initialization" {
    const state = container_state.ContainerState.init();

    try testing.expectEqual(container_state.State.created, state.state);
    try testing.expect(state.created > 0);
    try testing.expect(state.started == null);
    try testing.expect(state.finished == null);
    try testing.expect(state.exit_code == null);
    try testing.expect(state.exit_reason == null);
    try testing.expect(state.pid == null);
}

test "ContainerState - valid transitions" {
    var state = container_state.ContainerState.init();

    // created -> running
    try testing.expect(state.canTransitionTo(.running));
    try state.transitionTo(.running);
    try testing.expectEqual(container_state.State.running, state.state);
    try testing.expect(state.started != null);

    // running -> paused
    try testing.expect(state.canTransitionTo(.paused));
    try state.transitionTo(.paused);
    try testing.expectEqual(container_state.State.paused, state.state);

    // paused -> running
    try testing.expect(state.canTransitionTo(.running));
    try state.transitionTo(.running);
    try testing.expectEqual(container_state.State.running, state.state);

    // running -> stopped
    try testing.expect(state.canTransitionTo(.stopped));
    try state.transitionTo(.stopped);
    try testing.expectEqual(container_state.State.stopped, state.state);
    try testing.expect(state.finished != null);

    // stopped -> deleting
    try testing.expect(state.canTransitionTo(.deleting));
    try state.transitionTo(.deleting);
    try testing.expectEqual(container_state.State.deleting, state.state);
}

test "ContainerState - invalid transitions" {
    var state = container_state.ContainerState.init();

    // created -> stopped (invalid)
    try testing.expect(!state.canTransitionTo(.stopped));
    try testing.expectError(container_state.StateError.InvalidStateTransition, state.transitionTo(.stopped));

    // created -> paused (invalid)
    try testing.expect(!state.canTransitionTo(.paused));
    try testing.expectError(container_state.StateError.InvalidStateTransition, state.transitionTo(.paused));

    // created -> running -> created (invalid)
    try state.transitionTo(.running);
    try testing.expect(!state.canTransitionTo(.created));
    try testing.expectError(container_state.StateError.InvalidStateTransition, state.transitionTo(.created));
}

test "ContainerState - already in state" {
    var state = container_state.ContainerState.init();

    try state.transitionTo(.running);
    try testing.expectError(container_state.StateError.AlreadyInState, state.transitionTo(.running));
}

test "ContainerState - process information" {
    var state = container_state.ContainerState.init();

    // Встановлюємо PID
    state.setPid(1234);
    try testing.expectEqual(@as(i32, 1234), state.pid.?);

    // Встановлюємо код виходу та причину
    state.setExit(137, "OOM killed");
    try testing.expectEqual(@as(i32, 137), state.exit_code.?);
    try testing.expectEqualStrings("OOM killed", state.exit_reason.?);
}

test "ContainerState - state cleanup on restart" {
    var state = container_state.ContainerState.init();

    // Запускаємо контейнер
    try state.transitionTo(.running);
    state.setPid(1234);

    // Зупиняємо з помилкою
    try state.transitionTo(.stopped);
    state.setExit(1, "Error occurred");

    // Запускаємо знову
    try state.transitionTo(.running);
    try testing.expect(state.exit_code == null);
    try testing.expect(state.exit_reason == null);
    try testing.expect(state.finished == null);
}

test "ContainerState - convert LxcStatus" {
    const test_cases = [_]struct {
        input: container_state.LxcStatus,
        expected: container_state.State,
    }{
        .{ .input = .created, .expected = container_state.State.created },
        .{ .input = .running, .expected = container_state.State.running },
        .{ .input = .paused, .expected = container_state.State.paused },
        .{ .input = .stopped, .expected = container_state.State.stopped },
        .{ .input = .deleting, .expected = container_state.State.deleting },
    };

    for (test_cases) |test_case| {
        const result = convertLxcStatus(test_case.input);
        try testing.expectEqual(test_case.expected, result);
    }
}
