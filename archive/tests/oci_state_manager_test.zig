const std = @import("std");
const testing = std.testing;
const state_manager = @import("../src/oci/state_manager.zig");
const logger_mod = @import("../src/common/logger.zig");

test "StateManager: create and save state" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-state";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try state_manager.StateManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Create state
    var state = try mgr.createState("test-container", 12345, "/tmp/test-bundle", "created");
    defer state.deinit(allocator);

    try testing.expectEqualStrings("1.0.2", state.ociVersion);
    try testing.expectEqualStrings("test-container", state.id);
    try testing.expectEqualStrings("created", state.status);
    try testing.expectEqual(@as(u32, 12345), state.vmid);
    try testing.expectEqual(@as(i32, 0), state.pid);

    // Save state
    try mgr.saveState(&state);

    // Verify state exists
    try testing.expect(try mgr.stateExists("test-container"));
}

test "StateManager: load state" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-state-load";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try state_manager.StateManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Create and save state
    var state1 = try mgr.createState("load-test", 54321, "/bundle", "created");
    defer state1.deinit(allocator);
    try mgr.saveState(&state1);

    // Load state
    var state2 = try mgr.loadState("load-test");
    defer state2.deinit(allocator);

    try testing.expectEqualStrings("load-test", state2.id);
    try testing.expectEqual(@as(u32, 54321), state2.vmid);
    try testing.expectEqualStrings("created", state2.status);
}

test "StateManager: update status" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-state-update";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try state_manager.StateManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Create initial state
    var state = try mgr.createState("update-test", 99999, "/bundle", "created");
    defer state.deinit(allocator);
    try mgr.saveState(&state);

    // Update status
    try mgr.updateStatus("update-test", "running", 1234);

    // Load and verify
    var updated_state = try mgr.loadState("update-test");
    defer updated_state.deinit(allocator);

    try testing.expectEqualStrings("running", updated_state.status);
    try testing.expectEqual(@as(i32, 1234), updated_state.pid);
}

test "StateManager: delete state" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-state-delete";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try state_manager.StateManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Create state
    var state = try mgr.createState("delete-test", 11111, "/bundle", "created");
    defer state.deinit(allocator);
    try mgr.saveState(&state);

    // Verify exists
    try testing.expect(try mgr.stateExists("delete-test"));

    // Delete
    try mgr.deleteState("delete-test");

    // Verify deleted
    try testing.expect(!try mgr.stateExists("delete-test"));
}

test "StateManager: list states" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-state-list";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try state_manager.StateManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Create multiple states
    var state1 = try mgr.createState("container-1", 100, "/bundle1", "created");
    defer state1.deinit(allocator);
    try mgr.saveState(&state1);

    var state2 = try mgr.createState("container-2", 101, "/bundle2", "running");
    defer state2.deinit(allocator);
    try mgr.saveState(&state2);

    var state3 = try mgr.createState("container-3", 102, "/bundle3", "stopped");
    defer state3.deinit(allocator);
    try mgr.saveState(&state3);

    // List all states
    const states = try mgr.listStates();
    defer {
        for (states) |*s| {
            s.deinit(allocator);
        }
        allocator.free(states);
    }

    try testing.expectEqual(@as(usize, 3), states.len);
}
