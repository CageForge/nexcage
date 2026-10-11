const std = @import("std");

/// Write `value` as a JSON string, escaping what JSON requires.
///
/// nexcage builds its state output by hand rather than through
/// std.json.Stringify, which wants a *Io.Writer; this takes any writer, so the
/// same helper serves the backend's state file and the `state` command.
///
/// DEL, the C1 controls U+0080 to U+009F, and U+2028 and U+2029 are written
/// as \u escapes too, though JSON allows them as they are. A reader decodes
/// either form to the same string, but whoever reads the file itself -- the
/// --log-format json log, with cat or tail -- had them reach the terminal,
/// which acts on CSI (U+009B) and NEL (U+0085) written as UTF-8 as it does on
/// ESC [ and a newline.
pub fn writeString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const c = value[i];
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                const rest = value[i + 1 ..];
                if (c < 0x20 or c == 0x7f) {
                    try writeEscape(writer, c);
                } else if (c == 0xc2 and rest.len >= 1 and rest[0] >= 0x80 and rest[0] <= 0x9f) {
                    try writeEscape(writer, rest[0]);
                    i += 1;
                } else if (c == 0xe2 and rest.len >= 2 and rest[0] == 0x80 and (rest[1] == 0xa8 or rest[1] == 0xa9)) {
                    try writeEscape(writer, @as(u16, 0x2000) | (rest[1] - 0x80));
                    i += 2;
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

/// Writes `\uXXXX` for the character `code`.
fn writeEscape(writer: anytype, code: u16) !void {
    const hex = "0123456789abcdef";
    var buf: [6]u8 = .{ '\\', 'u', 0, 0, 0, 0 };
    for (buf[2..], 0..) |*d, n| d.* = hex[(code >> @intCast(12 - 4 * n)) & 0xF];
    try writer.writeAll(&buf);
}

test "a terminal control or line separator in a JSON string is a \\u escape, and reads back the same" {
    // é and р end in 0xa9 and 0x80, as U+2029 and the C1 controls do; only
    // the characters themselves are escaped.
    const value = "a\u{9b}2J\u{85}b\u{2028}c\u{2029}\x7f\x1b \u{e9} \u{440}";
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeString(&w, value);
    try std.testing.expectEqualStrings("\"a\\u009b2J\\u0085b\\u2028c\\u2029\\u007f\\u001b \u{e9} \u{440}\"", w.buffered());
    const back = try std.json.parseFromSlice([]const u8, std.testing.allocator, w.buffered(), .{});
    defer back.deinit();
    try std.testing.expectEqualStrings(value, back.value);
}
