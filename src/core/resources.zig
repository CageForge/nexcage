//! What `update` takes and what it means: sizes as runc reads them, the
//! runtime-spec `linux.resources` document a container engine sends, and the
//! conversions the Proxmox LXC backend needs to say the same thing in `pct
//! set`'s terms.
const std = @import("std");
const types = @import("types.zig");

/// A size as `runc update --memory` takes it: bytes, or a number with a binary
/// suffix (`512M`, `2G`), or `-1` for no limit. Anything else is an error.
pub fn parseSize(raw: []const u8) !i64 {
    if (raw.len == 0) return error.InvalidSize;
    if (std.mem.eql(u8, raw, "-1")) return -1;
    var digits = raw;
    var mult: i64 = 1;
    const last = raw[raw.len - 1];
    switch (last) {
        'k', 'K' => mult = 1024,
        'm', 'M' => mult = 1024 * 1024,
        'g', 'G' => mult = 1024 * 1024 * 1024,
        else => {},
    }
    if (mult != 1) digits = raw[0 .. raw.len - 1];
    const n = std.fmt.parseInt(i64, digits, 10) catch return error.InvalidSize;
    if (n < 0) return error.InvalidSize;
    return std.math.mul(i64, n, mult) catch error.InvalidSize;
}

/// Bytes to the MiB `pct set --memory` and `--swap` take, rounded up so a limit
/// is never silently lowered; pct refuses less than 16.
pub fn mibCeil(bytes: i64) i64 {
    const mib = @divFloor(bytes + (1024 * 1024 - 1), 1024 * 1024);
    return if (mib < 16) 16 else mib;
}

/// cgroup v1 CPU shares to the cgroup v2 weight `pct set --cpuunits` takes on
/// a v2 host, exactly as runc converts them: 1 + ((shares - 2) * 9999) / 262142,
/// so 1024 shares -- the default -- become weight 39 and 262144 become 10000.
pub fn sharesToWeight(shares: i64) i64 {
    if (shares <= 2) return 1;
    const w = 1 + @divFloor((shares - 2) * 9999, 262142);
    return if (w > 10000) 10000 else w;
}

/// quota over period as the cores `pct set --cpulimit` takes, formatted
/// without trailing zeros: 150000/100000 is "1.5", 50000/100000 is "0.5", a
/// quota of -1 is "0", which is pct's "no limit".
pub fn cpulimit(buf: []u8, quota: i64, period: i64) ![]const u8 {
    if (quota < 0) return "0";
    if (period <= 0) return error.InvalidPeriod;
    // Three decimals is more than pct keeps; enough not to lie by rounding
    const milli = @divFloor(quota * 1000, period);
    const whole = @divFloor(milli, 1000);
    var frac = @mod(milli, 1000);
    if (frac == 0) return std.fmt.bufPrint(buf, "{d}", .{whole});
    var width: usize = 3;
    while (@mod(frac, 10) == 0) : (width -= 1) frac = @divFloor(frac, 10);
    // Leading zeros of the fraction by hand: a zero fill on a signed
    // integer makes std.fmt print its sign, so "{d:0>2}" of 25 is "+25".
    const digits: usize = if (frac < 10) 1 else if (frac < 100) 2 else 3;
    const zeros = "00";
    return std.fmt.bufPrint(buf, "{d}.{s}{d}", .{ whole, zeros[0 .. width - digits], frac });
}

/// The sections and fields of a `linux.resources` document that `update`
/// reads, in the order they are applied. The same vocabulary crun's `update`
/// uses for its value flags, so the two forms meet in one list.
pub const known = [_]struct { section: []const u8, name: []const u8, numeric: bool }{
    .{ .section = "memory", .name = "limit", .numeric = true },
    .{ .section = "memory", .name = "reservation", .numeric = true },
    .{ .section = "memory", .name = "swap", .numeric = true },
    .{ .section = "memory", .name = "kernel", .numeric = true },
    .{ .section = "memory", .name = "kernelTCP", .numeric = true },
    .{ .section = "cpu", .name = "shares", .numeric = true },
    .{ .section = "cpu", .name = "quota", .numeric = true },
    .{ .section = "cpu", .name = "period", .numeric = true },
    .{ .section = "cpu", .name = "realtimeRuntime", .numeric = true },
    .{ .section = "cpu", .name = "realtimePeriod", .numeric = true },
    .{ .section = "cpu", .name = "cpus", .numeric = false },
    .{ .section = "cpu", .name = "mems", .numeric = false },
    .{ .section = "pids", .name = "limit", .numeric = true },
    .{ .section = "blockIO", .name = "weight", .numeric = true },
};

