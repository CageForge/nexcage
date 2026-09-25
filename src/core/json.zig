const std = @import("std");

/// Write `value` as a JSON string, escaping what JSON requires.
///
/// nexcage builds its state output by hand rather than through
/// std.json.Stringify, which wants a *Io.Writer; this takes any writer, so the
/// same helper serves the backend's state file and the `state` command.
pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    var buf: [6]u8 = .{ '\\', 'u', '0', '0', 0, 0 };
                    const hex = "0123456789abcdef";
                    buf[4] = hex[(c >> 4) & 0xF];
                    buf[5] = hex[c & 0xF];
                    try writer.writeAll(buf[0..]);
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}
