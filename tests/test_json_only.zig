const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing JSON parsing only...\n", .{});

    // Test JSON parsing
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, "{}", .{}) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        return err;
    };
    defer parsed.deinit();

    std.debug.print("JSON parse: OK\n", .{});

    // Test accessing the value
    _ = parsed.value;
    std.debug.print("JSON value access: OK\n", .{});

    std.debug.print("JSON only test completed successfully!\n", .{});
}
