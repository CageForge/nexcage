const std = @import("std");
const protobuf = @import("protobuf");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input);

    const response = protobuf.CodeGeneratorResponse{
        .file = &[_]protobuf.CodeGeneratorResponse.File{
            .{
                .name = "runtime_service_grpc.zig",
                .content = 
                \\const std = @import("std");
                \\const protobuf = @import("protobuf");
                \\
                \\pub const RuntimeService = struct {
                \\    pub fn version(self: *RuntimeService) ![]const u8 {
                \\        return "1.0.0";
                \\    }
                \\};
                ,
            },
        },
    };

    try response.writeTo(std.io.getStdOut().writer());
}
