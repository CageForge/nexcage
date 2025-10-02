const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing ConfigLoader isolated functions...\n", .{});

    // Test ConfigLoader init
    var config_loader = core.ConfigLoader.init(allocator);
    std.debug.print("ConfigLoader init: OK\n", .{});

    // Test loadFromString with simple JSON
    const simple_json = "{\"runtime_type\": \"lxc\"}";
    var config = try config_loader.loadFromString(simple_json);
    std.debug.print("Config loadFromString: OK\n", .{});

    // Test deinit
    config.deinit();
    std.debug.print("Config deinit: OK\n", .{});

    std.debug.print("ConfigLoader isolated test completed successfully!\n", .{});
}
