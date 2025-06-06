const std = @import("std");
const zig_json = @import("zig_json");
const types = @import("types.zig");

pub const ManifestError = error{
    InvalidManifest,
    InvalidDescriptor,
    InvalidConfig,
    InvalidLayer,
    InvalidPlatform,
};

pub fn parseManifest(allocator: std.mem.Allocator, content: []const u8) !types.ImageManifest {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    return types.ImageManifest{
        .schemaVersion = try getInt(obj, "schemaVersion"),
        .config = try parseDescriptor(obj, "config", allocator),
        .layers = try parseLayers(obj, "layers", allocator),
        .annotations = try parseAnnotations(obj, "annotations", allocator),
    };
}

fn getInt(obj: *zig_json.Object, field: []const u8) !i64 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .integer) return error.InvalidType;
    return value.integer();
}

fn getString(obj: *zig_json.Object, field: []const u8) ![]const u8 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}

fn parseDescriptor(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !types.Descriptor {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .object) return error.InvalidType;
    const descriptor_obj = value.object();

    return types.Descriptor{
        .mediaType = try getString(descriptor_obj, "mediaType"),
        .size = try getInt(descriptor_obj, "size"),
        .digest = try getString(descriptor_obj, "digest"),
        .urls = try parseStringArray(descriptor_obj, "urls", allocator),
        .annotations = try parseAnnotations(descriptor_obj, "annotations", allocator),
        .platform = try parsePlatform(descriptor_obj, "platform", allocator),
    };
}

fn parseStringArray(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?[][]const u8 {
    const value = obj.get(field) orelse return null;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    var result = try allocator.alloc([]const u8, array.len());
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

fn parseLayers(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) ![]types.Descriptor {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    var layers = try allocator.alloc(types.Descriptor, array.len());
    for (layers, 0..) |*layer, i| {
        const layer_value = array.get(i);
        if (layer_value.type != .object) return error.InvalidType;
        const layer_obj = layer_value.object();

        layer.* = types.Descriptor{
            .mediaType = try getString(layer_obj, "mediaType"),
            .size = try getInt(layer_obj, "size"),
            .digest = try getString(layer_obj, "digest"),
            .urls = try parseStringArray(layer_obj, "urls", allocator),
            .annotations = try parseAnnotations(layer_obj, "annotations", allocator),
            .platform = try parsePlatform(layer_obj, "platform", allocator),
        };
    }

    return layers;
}

fn validateDescriptor(descriptor: types.Descriptor) !void {
    if (descriptor.mediaType.len == 0 or descriptor.digest.len == 0 or descriptor.size < 0) {
        return ManifestError.InvalidDescriptor;
    }
}

pub fn createManifest(
    allocator: std.mem.Allocator,
    config: types.Descriptor,
    layers: []types.Descriptor,
    annotations: ?std.StringHashMap([]const u8),
) !types.ImageManifest {
    // Validate config descriptor
    try validateDescriptor(config);

    // Validate layers
    for (layers) |layer| {
        try validateDescriptor(layer);
    }

    return types.ImageManifest{
        .config = config,
        .layers = layers,
        .annotations = annotations,
    };
}

pub fn serializeManifest(allocator: std.mem.Allocator, manifest: types.ImageManifest) ![]const u8 {
    return try zig_json.stringify(allocator, manifest, .{});
}
