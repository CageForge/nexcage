const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing LogContext...\n", .{});

    // Test LogContext init
    var logger = core.LogContext.init(allocator, std.io.getStdOut().writer(), .info, "test");
    std.debug.print("LogContext init: OK\n", .{});

    // Test deinit
    logger.deinit();
    std.debug.print("LogContext deinit: OK\n", .{});

    std.debug.print("LogContext test completed successfully!\n", .{});
}
