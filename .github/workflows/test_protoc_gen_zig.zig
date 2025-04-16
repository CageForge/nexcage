const std = @import("std");
const testing = std.testing;

test "protoc-gen-zig generates correct code" {
    const allocator = testing.allocator;
    const response = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "protoc-gen-zig" },
        .cwd = ".",
    });
    defer allocator.free(response.stdout);
    defer allocator.free(response.stderr);

    try testing.expectEqualStrings("", response.stderr);
    try testing.expect(response.stdout.len > 0);
} 