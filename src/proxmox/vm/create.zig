const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;

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
