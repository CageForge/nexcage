const std = @import("std");

pub const CodeGeneratorResponse = struct {
    file: []const File,

    pub const File = struct {
        name: []const u8,
        content: []const u8,
    };

    pub fn write(self: CodeGeneratorResponse, output_writer: anytype) !void {
        var buffer = std.ArrayList(u8).init(std.heap.page_allocator);
        defer buffer.deinit();
        const writer = buffer.writer();

        try writer.writeAll("{\n");
        try writer.writeAll("  \"file\": [\n");
        for (self.file, 0..) |f, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"name\": \"{s}\",\n", .{f.name});
            try writer.print("      \"content\": \"{s}\"\n", .{f.content});
            try writer.writeAll("    }");
            if (i < self.file.len - 1) {
                try writer.writeAll(",");
            }
            try writer.writeAll("\n");
        }
        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        try output_writer.writeAll(buffer.items);
    }
};
