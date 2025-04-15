const std = @import("std");
const protobuf = @import("protobuf");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var response = protobuf.CodeGeneratorResponse{
        .file = &.{
            .{
                .name = "runtime_service_grpc.zig",
                .content = "pub const RuntimeService = struct {};",
            },
        },
    };

    try response.write(std.io.getStdOut().writer());
}
