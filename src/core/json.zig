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
    try writeStringContents(writer, value);
    try writer.writeByte('"');
}

/// A string someone else wrote -- a bundle's, a caller's -- as a message
/// quotes it with `{f}`: escaped as between the quotes of a JSON string, a
/// newline as \n and a NUL as \u0000, so that it cannot start a line of its
/// own, or move the cursor, in the log the engine keeps of the message. That
/// covers C0, DEL, and C1, which UTF-8 writes as 0xc2 then 0x80 to 0x9f:
/// U+009B is a terminal's CSI, as ESC [ is; and U+2028 and U+2029, which some
/// readers take for line breaks. A quote or a backslash is escaped too, so
/// the text cannot close the quotes a message puts round it. Both backends'
/// refusals of a bundle quote it this way, so the same text reads the same
/// whichever refused it.
pub const Quoted = struct {
    s: []const u8,

    pub fn format(self: Quoted, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try writeStringContents(w, self.s);
    }
};

pub fn quoted(s: []const u8) Quoted {
    return .{ .s = s };
}

/// What writeString writes between the quotes. A refusal quotes the bundle's
/// strings with it, through `quoted`, so that one can neither close the
/// quotes round it nor carry a control character into the message an engine
/// reads back from the --log-format json log and decodes.
pub fn writeStringContents(writer: anytype, value: []const u8) !void {
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
