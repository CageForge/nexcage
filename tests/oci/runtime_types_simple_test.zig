const std = @import("std");
const testing = std.testing;

// Simple test to verify basic compilation
test "basic compilation test" {
    try testing.expect(true);
}

test "memory allocation test" {
    const allocator = testing.allocator;
    
    // Test basic memory allocation
    const test_string = try allocator.dupe(u8, "test");
    defer allocator.free(test_string);
    
    try testing.expectEqualStrings("test", test_string);
}

test "string operations test" {
    const allocator = testing.allocator;
    
    // Test string operations
    const path1 = try allocator.dupe(u8, "/var/lib/containers");
    defer allocator.free(path1);
    
    const path2 = try allocator.dupe(u8, "/rootfs");
    defer allocator.free(path2);
    
    try testing.expect(std.mem.startsWith(u8, path1, "/"));
    try testing.expect(std.mem.startsWith(u8, path2, "/"));
}

test "array operations test" {
    const allocator = testing.allocator;
    
    // Test array operations
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

test "error handling test" {
    // Test error handling
    const result = std.mem.indexOf(u8, "test", "x");
    try testing.expect(result == null);
    
    const result2 = std.mem.indexOf(u8, "test", "t");
    try testing.expect(result2 != null);
    try testing.expect(result2.? == 0);
}

test "validation logic test" {
    // Test validation logic
    const valid_paths = [_][]const u8{ "/proc", "/sys", "/dev", "/tmp" };
    const invalid_paths = [_][]const u8{ "relative", "../dangerous", "" };
    
    for (valid_paths) |path| {
        try testing.expect(std.mem.startsWith(u8, path, "/"));
    }
    
    for (invalid_paths) |path| {
        if (path.len > 0) {
            try testing.expect(!std.mem.startsWith(u8, path, "/"));
        }
    }
}
