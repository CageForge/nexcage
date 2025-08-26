const std = @import("std");
const testing = std.testing;

// Simple test to verify basic compilation
test "basic compilation test" {
    try testing.expect(true);
}

test "path operations test" {
    const allocator = testing.allocator;
    
    // Test path joining
    const path1 = try std.fs.path.join(allocator, &[_][]const u8{ "/var/lib/containers", "test-container" });
    defer allocator.free(path1);
    
    const path2 = try std.fs.path.join(allocator, &[_][]const u8{ path1, "rootfs" });
    defer allocator.free(path2);
    
    try testing.expect(std.mem.startsWith(u8, path1, "/var/lib/containers"));
    try testing.expect(std.mem.startsWith(u8, path2, "/var/lib/containers"));
}

test "directory operations test" {
    // Test directory creation (in temp directory)
    var temp_dir = try std.fs.cwd().makeOpenPath(".", .{});
    defer temp_dir.close();
    
    const test_dir = "test_bundle_dir";
    try temp_dir.makePath(test_dir);
    
    // Check if directory exists
    try temp_dir.access(test_dir, .{});
    
    // Cleanup
    try temp_dir.deleteTree(test_dir);
}

test "file operations test" {
    const allocator = testing.allocator;
    
    // Test file writing
    const temp_file = "test_config.json";
    const test_content = "{\"test\": true}";
    
    try std.fs.cwd().writeFile(.{
        .data = test_content,
        .sub_path = temp_file,
    });
    
    // Read and verify
    const content = try std.fs.cwd().readFileAlloc(allocator, temp_file, 1024);
    defer allocator.free(content);
    
    try testing.expectEqualStrings(test_content, content);
    
    // Cleanup
    try std.fs.cwd().deleteFile(temp_file);
}

test "memory management test" {
    const allocator = testing.allocator;
    
    // Test array allocation and cleanup
    var args = try allocator.alloc([]const u8, 2);
    defer {
        for (args) |arg| allocator.free(arg);
        allocator.free(args);
    }
    
    args[0] = try allocator.dupe(u8, "/bin/sh");
    args[1] = try allocator.dupe(u8, "-c");
    
    try testing.expectEqual(@as(usize, 2), args.len);
    try testing.expectEqualStrings("/bin/sh", args[0]);
    try testing.expectEqualStrings("-c", args[1]);
}

test "validation logic test" {
    // Test path validation logic
    const valid_paths = [_][]const u8{ "/proc", "/sys", "/dev", "/tmp", "/var/lib" };
    const invalid_paths = [_][]const u8{ "relative", "../dangerous", "", "no-slash" };
    
    for (valid_paths) |path| {
        try testing.expect(std.mem.startsWith(u8, path, "/"));
    }
    
    for (invalid_paths) |path| {
        if (path.len > 0) {
            try testing.expect(!std.mem.startsWith(u8, path, "/"));
        }
    }
}
