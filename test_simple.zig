const std = @import("std");
const core = @import("src/core/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing modular architecture...\n", .{});

    // Test config loading
    var config_loader = core.ConfigLoader.init(allocator);
    var config = try config_loader.loadDefault();
    defer config.deinit();

    std.debug.print("✓ Config loaded successfully\n", .{});
    std.debug.print("  Runtime type: {}\n", .{config.runtime_type});
    std.debug.print("  Default runtime: {s}\n", .{config.default_runtime});
    std.debug.print("  Log level: {}\n", .{config.log_level});

    std.debug.print("✓ Core modules working correctly!\n", .{});
}
