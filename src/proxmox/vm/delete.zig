const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;

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