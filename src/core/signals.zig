//! Signal names and numbers for `nexcage kill`.
const std = @import("std");

/// Highest signal number Linux accepts (SIGRTMAX)
pub const max: u8 = 64;

const Entry = struct {
    name: []const u8,
    number: u8,
};

// Names without the SIG prefix, as runc takes them
const table = [_]Entry{
    .{ .name = "HUP", .number = std.posix.SIG.HUP },
    .{ .name = "INT", .number = std.posix.SIG.INT },
    .{ .name = "QUIT", .number = std.posix.SIG.QUIT },
    .{ .name = "ILL", .number = std.posix.SIG.ILL },
    .{ .name = "TRAP", .number = std.posix.SIG.TRAP },
    .{ .name = "ABRT", .number = std.posix.SIG.ABRT },
    .{ .name = "IOT", .number = std.posix.SIG.IOT },
    .{ .name = "BUS", .number = std.posix.SIG.BUS },
    .{ .name = "FPE", .number = std.posix.SIG.FPE },
    .{ .name = "KILL", .number = std.posix.SIG.KILL },
    .{ .name = "USR1", .number = std.posix.SIG.USR1 },
    .{ .name = "SEGV", .number = std.posix.SIG.SEGV },
    .{ .name = "USR2", .number = std.posix.SIG.USR2 },
    .{ .name = "PIPE", .number = std.posix.SIG.PIPE },
    .{ .name = "ALRM", .number = std.posix.SIG.ALRM },
    .{ .name = "TERM", .number = std.posix.SIG.TERM },
    .{ .name = "STKFLT", .number = std.posix.SIG.STKFLT },
    .{ .name = "CHLD", .number = std.posix.SIG.CHLD },
    .{ .name = "CONT", .number = std.posix.SIG.CONT },
    .{ .name = "STOP", .number = std.posix.SIG.STOP },
    .{ .name = "TSTP", .number = std.posix.SIG.TSTP },
    .{ .name = "TTIN", .number = std.posix.SIG.TTIN },
    .{ .name = "TTOU", .number = std.posix.SIG.TTOU },
    .{ .name = "URG", .number = std.posix.SIG.URG },
    .{ .name = "XCPU", .number = std.posix.SIG.XCPU },
    .{ .name = "XFSZ", .number = std.posix.SIG.XFSZ },
    .{ .name = "VTALRM", .number = std.posix.SIG.VTALRM },
    .{ .name = "PROF", .number = std.posix.SIG.PROF },
    .{ .name = "WINCH", .number = std.posix.SIG.WINCH },
    .{ .name = "IO", .number = std.posix.SIG.IO },
    .{ .name = "POLL", .number = std.posix.SIG.POLL },
    .{ .name = "PWR", .number = std.posix.SIG.PWR },
    .{ .name = "SYS", .number = std.posix.SIG.SYS },
};

/// Parses a signal the way runc does: a number from 1 to `max`, or a name in
/// any case with or without the SIG prefix ("TERM", "SIGTERM", "sigterm").
/// Anything else, 0 included, is null.
pub fn parse(text: []const u8) ?u8 {
    if (text.len == 0) return null;
    if (std.ascii.isDigit(text[0])) {
        const number = std.fmt.parseInt(u8, text, 10) catch return null;
        return if (number >= 1 and number <= max) number else null;
    }

    var buf: [16]u8 = undefined;
    if (text.len > buf.len) return null;
    const upper = std.ascii.upperString(&buf, text);
    const bare = if (std.mem.startsWith(u8, upper, "SIG")) upper[3..] else upper;
    for (table) |entry| {
        if (std.mem.eql(u8, entry.name, bare)) return entry.number;
    }
    return null;
}

test "parse accepts names in any case, with or without SIG" {
    try std.testing.expectEqual(@as(?u8, 15), parse("SIGTERM"));
    try std.testing.expectEqual(@as(?u8, 15), parse("TERM"));
    try std.testing.expectEqual(@as(?u8, 15), parse("term"));
    try std.testing.expectEqual(@as(?u8, 9), parse("sigkill"));
    try std.testing.expectEqual(@as(?u8, 10), parse("Usr1"));
}

test "parse accepts numbers from 1 to 64" {
    try std.testing.expectEqual(@as(?u8, 1), parse("1"));
    try std.testing.expectEqual(@as(?u8, 15), parse("15"));
    try std.testing.expectEqual(@as(?u8, 64), parse("64"));
}

test "parse rejects everything else" {
    for ([_][]const u8{ "", "0", "65", "300", "-1", "+15", "SIG", "SIGRTMIN", "TERM;id", "BOGUS", "SIGTERMSIGTERMSIGTERM" }) |text| {
        try std.testing.expectEqual(@as(?u8, null), parse(text));
    }
}
