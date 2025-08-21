const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub const Node = struct {
    name: []const u8,
    status: []const u8,
    node_type: []const u8,
    owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, status: []const u8, node_type: []const u8, owned: bool) !Node {
        if (owned) {
            return Node{
                .name = try allocator.dupe(u8, name),
                .status = try allocator.dupe(u8, status),
                .node_type = try allocator.dupe(u8, node_type),
                .owned = true,
            };
        } else {
            return Node{
                .name = name,
                .status = status,
                .node_type = node_type,
                .owned = false,
            };
        }
    }

    pub fn deinit(self: *Node, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.name);
            allocator.free(self.status);
            allocator.free(self.node_type);
        }
    }
};

pub fn getNodes(client: *Client) ![]Node {
    const path = "/cluster/resources";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var nodes = ArrayList(Node).init(client.allocator);
    errdefer {
        for (nodes.items) |*node| {
            node.deinit(client.allocator);
        }
        nodes.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |resource| {
            if (resource.object.get("type")) |type_value| {
                if (std.mem.eql(u8, type_value.string, "node")) {
                    try nodes.append(try Node.init(
                        client.allocator,
                        resource.object.get("node").?.string,
                        resource.object.get("status").?.string,
                        resource.object.get("type").?.string,
                        true,
                    ));
                }
            }
        }
    }

    return try nodes.toOwnedSlice();
}
