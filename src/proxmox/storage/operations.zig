const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub const Storage = struct {
    name: []const u8,
    type: []const u8,
    status: []const u8,
    content: []const []const u8,
    owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, storage_type: []const u8, status: []const u8, content: []const []const u8, owned: bool) !Storage {
        if (owned) {
            var content_copy = try allocator.alloc([]const u8, content.len);
            for (content, 0..) |item, i| {
                content_copy[i] = try allocator.dupe(u8, item);
            }

            return Storage{
                .name = try allocator.dupe(u8, name),
                .type = try allocator.dupe(u8, storage_type),
                .status = try allocator.dupe(u8, status),
                .content = content_copy,
                .owned = true,
            };
        } else {
            return Storage{
                .name = name,
                .type = storage_type,
                .status = status,
                .content = content,
                .owned = false,
            };
        }
    }

    pub fn deinit(self: *Storage, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.name);
            allocator.free(self.type);
            allocator.free(self.status);
            for (self.content) |item| {
                allocator.free(item);
            }
            allocator.free(self.content);
        }
    }
};

pub fn scanZFS(client: *Client) ![][]const u8 {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/scan/zfs", .{client.node});
    defer client.allocator.free(path);

    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    var storages = ArrayList([]const u8).init(client.allocator);
    errdefer {
        for (storages.items) |storage| {
            client.allocator.free(storage);
        }
        storages.deinit();
    }

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |storage| {
            try storages.append(try client.allocator.dupe(u8, storage.string));
        }
    }

    return try storages.toOwnedSlice();
}

pub fn listStorage(client: *Client) ![]Storage {
    const path = "/storage";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var storages = ArrayList(Storage).init(client.allocator);
    errdefer {
        for (storages.items) |*storage| {
            storage.deinit(client.allocator);
        }
        storages.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |storage| {
            var content = ArrayList([]const u8).init(client.allocator);
            if (storage.object.get("content")) |content_array| {
                for (content_array.array.items) |item| {
                    try content.append(try client.allocator.dupe(u8, item.string));
                }
            }

            try storages.append(try Storage.init(
                client.allocator,
                storage.object.get("storage").?.string,
                storage.object.get("type").?.string,
                storage.object.get("status").?.string,
                try content.toOwnedSlice(),
                true,
            ));
        }
    }

    return try storages.toOwnedSlice();
}

pub fn listTemplates(client: *Client) ![]Template {
    const path = "/storage/local/template";
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    var templates = ArrayList(Template).init(client.allocator);
    errdefer {
        for (templates.items) |*template| {
            template.deinit(client.allocator);
        }
        templates.deinit();
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |template| {
            try templates.append(try Template.init(
                client.allocator,
                template.object.get("volid").?.string,
                template.object.get("size").?.integer,
                template.object.get("format").?.string,
                true,
            ));
        }
    }

    return try templates.toOwnedSlice();
}

pub const Template = struct {
    volid: []const u8,
    size: u64,
    format: []const u8,
    owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, volid: []const u8, size: u64, format: []const u8, owned: bool) !Template {
        if (owned) {
            return Template{
                .volid = try allocator.dupe(u8, volid),
                .size = size,
                .format = try allocator.dupe(u8, format),
                .owned = true,
            };
        } else {
            return Template{
                .volid = volid,
                .size = size,
                .format = format,
                .owned = false,
            };
        }
    }

    pub fn deinit(self: *Template, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.volid);
            allocator.free(self.format);
        }
    }
};
