const std = @import("std");
const zig_json = @import("zig_json");
const types = @import("types.zig");

pub fn parseIndex(allocator: std.mem.Allocator, content: []const u8) !types.ImageIndex {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    const index = types.ImageIndex{
        .schemaVersion = try getInt(obj, "schemaVersion"),
        .manifests = try parseManifests(obj, "manifests", allocator),
    };

    return index;
}

fn getInt(obj: *zig_json.Object, field: []const u8) !i64 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .integer) return error.InvalidType;
    return value.integer();
}

fn parseManifests(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) ![]types.ManifestDescriptor {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    const manifests = try allocator.alloc(types.ManifestDescriptor, array.len());
    for (manifests, 0..) |*manifest, i| {
        const manifest_value = array.get(i);
        if (manifest_value.type != .object) return error.InvalidType;
        const manifest_obj = manifest_value.object();

        manifest.* = types.ManifestDescriptor{
            .mediaType = try getString(manifest_obj, "mediaType"),
            .size = try getInt(manifest_obj, "size"),
            .digest = try getString(manifest_obj, "digest"),
            .platform = try parsePlatform(manifest_obj, "platform", allocator),
        };
    }

    return manifests;
}

fn getString(obj: *zig_json.Object, field: []const u8) ![]const u8 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .string) return error.InvalidType;
    return value.string();
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