const std = @import("std");
const testing = std.testing;
const core = @import("core");

test "validateContainerName valid names" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Valid names
    try testing.expect(core.validation.validateContainerName(allocator, "test-container"));
    try testing.expect(core.validation.validateContainerName(allocator, "container123"));
    try testing.expect(core.validation.validateContainerName(allocator, "my-container-name"));
    try testing.expect(core.validation.validateContainerName(allocator, "a"));
    try testing.expect(core.validation.validateContainerName(allocator, "container-name-123"));
}

test "validateContainerName invalid names" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Invalid names
    try testing.expect(!core.validation.validateContainerName(allocator, ""));
    try testing.expect(!core.validation.validateContainerName(allocator, "container/name"));
    try testing.expect(!core.validation.validateContainerName(allocator, "container@name"));
    try testing.expect(!core.validation.validateContainerName(allocator, " container"));
    try testing.expect(!core.validation.validateContainerName(allocator, "container "));
}

test "validateContainerName length limits" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Maximum length (assuming 255 or similar)
    var long_name = std.ArrayList(u8).init(allocator);
    defer long_name.deinit();
    try long_name.writer().print("a", .{});
    for (0..250) |_| {
        try long_name.append('a');
    }
    
    // Should accept reasonable length
    try testing.expect(core.validation.validateContainerName(allocator, long_name.items));
}

test "resolvePath with absolute path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const absolute = "/absolute/path";
    const resolved = try core.validation.resolvePath(allocator, absolute);
    defer allocator.free(resolved);
    
    try testing.expectEqualStrings("/absolute/path", resolved);
}

test "resolvePath with relative path" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Relative paths should be resolved (actual resolution depends on implementation)
    const relative = "relative/path";
    const resolved = try core.validation.resolvePath(allocator, relative);
    defer allocator.free(resolved);
    
    // Should return a non-empty resolved path
    try testing.expect(resolved.len > 0);
}