/// The settings in a `linux.resources` document, as `update` values. Fields
/// the list above does not know are left to libcrun, which reads the document
/// itself; this is what the Proxmox LXC backend, which cannot, works from.
/// Every `value` is allocated with `allocator`.
pub fn valuesFromResources(allocator: std.mem.Allocator, json: []const u8, out: *std.ArrayListUnmanaged(types.ResourceUpdate)) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return error.InvalidResources;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResources;
    // An engine sends the resources object itself; a hand-written file may
    // wrap it the way config.json does.
    var root = parsed.value.object;
    if (root.get("linux")) |l| if (l == .object) if (l.object.get("resources")) |r| if (r == .object) {
        root = r.object;
    };
    for (known) |k| {
        const sec = root.get(k.section) orelse continue;
        if (sec != .object) continue;
        const v = sec.object.get(k.name) orelse continue;
        const text: []u8 = switch (v) {
            .integer => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(f))}),
            .string => |str| try allocator.dupe(u8, str),
            .null => continue,
            else => return error.InvalidResources,
        };
        errdefer allocator.free(text);
        try out.append(allocator, .{ .section = k.section, .name = k.name, .value = text, .numeric = k.numeric });
    }
}

test "sizes as runc reads them" {
    try std.testing.expectEqual(@as(i64, 536870912), try parseSize("512M"));
    try std.testing.expectEqual(@as(i64, 2147483648), try parseSize("2G"));
    try std.testing.expectEqual(@as(i64, 1024), try parseSize("1k"));
    try std.testing.expectEqual(@as(i64, 100), try parseSize("100"));
    try std.testing.expectEqual(@as(i64, -1), try parseSize("-1"));
    try std.testing.expectError(error.InvalidSize, parseSize("lots"));
    try std.testing.expectError(error.InvalidSize, parseSize(""));
}

test "bytes to pct's MiB, never rounded down, never below 16" {
    try std.testing.expectEqual(@as(i64, 1024), mibCeil(1073741824));
    try std.testing.expectEqual(@as(i64, 513), mibCeil(536870913));
    try std.testing.expectEqual(@as(i64, 16), mibCeil(1));
}

test "shares to a cgroup v2 weight, as runc converts them" {
    try std.testing.expectEqual(@as(i64, 39), sharesToWeight(1024));
    try std.testing.expectEqual(@as(i64, 1), sharesToWeight(2));
    try std.testing.expectEqual(@as(i64, 10000), sharesToWeight(262144));
}

test "quota over period as pct's cpulimit" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.5", try cpulimit(&buf, 150000, 100000));
    try std.testing.expectEqualStrings("0.5", try cpulimit(&buf, 50000, 100000));
    try std.testing.expectEqualStrings("2", try cpulimit(&buf, 200000, 100000));
    try std.testing.expectEqualStrings("0.25", try cpulimit(&buf, 25000, 100000));
    try std.testing.expectEqualStrings("0", try cpulimit(&buf, -1, 100000));
}

test "a linux.resources document becomes values, wrapped or bare" {
    var out = std.ArrayListUnmanaged(types.ResourceUpdate){};
    defer {
        for (out.items) |u| std.testing.allocator.free(u.value);
        out.deinit(std.testing.allocator);
    }
    try valuesFromResources(std.testing.allocator,
        \\{"memory":{"limit":536870912},"cpu":{"quota":50000,"period":100000,"cpus":"0-1"}}
    , &out);
    try std.testing.expectEqual(@as(usize, 4), out.items.len);
    try std.testing.expectEqualStrings("memory", out.items[0].section);
    try std.testing.expectEqualStrings("536870912", out.items[0].value);
    try std.testing.expectEqualStrings("cpus", out.items[3].name);
    try std.testing.expect(!out.items[3].numeric);

    var wrapped = std.ArrayListUnmanaged(types.ResourceUpdate){};
    defer {
        for (wrapped.items) |u| std.testing.allocator.free(u.value);
        wrapped.deinit(std.testing.allocator);
    }
    try valuesFromResources(std.testing.allocator,
        \\{"linux":{"resources":{"pids":{"limit":100}}}}
    , &wrapped);
    try std.testing.expectEqual(@as(usize, 1), wrapped.items.len);
    try std.testing.expectEqualStrings("pids", wrapped.items[0].section);
}
