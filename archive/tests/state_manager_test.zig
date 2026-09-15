const std = @import("std");
const testing = std.testing;
const state_manager = @import("../src/backends/proxmox-lxc/state_manager.zig");

test "StateManager init" {
    const tmp_dir = "test_state_manager";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = state_manager.StateManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    try testing.expectEqualStrings(tmp_dir, manager.state_dir);
    try testing.expect(manager.logger == null);
}

test "StateManager stateExists" {
    const tmp_dir = "test_state_exists";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = state_manager.StateManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container";
    
    // Initially should not exist
    const exists_before = manager.stateExists(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    try testing.expect(!exists_before);
    
    // Create state
    manager.createState(container_id, 12345, "/test/bundle") catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Now should exist
    const exists_after = manager.stateExists(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    try testing.expect(exists_after);
}

test "StateManager createState and loadState" {
    const tmp_dir = "test_state_create_load";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = state_manager.StateManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-create";
    const vmid: u32 = 12345;
    const bundle_path = "/test/bundle";
    
    // Create state
    manager.createState(container_id, vmid, bundle_path) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Load state
    var state = manager.loadState(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer state.deinit(testing.allocator);
    
    // Verify state values
    try testing.expectEqualStrings("1.0.2", state.ociVersion);
    try testing.expectEqualStrings(container_id, state.id);
    try testing.expectEqualStrings("created", state.status);
    try testing.expectEqual(@as(i32, 0), state.pid);
    try testing.expectEqualStrings(bundle_path, state.bundle);
    try testing.expectEqual(vmid, state.vmid);
    try testing.expect(state.created_at > 0);
}

test "StateManager updateState" {
    const tmp_dir = "test_state_update";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = state_manager.StateManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-update";
    const vmid: u32 = 12345;
    const bundle_path = "/test/bundle";
    
    // Create state
    manager.createState(container_id, vmid, bundle_path) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Update state
    manager.updateState(container_id, "running", 1234) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Load and verify updated state
    var state = manager.loadState(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer state.deinit(testing.allocator);
    
    try testing.expectEqualStrings("running", state.status);
    try testing.expectEqual(@as(i32, 1234), state.pid);
}

test "StateManager deleteState" {
    const tmp_dir = "test_state_delete";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = state_manager.StateManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-delete";
    const vmid: u32 = 12345;
    const bundle_path = "/test/bundle";
    
    // Create state
    manager.createState(container_id, vmid, bundle_path) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Verify it exists
    const exists_before = manager.stateExists(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    try testing.expect(exists_before);
    
    // Delete state
    manager.deleteState(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Verify it's gone
    const exists_after = manager.stateExists(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    try testing.expect(!exists_after);
}

test "ContainerState deinit" {
    var state = state_manager.ContainerState{
        .ociVersion = try testing.allocator.dupe(u8, "1.0.2"),
        .id = try testing.allocator.dupe(u8, "test-container"),
        .status = try testing.allocator.dupe(u8, "created"),
        .pid = 0,
        .bundle = try testing.allocator.dupe(u8, "/test/bundle"),
        .annotations = null,
        .vmid = 12345,
        .created_at = 1234567890,
    };
    
    // Should not crash
    state.deinit(testing.allocator);
}
