const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic allocator usage
    const str = try allocator.dupe(u8, "hello");
    defer allocator.free(str);
    
    std.debug.print("String: {s}\n", .{str});
}
