const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub const create = @import("create.zig").createVM;
pub const start = @import("start.zig").startVM;
pub const stop = @import("stop.zig").stopVM;
pub const delete = @import("delete.zig").deleteVM;
pub const status = @import("status.zig").getVMStatus;
pub const list = @import("list.zig").listVMs;

pub fn listVMs(client: *Client) ![]types.VMContainer {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var containers = ArrayList(types.VMContainer).init(client.allocator);
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
            try containers.append(types.VMContainer{
                .vmid = @intCast(container.object.get("vmid").?.integer),
                .name = try client.allocator.dupe(u8, container.object.get("name").?.string),
                .status = try parseContainerStatus(container.object.get("status").?.string),
                .config = try getVMConfig(client, client.node, @intCast(container.object.get("vmid").?.integer)),
            });
        }
    }

    return try containers.toOwnedSlice();
}

pub fn createVM(client: *Client, spec: types.VMConfig) !types.VMContainer {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu", .{client.node});
    defer client.allocator.free(path);

    const body = try json.stringifyAlloc(client.allocator, spec, .{});
    defer client.allocator.free(body);

    const response = try client.makeRequest(.POST, path, body);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    return types.VMContainer{
        .vmid = @intCast(parsed.value.object.get("data").?.object.get("vmid").?.integer),
        .name = try client.allocator.dupe(u8, spec.name),
        .status = .stopped,
        .config = spec,
    };
}

pub fn startVM(client: *Client, node: []const u8, vmid: u32) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}/status/start", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Starting VM {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.POST, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when starting VM {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("VM {d} started successfully", .{vmid});
    } else {
        try client.logger.err("Failed to start VM {d}: {s}", .{ vmid, response });
        return error.StartError;
    }
}

pub fn stopVM(client: *Client, node: []const u8, vmid: u32, timeout: ?i64) !void {
    var query = ArrayList(u8).init(client.allocator);
    defer query.deinit();

    if (timeout) |t| {
        try query.writer().print("timeout={d}", .{t});
    }

    const path = if (query.items.len > 0)
        try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}/status/stop?{s}", .{ node, vmid, query.items })
    else
        try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}/status/stop", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Stopping VM {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.POST, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when stopping VM {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("VM {d} stopped successfully", .{vmid});
    } else {
        try client.logger.err("Failed to stop VM {d}: {s}", .{ vmid, response });
        return error.StopError;
    }
}

pub fn deleteVM(client: *Client, node: []const u8, vmid: u32) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Deleting VM {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.DELETE, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when deleting VM {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("VM {d} deleted successfully", .{vmid});
    } else {
        try client.logger.err("Failed to delete VM {d}: {s}", .{ vmid, response });
        return error.DeleteError;
    }
}

pub fn getVMStatus(client: *Client, node: []const u8, vmid: u32) !types.ContainerStatus {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}/status/current", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Getting status for VM {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when getting VM status {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        if (data.object.get("status")) |status_str| {
            return try parseContainerStatus(status_str.string);
        }
    }

    try client.logger.err("Invalid response format for VM status {d}: {s}", .{ vmid, response });
    return error.InvalidResponse;
}

fn parseContainerStatus(status_str: []const u8) !types.ContainerStatus {
    if (std.mem.eql(u8, status_str, "running")) {
        return .running;
    } else if (std.mem.eql(u8, status_str, "stopped")) {
        return .stopped;
    } else if (std.mem.eql(u8, status_str, "paused")) {
        return .paused;
    } else {
        return .unknown;
    }
}

fn getVMConfig(client: *Client, node: []const u8, vmid: u32) !types.VMConfig {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/qemu/{d}/config", .{ node, vmid });
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const data = parsed.value.object.get("data").? orelse return error.InvalidResponse;

    return types.VMConfig{
        .name = try client.allocator.dupe(u8, data.object.get("name").?.string),
        .memory = @intCast(data.object.get("memory").?.integer),
        .cores = @intCast(data.object.get("cores").?.integer),
        .sockets = @intCast(data.object.get("sockets").?.integer),
        .net0 = try parseNetworkConfig(client.allocator, data.object.get("net0").?.string),
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