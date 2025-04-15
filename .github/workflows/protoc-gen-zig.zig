const std = @import("std");
const protobuf = @import("protobuf");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    var buffer: [8192]u8 = undefined;
    _ = try stdin.reader().read(&buffer);

    var response = protobuf.CodeGeneratorResponse{
        .file = &[_]protobuf.CodeGeneratorResponse.File{
            .{
                .name = "runtime_service.zig",
                .content = "const std = @import(\"std\");\npub const RuntimeService = struct {\n    pub const Service = struct {\n        pub const Version = struct {\n            version: []const u8,\n        };\n    };\n};\n",
            },
        },
    };

    try response.write(stdout.writer());
} 