const std = @import("std");
const testing = std.testing;

// Basic tests that should always pass
test "basic math" {
    try testing.expect(2 + 2 == 4);
}

test "string operations" {
    const str = "hello";
    try testing.expect(str.len == 5);
}

test "array operations" {
    var arr = [_]u8{ 1, 2, 3, 4, 5 };
    try testing.expect(arr[0] == 1);
    try testing.expect(arr[4] == 5);
}

test "optionals" {
    var maybe_number: ?u32 = 42;
    try testing.expect(maybe_number.? == 42);
    
    maybe_number = null;
    try testing.expect(maybe_number == null);
}

test "error handling" {
    const result = error.SomeError;
    try testing.expectError(error.SomeError, result);
}

test "memory allocation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const memory = allocator.alloc(u8, 100) catch return;
    defer allocator.free(memory);
    
    try testing.expect(memory.len == 100);
}

test "string formatting" {
    const formatted = try std.fmt.allocPrint(testing.allocator, "Hello {s}!", .{"World"});
    defer testing.allocator.free(formatted);
    
    try testing.expectEqualStrings("Hello World!", formatted);
}

test "hash map operations" {
    var map = std.HashMap(u32, u32, std.hash_map.default_hash_fn(u32), std.hash_map.default_eql_fn(u32)).init(testing.allocator);
    defer map.deinit();
    
    try map.put(1, 100);
    try map.put(2, 200);
    
    try testing.expect(map.get(1).? == 100);
    try testing.expect(map.get(2).? == 200);
    try testing.expect(map.get(3) == null);
}

test "array list operations" {
    var list = std.ArrayList(u32).init(testing.allocator);
    defer list.deinit();
    
    try list.append(1);
    try list.append(2);
    try list.append(3);
    
    try testing.expect(list.items.len == 3);
    try testing.expect(list.items[0] == 1);
    try testing.expect(list.items[1] == 2);
    try testing.expect(list.items[2] == 3);
}

test "json parsing" {
    const json_str = "{\"name\": \"test\", \"value\": 42}";
    var parsed = std.json.parseFromSlice(std.json.Value, testing.allocator, json_str, .{}) catch return;
    defer parsed.deinit();
    
    try testing.expect(parsed.value.object.get("name").?.string.len == 4);
    try testing.expect(parsed.value.object.get("value").?.integer == 42);
}