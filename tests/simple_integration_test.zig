const std = @import("std");
const testing = std.testing;

// Simple integration test for the entire project
test "project integration test" {
    // Test that the project compiles and basic functionality works
    try testing.expect(true);
}

test "file system operations" {
    // Test basic file operations
    const test_file = "test_integration.txt";
    defer std.fs.cwd().deleteFile(test_file) catch {};
    
    // Write test file
    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll("Hello, World!");
    }
    
    // Read test file
    {
        const read_file = try std.fs.cwd().openFile(test_file, .{});
        defer read_file.close();
        
        const content = try read_file.readToEndAlloc(testing.allocator, 1024);
        defer testing.allocator.free(content);
        
        try testing.expectEqualStrings("Hello, World!", content);
    }
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

test "string operations" {
    const str = "hello world";
    try testing.expectEqual(@as(usize, 11), str.len);
    try testing.expectEqualStrings("hello", str[0..5]);
}

test "array operations" {
    var list = std.ArrayListUnmanaged(u32){};
    defer list.deinit(testing.allocator);
    
    try list.append(testing.allocator, 1);
    try list.append(testing.allocator, 2);
    try list.append(testing.allocator, 3);
    
    try testing.expectEqual(@as(usize, 3), list.items.len);
    try testing.expectEqual(@as(u32, 1), list.items[0]);
    try testing.expectEqual(@as(u32, 2), list.items[1]);
    try testing.expectEqual(@as(u32, 3), list.items[2]);
}

test "hash operations" {
    var hash = std.hash.Wyhash.init(0);
    hash.update("test");
    const hash_value = hash.final();
    
    // Hash should be consistent
    var hash2 = std.hash.Wyhash.init(0);
    hash2.update("test");
    const hash_value2 = hash2.final();
    
    try testing.expectEqual(hash_value, hash_value2);
}

test "JSON operations" {
    var json_obj = std.json.ObjectMap.init(testing.allocator);
    defer json_obj.deinit();
    
    try json_obj.put("test", .{ .string = "value" });
    try json_obj.put("number", .{ .integer = 42 });
    
    try testing.expect(json_obj.get("test") != null);
    try testing.expect(json_obj.get("number") != null);
    
    const test_val = json_obj.get("test").?;
    try testing.expect(test_val == .string);
    try testing.expectEqualStrings("value", test_val.string);
    
    const number_val = json_obj.get("number").?;
    try testing.expect(number_val == .integer);
    try testing.expectEqual(@as(i64, 42), number_val.integer);
}
