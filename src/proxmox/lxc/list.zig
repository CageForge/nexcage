const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub fn listLXCs(client: *Client) ![]types.LXCContainer {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var containers = ArrayList(types.LXCContainer).init(client.allocator);
    errdefer {
        for (containers.items) |*container| {
            container.deinit(client.allocator);
        }
        containers.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |container| {
            try containers.append(types.LXCContainer{
                .vmid = @intCast(container.object.get("vmid").?.integer),
                .name = try client.allocator.dupe(u8, container.object.get("name").?.string),
                .status = try parseStatus(container.object.get("status").?.string),
                .config = try getLXCConfig(client, client.node, @intCast(container.object.get("vmid").?.integer)),
            });
        }
    }

    return try containers.toOwnedSlice();
}

fn parseStatus(status: []const u8) !types.ContainerStatus {
    if (std.mem.eql(u8, status, "running")) {
        return .running;
    } else if (std.mem.eql(u8, status, "stopped")) {
        return .stopped;
    } else if (std.mem.eql(u8, status, "paused")) {
        return .paused;
    } else {
        return .unknown;
    }
}

fn getLXCConfig(client: *Client, node: []const u8, vmid: u32) !types.LXCConfig {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/config", .{ node, vmid });
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const data = parsed.value.object.get("data").? orelse return error.InvalidResponse;

    return types.LXCConfig{
        .hostname = try client.allocator.dupe(u8, data.object.get("hostname").?.string),
        .ostype = try client.allocator.dupe(u8, data.object.get("ostype").?.string),
        .memory = @intCast(data.object.get("memory").?.integer),
        .swap = @intCast(data.object.get("swap").?.integer),
        .cores = @intCast(data.object.get("cores").?.integer),
        .rootfs = try client.allocator.dupe(u8, data.object.get("rootfs").?.string),
        .net0 = try parseNetworkConfig(client.allocator, data.object.get("net0").?.string),
        .onboot = data.object.get("onboot").?.bool,
        .protection = data.object.get("protection").?.bool,
        .start = data.object.get("start").?.bool,
        .template = data.object.get("template").?.bool,
        .unprivileged = data.object.get("unprivileged").?.bool,
        .features = .{},
    };
}

fn parseNetworkConfig(allocator: std.mem.Allocator, net_str: []const u8) !types.NetworkConfig {
    var net = types.NetworkConfig{
        .name = "eth0",
        .bridge = "vmbr0",
        .ip = "dhcp",
    };

    var net_iter = std.mem.splitScalar(u8, net_str, ',');
    while (net_iter.next()) |pair| {
        var kv_iter = std.mem.splitScalar(u8, pair, '=');
        if (kv_iter.next()) |key| {
            if (kv_iter.next()) |value| {
                if (std.mem.eql(u8, key, "name")) {
                    net.name = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "bridge")) {
                    net.bridge = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "ip")) {
                    net.ip = try allocator.dupe(u8, value);
                }
            }
        }
    }

    return net;
} 