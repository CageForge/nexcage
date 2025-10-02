const std = @import("std");
const core = @import("core");

test "NetworkConfig deinit handles nulls" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var net = core.types.NetworkConfig{};
    net.deinit(allocator);
}

test "RuntimeOptions deinit frees optionals" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var opts = core.types.RuntimeOptions{
        .allocator = allocator,
        .command = .help,
        .container_id = try allocator.dupe(u8, "abc"),
        .image = try allocator.dupe(u8, "img"),
    };
    opts.deinit();
}

