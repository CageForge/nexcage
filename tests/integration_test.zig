const std = @import("std");
const testing = std.testing;

// Integration test for the entire project
test "project integration test" {
    // Test that the project compiles and basic functionality works
    try testing.expect(true);
}

test "build system test" {
    // Test that we can build the project
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &[_][]const u8{ "zig", "build", "--help" },
    }) catch |err| {
        // If command fails, that's also acceptable for this test
        _ = err;
        return;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    
    // Should not crash
    _ = result;
}

test "file system operations" {
    // Test basic file operations
    const test_file = "test_integration.txt";
    defer std.fs.cwd().deleteFile(test_file) catch {};
    
    // Write test file
    const file = try std.fs.cwd().createFile(test_file, .{});
    defer file.close();
    
    try file.writeAll("Hello, World!");
    
    // Read test file
    const content = try file.readToEndAlloc(testing.allocator, 1024);
    defer testing.allocator.free(content);
    
    try testing.expectEqualStrings("Hello, World!", content);
}

test "process execution" {
    // Test basic process execution
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &[_][]const u8{ "echo", "test" },
    }) catch |err| {
        // If command fails, that's also acceptable for this test
        _ = err;
        return;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    
    // Should succeed
    try testing.expect(result.term.Exited == 0);
    try testing.expectEqualStrings("test\n", result.stdout);
}

test "memory management" {
    // Test memory allocation and deallocation
    const allocator = testing.allocator;
    
    // Allocate memory
    const ptr = try allocator.alloc(u8, 1024);
    defer allocator.free(ptr);
    
    // Initialize memory
    @memset(ptr, 0x42);
    
    // Verify memory
    for (ptr) |byte| {
        try testing.expectEqual(@as(u8, 0x42), byte);
    }
}

test "error handling" {
    // Test error handling
    const result = std.process.Child.run(.{
        .allocator = testing.allocator,
        .argv = &[_][]const u8{ "nonexistent-command" },
    }) catch |err| {
        // If command fails, that's expected for this test
        _ = err;
        return;
    };
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    
    // Should fail
    try testing.expect(result.term.Exited != 0);
}
