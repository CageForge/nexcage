const std = @import("std");
const testing = std.testing;

test "protoc-gen-grpc-zig generates correct code" {
    const allocator = testing.allocator;
    const response = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "protoc-gen-grpc-zig" },
        .cwd = ".",
    });
    defer allocator.free(response.stdout);
    defer allocator.free(response.stderr);

    try testing.expectEqualStrings("", response.stderr);
    try testing.expect(response.stdout.len > 0);
} 