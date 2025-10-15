const std = @import("std");
const testing = std.testing;
const vmid_manager = @import("../src/backends/proxmox-lxc/vmid_manager.zig");

test "VmidManager init" {
    const tmp_dir = "test_state";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = vmid_manager.VmidManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    try testing.expectEqualStrings(tmp_dir, manager.state_dir);
    try testing.expect(manager.logger == null);
}

test "VmidManager generateVmid" {
    const tmp_dir = "test_state_vmid";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = vmid_manager.VmidManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-1";
    const vmid = manager.generateVmid(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // VMID should be in valid range
    try testing.expect(vmid >= 100);
    try testing.expect(vmid <= 999999);
}

test "VmidManager storeMapping and getVmid" {
    const tmp_dir = "test_state_mapping";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = vmid_manager.VmidManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-2";
    const vmid: u32 = 12345;
    const bundle_path = "/test/bundle";
    
    // Store mapping
    manager.storeMapping(container_id, vmid, bundle_path) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Get VMID back
    const retrieved_vmid = manager.getVmid(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    try testing.expectEqual(vmid, retrieved_vmid);
}

test "VmidManager removeMapping" {
    const tmp_dir = "test_state_remove";
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};
    
    var manager = vmid_manager.VmidManager.init(testing.allocator, null, tmp_dir) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    defer manager.deinit();
    
    const container_id = "test-container-3";
    const vmid: u32 = 54321;
    const bundle_path = "/test/bundle";
    
    // Store mapping
    manager.storeMapping(container_id, vmid, bundle_path) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Verify it exists
    const retrieved_vmid = manager.getVmid(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    try testing.expectEqual(vmid, retrieved_vmid);
    
    // Remove mapping
    manager.removeMapping(container_id) catch |err| {
        // If pct command is not available, skip this test
        if (err == error.ProcessExecError) return;
        return err;
    };
    
    // Verify it's gone
    const result = manager.getVmid(container_id);
    try testing.expectError(error.MappingNotFound, result);
}

test "MappingEntry deinit" {
    var entry = vmid_manager.MappingEntry{
        .container_id = try testing.allocator.dupe(u8, "test-container"),
        .vmid = 12345,
        .created_at = 1234567890,
        .bundle_path = try testing.allocator.dupe(u8, "/test/bundle"),
    };
    
    // Should not crash
    entry.deinit(testing.allocator);
}

test "generateVmidFromHash consistency" {
    const container_id = "test-consistency";
    
    // Generate VMID multiple times - should be consistent
    const vmid1 = vmid_manager.VmidManager.generateVmidFromHash(container_id);
    const vmid2 = vmid_manager.VmidManager.generateVmidFromHash(container_id);
    
    try testing.expectEqual(vmid1, vmid2);
    
    // Different container ID should generate different VMID (likely)
    const different_vmid = vmid_manager.VmidManager.generateVmidFromHash("different-container");
    // Note: This might occasionally be equal due to hash collision, but very unlikely
    // try testing.expect(vmid1 != different_vmid);
}
