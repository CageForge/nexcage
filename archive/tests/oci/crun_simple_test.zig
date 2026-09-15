const std = @import("std");
const testing = std.testing;
const crun = @import("oci").crun;

test "CrunError types" {
    // Test that all error types are defined
    try testing.expect(crun.CrunError.ContainerCreateFailed != crun.CrunError.ContainerStartFailed);
    try testing.expect(crun.CrunError.ContainerDeleteFailed != crun.CrunError.ContainerRunFailed);
    try testing.expect(crun.CrunError.ContainerNotFound != crun.CrunError.InvalidConfiguration);
    try testing.expect(crun.CrunError.RuntimeError != crun.CrunError.OutOfMemory);
    try testing.expect(crun.CrunError.InvalidContainerId != crun.CrunError.InvalidBundlePath);
    try testing.expect(crun.CrunError.ContextInitFailed != crun.CrunError.ContainerLoadFailed);
}

test "ContainerState enum" {
    // Test that all states are defined
    try testing.expect(crun.ContainerState.created != crun.ContainerState.running);
    try testing.expect(crun.ContainerState.stopped != crun.ContainerState.paused);
    try testing.expect(crun.ContainerState.unknown != crun.ContainerState.created);
}

test "ContainerStatus struct" {
    const allocator = testing.allocator;

    var status = crun.ContainerStatus{
        .id = try allocator.dupe(u8, "test-container"),
        .state = crun.ContainerState.created,
        .pid = 12345,
        .exit_code = null,
        .created_at = try allocator.dupe(u8, "2025-08-26T10:00:00Z"),
        .started_at = null,
        .finished_at = null,
    };
    defer status.deinit(allocator);

    try testing.expectEqualStrings("test-container", status.id);
    try testing.expect(status.state == crun.ContainerState.created);
    try testing.expect(status.pid == 12345);
    try testing.expect(status.exit_code == null);
    if (status.created_at) |created_at| {
        try testing.expectEqualStrings("2025-08-26T10:00:00Z", created_at);
    }
    try testing.expect(status.started_at == null);
    try testing.expect(status.finished_at == null);
}
