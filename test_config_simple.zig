const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing ConfigLoader simple...\n", .{});

    // Test ConfigLoader init
    var config_loader = core.ConfigLoader.init(allocator);
    std.debug.print("ConfigLoader init: OK\n", .{});

    // Test loadDefault (this will try to load from files, then fall back to default)
    var config = try config_loader.loadDefault();
    std.debug.print("Config loadDefault: OK\n", .{});

    // Test deinit
    config.deinit();
    std.debug.print("Config deinit: OK\n", .{});

    std.debug.print("ConfigLoader simple test completed successfully!\n", .{});
}
