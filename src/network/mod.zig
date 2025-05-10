pub const cni = @import("cni.zig");
pub const cilium = @import("cilium.zig");
pub const state = @import("state.zig");
pub const manager = @import("manager.zig");
pub const dns = @import("dns.zig");
pub const port_forward = @import("port_forward.zig");
pub const validator = @import("validator.zig");
pub usingnamespace @import("network.zig");

pub const NetworkManager = manager.NetworkManager;
pub const NetworkError = manager.NetworkError;
pub const NetworkState = state.NetworkState;
pub const CNIPlugin = cni.CNIPlugin;
pub const CiliumPlugin = cilium.CiliumPlugin;
pub const DnsManager = dns.DnsManager;
pub const PortForwarder = port_forward.PortForwarder;

const std = @import("std");

/// Перевіряє чи є рядок валідною IPv4 адресою
pub fn isValidIPAddress(ip: []const u8) !bool {
    var parts = std.mem.split(u8, ip, ".");
    var count: u8 = 0;

    while (parts.next()) |part| {
        count += 1;
        if (count > 4) return false;

        const num = std.fmt.parseInt(u8, part, 10) catch return false;
        if (part.len > 1 and part[0] == '0') return false; // Заборона ведучих нулів
    }

    return count == 4;
}

/// Перевіряє чи є рядок валідною MAC адресою
pub fn isValidMACAddress(mac: []const u8) !bool {
    if (mac.len != 17) return false;

    var i: usize = 0;
    while (i < 17) : (i += 1) {
        const c = mac[i];
        if (i % 3 == 2) {
            if (c != ':') return false;
        } else {
            switch (c) {
                '0'...'9', 'A'...'F', 'a'...'f' => {},
                else => return false,
            }
        }
    }

    return true;
}

/// Генерує випадкову MAC адресу
pub fn generateMACAddress(allocator: std.mem.Allocator) ![]const u8 {
    var mac = try allocator.alloc(u8, 17);
    errdefer allocator.free(mac);

    var rng = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = rng.random();

    // Перший байт повинен мати локально адміністрований біт встановленим
    const first_byte = 0x02 | (random.int(u8) & 0xFE);

    try std.fmt.bufPrint(mac[0..], "{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
        first_byte,
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
        random.int(u8),
    });

    return mac;
}

test "isValidIPAddress" {
    const testing = std.testing;

    try testing.expect(try isValidIPAddress("192.168.1.1"));
    try testing.expect(try isValidIPAddress("10.0.0.0"));
    try testing.expect(try isValidIPAddress("172.16.254.1"));

    try testing.expect(!try isValidIPAddress("256.1.2.3"));
    try testing.expect(!try isValidIPAddress("1.1.1"));
    try testing.expect(!try isValidIPAddress("192.168.01.1"));
}

test "isValidMACAddress" {
    const testing = std.testing;

    try testing.expect(try isValidMACAddress("00:11:22:33:44:55"));
    try testing.expect(try isValidMACAddress("AA:BB:CC:DD:EE:FF"));
    try testing.expect(try isValidMACAddress("02:00:00:00:00:00"));

    try testing.expect(!try isValidMACAddress("00-11-22-33-44-55"));
    try testing.expect(!try isValidMACAddress("00:11:22:33:44"));
    try testing.expect(!try isValidMACAddress("00:11:22:33:44:GG"));
}

test "generateMACAddress" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const mac = try generateMACAddress(allocator);
    defer allocator.free(mac);

    try testing.expect(try isValidMACAddress(mac));
    try testing.expect(mac[0] == '0' and mac[1] == '2');
}
