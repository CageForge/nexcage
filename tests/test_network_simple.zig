const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing NetworkConfig simple...\n", .{});

    // Test NetworkConfig init directly
    var network_config = core.types.NetworkConfig{
        .bridge = try allocator.dupe(u8, "lxcbr0"),
        .ip = null,
        .gateway = null,
    };
    std.debug.print("NetworkConfig init: OK\n", .{});

    // Test deinit
    network_config.deinit(allocator);
    std.debug.print("NetworkConfig deinit: OK\n", .{});

    std.debug.print("NetworkConfig simple test completed successfully!\n", .{});
}
