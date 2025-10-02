const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing Config without JSON...\n", .{});

    // Test ConfigLoader init
    var config_loader = core.ConfigLoader.init(allocator);
    std.debug.print("ConfigLoader init: OK\n", .{});

    // Test parseConfig directly with empty object
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, "{}", .{}) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        return err;
    };
    defer parsed.deinit();

    std.debug.print("JSON parse: OK\n", .{});

    // Test parseConfig
    var config = try config_loader.parseConfig(parsed.value);
    std.debug.print("Config parseConfig: OK\n", .{});

    // Test deinit
    config.deinit();
    std.debug.print("Config deinit: OK\n", .{});

    std.debug.print("Config no JSON test completed successfully!\n", .{});
}
