const std = @import("std");
const testing = std.testing;
const mapping = @import("../src/oci/mapping.zig");
const logger_mod = @import("../src/common/logger.zig");

test "MappingManager: generate VMID from hash" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-mapping";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try mapping.MappingManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Test VMID generation
    const vmid1 = try mgr.generateVmid("test-container-1");
    try testing.expect(vmid1 >= 100 and vmid1 <= 999999);

    // Same container ID should return same VMID
    const vmid2 = try mgr.generateVmid("test-container-1");
    try testing.expectEqual(vmid1, vmid2);

    // Different container ID should return different VMID (most likely)
    const vmid3 = try mgr.generateVmid("test-container-2");
    try testing.expect(vmid3 >= 100 and vmid3 <= 999999);
}

test "MappingManager: store and retrieve mapping" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-mapping-store";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try mapping.MappingManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Store mapping
    try mgr.storeMapping("test-container", 12345, "/tmp/test-bundle");

    // Retrieve mapping
    const vmid = try mgr.getVmid("test-container");
    try testing.expectEqual(@as(u32, 12345), vmid);

    // Remove mapping
    try mgr.removeMapping("test-container");

    // Should fail after removal
    const result = mgr.getVmid("test-container");
    try testing.expectError(error.MappingNotFound, result);
}

test "MappingManager: collision handling" {
    const allocator = testing.allocator;
    
    var logger = try logger_mod.Logger.init(allocator, .debug);
    defer logger.deinit();

    const state_dir = "/tmp/nexcage-test-collision";
    std.fs.cwd().makePath(state_dir) catch {};
    defer std.fs.cwd().deleteTree(state_dir) catch {};

    var mgr = try mapping.MappingManager.init(allocator, &logger, state_dir);
    defer mgr.deinit();

    // Generate multiple VMIDs
    const vmid1 = try mgr.generateVmid("container-1");
    try mgr.storeMapping("container-1", vmid1, "/bundle1");

    const vmid2 = try mgr.generateVmid("container-2");
    try mgr.storeMapping("container-2", vmid2, "/bundle2");

    const vmid3 = try mgr.generateVmid("container-3");
    try mgr.storeMapping("container-3", vmid3, "/bundle3");

    // All VMIDs should be unique
    try testing.expect(vmid1 != vmid2);
    try testing.expect(vmid1 != vmid3);
    try testing.expect(vmid2 != vmid3);
}
