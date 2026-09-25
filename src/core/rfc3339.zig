const std = @import("std");

/// Format epoch seconds as RFC 3339, which is what a Go caller's time.Time
/// unmarshals. containerd reads the runtime's JSON log to report why a create
/// failed, and answers "Time.UnmarshalJSON: input is not a JSON string" to a
/// numeric timestamp — so the field has to be a quoted date, not a number.
///
/// Returns the slice of `buf` that was written; `buf` must hold 20 bytes.
pub fn format(buf: []u8, epoch_seconds: i64) []const u8 {
    const secs: u64 = if (epoch_seconds < 0) 0 else @intCast(epoch_seconds);
    const epoch: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const time = epoch.getDaySeconds();

    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        time.getHoursIntoDay(),
        time.getMinutesIntoHour(),
        time.getSecondsIntoMinute(),
    }) catch buf[0..0];
}

test "epoch zero is the unix epoch" {
    var buf: [20]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", format(&buf, 0));
}

test "a known instant" {
    var buf: [20]u8 = undefined;
    // 2026-09-25T20:13:15Z
    try std.testing.expectEqualStrings("2026-09-25T20:13:15Z", format(&buf, 1790367195));
}

test "a negative timestamp does not underflow" {
    var buf: [20]u8 = undefined;
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", format(&buf, -5));
}
