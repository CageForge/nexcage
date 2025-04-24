const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;

pub fn stopLXC(client: *Client, node: []const u8, vmid: u32) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/lxc/{d}/status/stop", .{ node, vmid });
    defer client.allocator.free(path);

    try client.logger.debug("Stopping LXC container {d} on node {s}", .{ vmid, node });
    
    const response = try client.makeRequest(.POST, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when stopping container {d}", .{vmid});
        return error.EmptyResponse;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("Container {d} stopped successfully", .{vmid});
    } else {
        try client.logger.err("Failed to stop container {d}: {s}", .{ vmid, response });
        return error.StopError;
    }
} 