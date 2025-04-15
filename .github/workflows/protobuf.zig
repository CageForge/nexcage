const std = @import("std");

pub const CodeGeneratorResponse = struct {
    file: []const File,

    pub const File = struct {
        name: []const u8,
        content: []const u8,
    };

    pub fn write(self: CodeGeneratorResponse, writer: anytype) !void {
        _ = self;
        _ = writer;
    }
}; 