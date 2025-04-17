const std = @import("std");
const types = @import("types");
const Client = @import("../client.zig").Client;
const json = std.json;
const fmt = std.fmt;
const ArrayList = std.ArrayList;

pub const Template = struct {
    volid: []const u8,
    format: []const u8,
    size: u64,
    hash: ?[]const u8,

    pub fn deinit(self: *Template, allocator: std.mem.Allocator) void {
        allocator.free(self.volid);
        allocator.free(self.format);
        if (self.hash) |h| {
            allocator.free(h);
        }
    }
};

pub fn listTemplates(client: *Client) ![]Template {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/storage/local/content", .{client.node});
    defer client.allocator.free(path);

    try client.logger.debug("Requesting templates list from node {s}", .{client.node});
    
    const response = try client.makeRequest(.GET, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.warn("Empty response when requesting templates", .{});
        return &[_]Template{};
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    var templates = ArrayList(Template).init(client.allocator);
    errdefer {
        for (templates.items) |*template| {
            template.deinit(client.allocator);
        }
        templates.deinit();
    }

    if (parsed.value.object.get("data")) |data| {
        for (data.array.items) |item| {
            if (std.mem.eql(u8, item.object.get("content").?.string, "vztmpl")) {
                try templates.append(Template{
                    .volid = try client.allocator.dupe(u8, item.object.get("volid").?.string),
                    .format = try client.allocator.dupe(u8, item.object.get("format").?.string),
                    .size = @intCast(item.object.get("size").?.integer),
                    .hash = if (item.object.get("hash")) |h| 
                        try client.allocator.dupe(u8, h.string)
                    else null,
                });
            }
        }
    }

    return templates.toOwnedSlice();
}

pub fn downloadTemplate(client: *Client, url: []const u8) !Template {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/storage/local/download-url", .{client.node});
    defer client.allocator.free(path);

    const body = try fmt.allocPrint(client.allocator, "{{\"url\":\"{s}\",\"verify-certificates\":true}}", .{url});
    defer client.allocator.free(body);

    try client.logger.debug("Downloading template from URL: {s}", .{url});
    
    const response = try client.makeRequest(.POST, path, body);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when downloading template", .{});
        return error.DownloadError;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |data| {
        return Template{
            .volid = try client.allocator.dupe(u8, data.object.get("volid").?.string),
            .format = try client.allocator.dupe(u8, "gz"),
            .size = 0,
            .hash = null,
        };
    } else {
        try client.logger.err("Invalid response format when downloading template: {s}", .{response});
        return error.DownloadError;
    }
}

pub fn deleteTemplate(client: *Client, volid: []const u8) !void {
    const path = try fmt.allocPrint(client.allocator, "/nodes/{s}/storage/local/content/{s}", .{ client.node, volid });
    defer client.allocator.free(path);

    try client.logger.debug("Deleting template: {s}", .{volid});
    
    const response = try client.makeRequest(.DELETE, path, null);
    defer client.allocator.free(response);

    if (response.len == 0) {
        try client.logger.err("Empty response when deleting template", .{});
        return error.DeleteError;
    }

    var parsed = try json.parseFromSlice(json.Value, client.allocator, response, .{});
    defer parsed.deinit();

    if (parsed.value.object.get("data")) |_| {
        try client.logger.info("Template {s} deleted successfully", .{volid});
    } else {
        try client.logger.err("Failed to delete template {s}: {s}", .{ volid, response });
        return error.DeleteError;
    }
} 