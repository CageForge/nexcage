const std = @import("std");
const types = @import("../../common/types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const logger = std.log.scoped(.proxmox_lxc);
const ProxmoxClient = @import("../proxmox.zig").ProxmoxClient;
const proxmox = @import("../proxmox.zig");

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

pub fn listLXC(client: *ProxmoxClient) ![]types.LXCContainer {
    logger.info("Listing all containers", .{});

    const path = try std.fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer response.deinit();

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response.body, .{});
    defer parsed.deinit();

    if (!parsed.value.object.contains("data")) {
        return error.InvalidResponse;
    }

    const data = parsed.value.object.get("data").?;
    if (data != .array) {
        return error.InvalidResponse;
    }

    var containers = std.ArrayList(types.LXCContainer).init(client.allocator);
    errdefer containers.deinit();

    for (data.array.items) |container| {
        if (container != .object) continue;

        const vmid = container.object.get("vmid") orelse continue;
        if (vmid != .integer) continue;

        const name = container.object.get("name") orelse continue;
        if (name != .string) continue;

        const status = container.object.get("status") orelse continue;
        if (status != .string) continue;

        const container_status = try types.ContainerStatus.fromString(status.string);

        try containers.append(.{
            .vmid = @intCast(vmid.integer),
            .name = try client.allocator.dupe(u8, name.string),
            .status = container_status,
        });
    }

    return try containers.toOwnedSlice();
}

pub fn getLXCStatus(client: *ProxmoxClient, oci_container_id: []const u8) !types.ContainerStatus {
    logger.info("Getting status for container {s}", .{oci_container_id});

    const vmid = try client.getProxmoxVMID(oci_container_id);
    const path = try std.fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/current", .{ client.node, vmid });
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer response.deinit();

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response.body, .{});
    defer parsed.deinit();

    if (!parsed.value.object.contains("data")) {
        return error.InvalidResponse;
    }

    const data = parsed.value.object.get("data").?;
    if (data != .object) {
        return error.InvalidResponse;
    }

    const status = data.object.get("status") orelse return error.InvalidResponse;
    if (status != .string) {
        return error.InvalidResponse;
    }

    return try types.ContainerStatus.fromString(status.string);
}
