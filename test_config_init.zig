const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing Config.init...\n", .{});

    // Test Config.init directly
    var config = try core.Config.init(allocator, .lxc);
    std.debug.print("Config init: OK\n", .{});

    // Test deinit
    config.deinit();
    std.debug.print("Config deinit: OK\n", .{});

    std.debug.print("Config.init test completed successfully!\n", .{});
}
