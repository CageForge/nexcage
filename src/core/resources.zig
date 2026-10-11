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
/// is never silently lowered. Proxmox works the bytes out again from the MiB,
/// in 64 bits, so a size whose MiB cannot be turned back into bytes there is
/// refused here. The rounding adds nothing to `bytes`: `bytes + (1 MiB - 1)`
/// overflowed, and trapped, near the top of i64.
pub fn mibCeil(bytes: i64) error{TooLarge}!i64 {
    const mib = @divFloor(bytes, 1024 * 1024) + @intFromBool(@mod(bytes, 1024 * 1024) != 0);
    _ = std.math.mul(i64, mib, 1024 * 1024) catch return error.TooLarge;
    return mib;
}

/// The least memory limit pct takes, in MiB.
pub const min_memory_mib = 16;

/// cgroup v1 CPU shares to the cgroup v2 weight `pct set --cpuunits` takes on
/// a v2 host, exactly as runc converts them: 1 + ((shares - 2) * 9999) / 262142,
/// so 1024 shares -- the default -- become weight 39 and 262144 become 10000.
pub fn sharesToWeight(shares: i64) i64 {
    if (shares <= 2) return 1;
    // 262144, the most shares the kernel takes, is already weight 10000, the
    // most a weight can be. Above it the product below only overflows.
    if (shares >= 262144) return 10000;
    return 1 + @divFloor((shares - 2) * 9999, 262142);
}

/// quota over period as the cores `pct set --cpulimit` takes, formatted
/// without trailing zeros: 150000/100000 is "1.5", 50000/100000 is "0.5", a
/// quota of -1 is "0", which is pct's "no limit".
pub fn cpulimit(buf: []u8, quota: i64, period: i64) ![]const u8 {
    if (quota < 0) return "0";
    if (period <= 0) return error.InvalidPeriod;
    // Three decimals is more than pct keeps; enough not to lie by rounding.
    // A quota whose thousandths overflow is far more cores than pct takes.
    const milli = @divFloor(std.math.mul(i64, quota, 1000) catch return error.QuotaTooLarge, period);
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

/// A setting by where it sits in a `linux.resources` document: `memory` and
/// `limit` for memory.limit.
pub const Setting = struct { section: []const u8, name: []const u8 };

/// The settings in a `linux.resources` document, as `update` values. Fields
/// the list above does not know are left to libcrun, which reads the document
/// itself; this is what the Proxmox LXC backend, which cannot, works from.
/// Every `value` is allocated with `allocator`. A value of the wrong kind is
/// an error, and `refused` names its setting.
pub fn valuesFromResources(allocator: std.mem.Allocator, json: []const u8, out: *std.ArrayListUnmanaged(types.ResourceUpdate), refused: *?Setting) !void {
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
            // Every number here is a whole one in 64 bits, as libcrun reads
            // the same document. std.json makes a number with a fraction or
            // an exponent a float, and a whole one past i64 a number_string;
            // the float was cast, which cut 1.5 to 1 and trapped on 1e300.
            .float, .number_string => {
                refused.* = .{ .section = k.section, .name = k.name };
                return error.NotAnInteger;
            },
            .string => |str| try allocator.dupe(u8, str),
            .null => continue,
            else => {
                refused.* = .{ .section = k.section, .name = k.name };
                return error.InvalidResources;
            },
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

test "bytes to pct's MiB, never rounded down" {
    try std.testing.expectEqual(@as(i64, 1024), try mibCeil(1073741824));
    try std.testing.expectEqual(@as(i64, 513), try mibCeil(536870913));
    try std.testing.expectEqual(@as(i64, 1), try mibCeil(1));
    try std.testing.expectEqual(@as(i64, 0), try mibCeil(0));
}

test "shares to a cgroup v2 weight, as runc converts them" {
    try std.testing.expectEqual(@as(i64, 39), sharesToWeight(1024));
    try std.testing.expectEqual(@as(i64, 1), sharesToWeight(2));
    try std.testing.expectEqual(@as(i64, 10000), sharesToWeight(262144));
    try std.testing.expectEqual(@as(i64, 9999), sharesToWeight(262143));
}

test "quota over period as pct's cpulimit" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("1.5", try cpulimit(&buf, 150000, 100000));
    try std.testing.expectEqualStrings("0.5", try cpulimit(&buf, 50000, 100000));
    try std.testing.expectEqualStrings("2", try cpulimit(&buf, 200000, 100000));
    try std.testing.expectEqualStrings("0.25", try cpulimit(&buf, 25000, 100000));
    try std.testing.expectEqualStrings("0", try cpulimit(&buf, -1, 100000));
}

// Values from an engine's document or the command line reach this arithmetic
// unchecked; at the top of i64 it overflowed and the root process trapped.
test "limits at the top of i64 are converted or refused, never a trap" {
    const max = std.math.maxInt(i64);
    try std.testing.expectEqual(@as(i64, 10000), sharesToWeight(max));
    try std.testing.expectEqual(@as(i64, 10000), sharesToWeight(1_000_000_000_000_000));
    var buf: [32]u8 = undefined;
    try std.testing.expectError(error.QuotaTooLarge, cpulimit(&buf, max, 100000));
    try std.testing.expectError(error.QuotaTooLarge, cpulimit(&buf, 9_223_372_036_854_776, 100000));
    // The last quota whose thousandths still fit
    try std.testing.expectEqualStrings("92233720368.547", try cpulimit(&buf, 9_223_372_036_854_775, 100000));
}

test "MiB that Proxmox cannot turn back into bytes are refused" {
    const max = std.math.maxInt(i64);
    try std.testing.expectError(error.TooLarge, mibCeil(max));
    // 2^63 - 2^20 is the last size whose MiB, times 2^20, fit in i64
    try std.testing.expectEqual(@as(i64, 8796093022207), try mibCeil(max - (1024 * 1024 - 1)));
    try std.testing.expectError(error.TooLarge, mibCeil(max - (1024 * 1024 - 2)));
}

test "a number that is no whole i64 is refused by name, not cast" {
    var out = std.ArrayListUnmanaged(types.ResourceUpdate){};
    defer {
        for (out.items) |u| std.testing.allocator.free(u.value);
        out.deinit(std.testing.allocator);
    }
    const docs = [_][]const u8{
        \\{"memory":{"limit":1e300}}
        ,
        \\{"memory":{"limit":1.5}}
        ,
        \\{"memory":{"limit":9223372036854775808}}
        ,
    };
    for (docs) |doc| {
        var refused: ?Setting = null;
        try std.testing.expectError(error.NotAnInteger, valuesFromResources(std.testing.allocator, doc, &out, &refused));
        try std.testing.expectEqualStrings("memory", refused.?.section);
        try std.testing.expectEqualStrings("limit", refused.?.name);
    }
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "a linux.resources document becomes values, wrapped or bare" {
    var refused: ?Setting = null;
    var out = std.ArrayListUnmanaged(types.ResourceUpdate){};
    defer {
        for (out.items) |u| std.testing.allocator.free(u.value);
        out.deinit(std.testing.allocator);
    }
    try valuesFromResources(std.testing.allocator,
        \\{"memory":{"limit":536870912},"cpu":{"quota":50000,"period":100000,"cpus":"0-1"}}
    , &out, &refused);
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
    , &wrapped, &refused);
    try std.testing.expect(refused == null);
    try std.testing.expectEqual(@as(usize, 1), wrapped.items.len);
    try std.testing.expectEqualStrings("pids", wrapped.items[0].section);
}
