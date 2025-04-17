const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub fn listLXCs(client: *Client) ![]types.LXCContainer {
    const nodes = try client.getNodes();
    
    var containers = ArrayList(types.LXCContainer).init(client.allocator);
    errdefer {
        for (containers.items) |container| {
            client.allocator.free(container.name);
        }
        containers.deinit();
    }

    for (nodes) |node| {
        const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{node.name});
        defer client.allocator.free(path);

        try client.logger.info("Requesting LXC containers from node {s} with path: {s}", .{node.name, path});
        
        const response = try client.makeRequest(.GET, path, null);
        defer client.allocator.free(response);

        if (response.len == 0) {
            try client.logger.warn("Empty response from node {s}", .{node.name});
            continue;
        }

        var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
        defer parsed.deinit();

        if (parsed.value.object.get("data")) |data| {
            for (data.array.items) |container| {
                try containers.append(types.LXCContainer{
                    .vmid = @intCast(container.object.get("vmid").?.integer),
                    .name = try client.allocator.dupe(u8, container.object.get("name").?.string),
                    .status = try parseStatus(container.object.get("status").?.string),
                });
            }
        }
    }

    return try containers.toOwnedSlice();
}

pub fn createLXC(client: *Client, spec: types.LXCConfig) !types.LXCContainer {
    const body = try json.stringifyAlloc(client.allocator, spec, .{});
    defer client.allocator.free(body);

    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.POST, path, body);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    return types.LXCContainer{
        .vmid = @intCast(parsed.value.object.get("vmid").?.integer),
        .name = try client.allocator.dupe(u8, spec.hostname),
        .status = .stopped,
    };
}

fn parseStatus(status: []const u8) !types.LXCStatus {
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