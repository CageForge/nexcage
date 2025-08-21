const std = @import("std");
const types = @import("../../common/types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;

pub fn getLXCStatus(client: *Client, node: []const u8, vmid: u32) !types.ContainerStatus {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/current", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Getting status for LXC container {d} on node {s}", .{ vmid, node });

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when getting container status {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        if (data.object.get("status")) |status| {
            return try parseStatus(status.string);
        }
    }

    try client.logger.err("Invalid response format for container status {d}: {s}", .{ vmid, response });
    return error.InvalidResponse;
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
