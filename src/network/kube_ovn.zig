const std = @import("std");
const network = @import("mod.zig");

pub const KubeOVNError = error{
    MissingIPAddress,
    MissingMACAddress,
    MissingGateway,
    MissingCIDR,
    InvalidIPAddress,
    InvalidMACAddress,
    InvalidGateway,
    InvalidCIDR,
    InvalidMTU,
    InvalidVLAN,
    InvalidBandwidth,
};

pub const NetworkConfig = struct {
    ip_address: []const u8,
    mac_address: []const u8,
    gateway: []const u8,
    cidr: []const u8,
    mtu: ?u32 = null,
    vlan: ?u16 = null,
    ingress_rate: ?u32 = null,
    egress_rate: ?u32 = null,
    dns_servers: ?[]const []const u8 = null,
    dns_search: ?[]const []const u8 = null,

    pub fn init(allocator: std.mem.Allocator, annotations: std.StringHashMap([]const u8)) !NetworkConfig {
        const ip = annotations.get("ovn.kubernetes.io/ip_address") orelse return KubeOVNError.MissingIPAddress;
        const mac = annotations.get("ovn.kubernetes.io/mac_address") orelse return KubeOVNError.MissingMACAddress;
        const gateway = annotations.get("ovn.kubernetes.io/gateway") orelse return KubeOVNError.MissingGateway;
        const cidr = annotations.get("ovn.kubernetes.io/cidr") orelse return KubeOVNError.MissingCIDR;

        if (!try network.isValidIPAddress(ip)) return KubeOVNError.InvalidIPAddress;
        if (!try network.isValidMACAddress(mac)) return KubeOVNError.InvalidMACAddress;
        if (!try network.isValidIPAddress(gateway)) return KubeOVNError.InvalidGateway;

        var config = NetworkConfig{
            .ip_address = try allocator.dupe(u8, ip),
            .mac_address = try allocator.dupe(u8, mac),
            .gateway = try allocator.dupe(u8, gateway),
            .cidr = try allocator.dupe(u8, cidr),
        };

        if (annotations.get("ovn.kubernetes.io/mtu")) |mtu_str| {
            config.mtu = std.fmt.parseInt(u32, mtu_str, 10) catch return KubeOVNError.InvalidMTU;
        }

        if (annotations.get("ovn.kubernetes.io/vlan")) |vlan_str| {
            config.vlan = std.fmt.parseInt(u16, vlan_str, 10) catch return KubeOVNError.InvalidVLAN;
        }

        if (annotations.get("ovn.kubernetes.io/ingress_rate")) |rate_str| {
            config.ingress_rate = std.fmt.parseInt(u32, rate_str, 10) catch return KubeOVNError.InvalidBandwidth;
        }

        if (annotations.get("ovn.kubernetes.io/egress_rate")) |rate_str| {
            config.egress_rate = std.fmt.parseInt(u32, rate_str, 10) catch return KubeOVNError.InvalidBandwidth;
        }

        // TODO: Додати парсинг DNS серверів та пошукових доменів

        return config;
    }

    pub fn deinit(self: *NetworkConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.ip_address);
        allocator.free(self.mac_address);
        allocator.free(self.gateway);
        allocator.free(self.cidr);
        if (self.dns_servers) |servers| {
            for (servers) |server| {
                allocator.free(server);
            }
            allocator.free(servers);
        }
        if (self.dns_search) |domains| {
            for (domains) |domain| {
                allocator.free(domain);
            }
            allocator.free(domains);
        }
    }

    pub fn toString(self: NetworkConfig, allocator: std.mem.Allocator) ![]const u8 {
        var config = std.ArrayList(u8).init(allocator);
        defer config.deinit();

        try config.writer().print("ip={s},gw={s},hwaddr={s}", .{
            self.ip_address,
            self.gateway,
            self.mac_address,
        });

        if (self.mtu) |mtu| {
            try config.writer().print(",mtu={d}", .{mtu});
        }

        if (self.vlan) |vlan| {
            try config.writer().print(",vlan={d}", .{vlan});
        }

        if (self.ingress_rate) |rate| {
            try config.writer().print(",rate={d}", .{rate});
        }

        if (self.egress_rate) |rate| {
            try config.writer().print(",rate_limit={d}", .{rate});
        }

        // TODO: Додати DNS конфігурацію

        return config.toOwnedSlice();
    }
};

test "NetworkConfig initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    try annotations.put("ovn.kubernetes.io/ip_address", "192.168.1.100");
    try annotations.put("ovn.kubernetes.io/mac_address", "02:00:00:00:00:01");
    try annotations.put("ovn.kubernetes.io/gateway", "192.168.1.1");
    try annotations.put("ovn.kubernetes.io/cidr", "192.168.1.0/24");
    try annotations.put("ovn.kubernetes.io/mtu", "1500");
    try annotations.put("ovn.kubernetes.io/vlan", "100");
    try annotations.put("ovn.kubernetes.io/ingress_rate", "1000000");
    try annotations.put("ovn.kubernetes.io/egress_rate", "1000000");

    var config = try NetworkConfig.init(allocator, annotations);
    defer config.deinit(allocator);

    try testing.expectEqualStrings("192.168.1.100", config.ip_address);
    try testing.expectEqualStrings("02:00:00:00:00:01", config.mac_address);
    try testing.expectEqualStrings("192.168.1.1", config.gateway);
    try testing.expectEqualStrings("192.168.1.0/24", config.cidr);
    try testing.expectEqual(@as(u32, 1500), config.mtu.?);
    try testing.expectEqual(@as(u16, 100), config.vlan.?);
    try testing.expectEqual(@as(u32, 1000000), config.ingress_rate.?);
    try testing.expectEqual(@as(u32, 1000000), config.egress_rate.?);
}

test "NetworkConfig toString" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    try annotations.put("ovn.kubernetes.io/ip_address", "192.168.1.100");
    try annotations.put("ovn.kubernetes.io/mac_address", "02:00:00:00:00:01");
    try annotations.put("ovn.kubernetes.io/gateway", "192.168.1.1");
    try annotations.put("ovn.kubernetes.io/cidr", "192.168.1.0/24");
    try annotations.put("ovn.kubernetes.io/mtu", "1500");
    try annotations.put("ovn.kubernetes.io/vlan", "100");

    var config = try NetworkConfig.init(allocator, annotations);
    defer config.deinit(allocator);

    const config_str = try config.toString(allocator);
    defer allocator.free(config_str);

    try testing.expectEqualStrings(
        "ip=192.168.1.100,gw=192.168.1.1,hwaddr=02:00:00:00:00:01,mtu=1500,vlan=100",
        config_str
    );
} 