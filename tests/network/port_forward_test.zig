const std = @import("std");
const testing = std.testing;
const types = @import("../../src/types/pod.zig");
const port_forward = @import("../../src/network/port_forward.zig");

test "PortForwarder - базові операції" {
    const allocator = testing.allocator;
    var forwarder = try port_forward.PortForwarder.init(allocator, "10.0.0.2");
    defer forwarder.deinit();

    // TCP port mapping
    const tcp_rule = types.PortMapping{
        .protocol = .tcp,
        .host_port = 8080,
        .container_port = 80,
    };

    try forwarder.addRule(tcp_rule);
    try testing.expect(forwarder.hasRule(tcp_rule));
    try testing.expectEqual(forwarder.rules.items.len, 1);

    try forwarder.deleteRule(tcp_rule);
    try testing.expect(!forwarder.hasRule(tcp_rule));
    try testing.expectEqual(forwarder.rules.items.len, 0);

    // UDP port mapping
    const udp_rule = types.PortMapping{
        .protocol = .udp,
        .host_port = 53,
        .container_port = 53,
    };

    try forwarder.addRule(udp_rule);
    try testing.expect(forwarder.hasRule(udp_rule));
    try testing.expectEqual(forwarder.rules.items.len, 1);

    try forwarder.deleteRule(udp_rule);
    try testing.expect(!forwarder.hasRule(udp_rule));
    try testing.expectEqual(forwarder.rules.items.len, 0);
}

test "PortForwarder - невалідний протокол" {
    const allocator = testing.allocator;
    var forwarder = try port_forward.PortForwarder.init(allocator, "10.0.0.2");
    defer forwarder.deinit();

    const invalid_rule = types.PortMapping{
        .protocol = @intToEnum(types.Protocol, 999), // SCTP
        .host_port = 8080,
        .container_port = 80,
    };

    try testing.expectError(port_forward.Error.InvalidProtocol, forwarder.addRule(invalid_rule));
    try testing.expectError(port_forward.Error.InvalidProtocol, forwarder.deleteRule(invalid_rule));
    try testing.expect(!forwarder.hasRule(invalid_rule));
}

test "PortForwarder - управління пам'яттю" {
    const allocator = testing.allocator;
    var forwarder = try port_forward.PortForwarder.init(allocator, "10.0.0.2");
    defer forwarder.deinit();

    // Додаємо декілька правил
    const rules = [_]types.PortMapping{
        .{
            .protocol = .tcp,
            .host_port = 8080,
            .container_port = 80,
        },
        .{
            .protocol = .udp,
            .host_port = 53,
            .container_port = 53,
        },
        .{
            .protocol = .tcp,
            .host_port = 443,
            .container_port = 8443,
        },
    };

    // Додаємо всі правила
    for (rules) |rule| {
        try forwarder.addRule(rule);
        try testing.expect(forwarder.hasRule(rule));
    }
    try testing.expectEqual(forwarder.rules.items.len, rules.len);

    // Видаляємо всі правила
    for (rules) |rule| {
        try forwarder.deleteRule(rule);
        try testing.expect(!forwarder.hasRule(rule));
    }
    try testing.expectEqual(forwarder.rules.items.len, 0);
}; 