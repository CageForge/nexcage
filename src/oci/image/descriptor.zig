const std = @import("std");
const zig_json = @import("zig_json");
const types = @import("types.zig");

pub fn parseDescriptor(allocator: std.mem.Allocator, content: []const u8) !types.Descriptor {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    return types.Descriptor{
        .mediaType = try getString(obj, "mediaType"),
        .size = try getInt(obj, "size"),
        .digest = try getString(obj, "digest"),
        .urls = try parseStringArray(obj, "urls", allocator),
        .annotations = try parseAnnotations(obj, "annotations", allocator),
        .platform = try parsePlatform(obj, "platform", allocator),
    };
}

fn getString(obj: *zig_json.Object, field: []const u8) ![]const u8 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}

fn getInt(obj: *zig_json.Object, field: []const u8) !i64 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .integer) return error.InvalidType;
    return value.integer();
}

fn parseStringArray(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?[][]const u8 {
    const value = obj.get(field) orelse return null;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    const result = try allocator.alloc([]const u8, array.len());
    for (result, 0..) |*entry, i| {
        const entry_value = array.get(i);
        if (entry_value.type != .string) return error.InvalidType;
        entry.* = try allocator.dupe(u8, entry_value.string());
    }

    return result;
}

fn parseAnnotations(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?std.StringHashMap([]const u8) {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const annotations_obj = value.object();

    var annotations = std.StringHashMap([]const u8).init(allocator);
    var it = annotations_obj.iterator();
    while (it.next()) |entry| {
        if (entry.value.type != .string) return error.InvalidType;
        try annotations.put(entry.key, try allocator.dupe(u8, entry.value.string()));
    }

    return annotations;
}

fn parsePlatform(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?types.Platform {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const platform_obj = value.object();

    return types.Platform{
        .architecture = try getString(platform_obj, "architecture"),
        .os = try getString(platform_obj, "os"),
        .os_version = try getOptionalString(platform_obj, "os.version"),
        .os_features = try parseStringArray(platform_obj, "os.features", allocator),
        .variant = try getOptionalString(platform_obj, "variant"),
        .features = try parseStringArray(platform_obj, "features", allocator),
    };
}

fn getOptionalString(obj: *zig_json.Object, field: []const u8) !?[]const u8 {
    const value = obj.get(field) orelse return null;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}
