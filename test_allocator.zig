const std = @import("std");
const core = @import("core");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test ConfigLoader
    var config_loader = core.ConfigLoader.init(allocator);
    var config = try config_loader.loadDefault();
    defer config.deinit();

    std.debug.print("Config loaded successfully\n", .{});
}
