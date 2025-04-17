const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub const Resource = struct {
    name: []const u8,
    type: []const u8,
    status: []const u8,
    owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, res_type: []const u8, status: []const u8, owned: bool) !Resource {
        if (owned) {
            return Resource{
                .name = try allocator.dupe(u8, name),
                .type = try allocator.dupe(u8, res_type),
                .status = try allocator.dupe(u8, status),
                .owned = true,
            };
        } else {
            return Resource{
                .name = name,
                .type = res_type,
                .status = status,
                .owned = false,
            };
        }
    }

    pub fn deinit(self: *Resource, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.name);
            allocator.free(self.type);
            allocator.free(self.status);
        }
    }
};

pub fn listResources(client: *Client) ![]Resource {
    const path = "/cluster/resources";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var resources = ArrayList(Resource).init(client.allocator);
    errdefer {
        for (resources.items) |*resource| {
            resource.deinit(client.allocator);
        }
        resources.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |resource| {
            try resources.append(try Resource.init(
                client.allocator,
                resource.object.get("id").?.string,
                resource.object.get("type").?.string,
                resource.object.get("status").?.string,
                true,
            ));
        }
    }

    return try resources.toOwnedSlice();
}

pub fn getClusterStatus(client: *Client) !struct {
    nodes: u32,
    quorum: bool,
    version: []const u8,
} {
    const path = "/cluster/status";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    const data = parsed.value.object.get("data").?;
    const version = try client.allocator.dupe(u8, data.object.get("version").?.string);

    return .{
        .nodes = @intCast(data.object.get("nodes").?.integer),
        .quorum = data.object.get("quorum").?.bool,
        .version = version,
    };
} 