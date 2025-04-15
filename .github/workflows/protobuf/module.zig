const std = @import("std");

pub const CodeGeneratorResponse = struct {
    file: []const File,

    pub const File = struct {
        name: []const u8,
        content: []const u8,
    };

    pub fn write(self: CodeGeneratorResponse, writer: anytype) !void {
        // Write the number of files (field 1, repeated)
        for (self.file) |f| {
            // Write field tag (1 << 3 | 2 = 10)
            try writer.writeByte(10);

            // Write length of the file message
            const file_len = 2 + f.name.len + 2 + f.content.len;
            try writeVarint(writer, file_len);

            // Write name field (field 1, string)
            try writer.writeByte(10);
            try writeVarint(writer, f.name.len);
            try writer.writeAll(f.name);

            // Write content field (field 2, string)
            try writer.writeByte(18);
            try writeVarint(writer, f.content.len);
            try writer.writeAll(f.content);
        }
    }

    fn writeVarint(writer: anytype, value: usize) !void {
        var v = value;
        while (v >= 0x80) {
            const byte = @as(u8, @truncate((v & 0x7F) | 0x80));
            try writer.writeByte(byte);
            v >>= 7;
        }
        try writer.writeByte(@as(u8, @truncate(v)));
    }
};
