const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing NetworkConfig parsing...\n", .{});

    // Test ConfigLoader init
    var config_loader = core.ConfigLoader.init(allocator);
    std.debug.print("ConfigLoader init: OK\n", .{});

    // Test parseNetworkConfig with empty object
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, "{}", .{}) catch |err| {
        std.debug.print("JSON parse error: {}\n", .{err});
        return err;
    };
    defer parsed.deinit();

    std.debug.print("JSON parse: OK\n", .{});

    // Test parseNetworkConfig
    var network_config = try config_loader.parseNetworkConfig(parsed.value);
    std.debug.print("NetworkConfig parseNetworkConfig: OK\n", .{});

    // Test deinit
    network_config.deinit(allocator);
    std.debug.print("NetworkConfig deinit: OK\n", .{});

    std.debug.print("NetworkConfig test completed successfully!\n", .{});
}
