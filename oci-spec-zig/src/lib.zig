const std = @import("std");

pub const runtime = @import("runtime/mod.zig");
pub const image = @import("image/mod.zig");
pub const distribution = @import("distribution/mod.zig");

pub fn packageInfo() std.builtin.TypeInfo.Struct {
    return .{
        .layout = .auto,
        .fields = &[_]std.builtin.TypeInfo.StructField{
            .{
                .name = "version",
                .type = []const u8,
                .default_value = "0.1.0",
                .is_comptime = true,
                .alignment = @alignOf([]const u8),
            },
        },
        .decls = &.{},
        .is_tuple = false,
    };
}

