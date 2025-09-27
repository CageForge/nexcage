const std = @import("std");
const zig_json = @import("zig_json");
const types = @import("types.zig");

pub const ManifestError = types.ImageError;

pub fn parseManifest(allocator: std.mem.Allocator, content: []const u8) !types.ImageManifest {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    var manifest = types.ImageManifest{
        .schemaVersion = @intCast(try getInt(obj, "schemaVersion")),
        .config = try parseDescriptor(obj, "config", allocator),
        .layers = try parseLayers(obj, "layers", allocator),
        .annotations = try parseAnnotations(obj, "annotations", allocator),
    };

    // Validate the parsed manifest
    try manifest.validate();

    return manifest;
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

    var descriptor = types.Descriptor{
        .mediaType = try getString(descriptor_obj, "mediaType"),
        .size = @intCast(try getInt(descriptor_obj, "size")),
        .digest = try getString(descriptor_obj, "digest"),
        .urls = try parseStringArray(descriptor_obj, "urls", allocator),
        .annotations = try parseAnnotations(descriptor_obj, "annotations", allocator),
        .platform = try parsePlatform(descriptor_obj, "platform", allocator),
    };

    // Validate the parsed descriptor
    try descriptor.validate();

    return descriptor;
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

fn parsePlatform(obj: *zig_json.Object, field: []const u8, _allocator: std.mem.Allocator) !?types.Platform {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const platform_obj = value.object();

    return types.Platform{
        .architecture = try getString(platform_obj, "architecture"),
        .os = try getString(platform_obj, "os"),
        .os_version = try getOptionalString(platform_obj, "os.version"),
        .os_features = try parseStringArray(platform_obj, "os.features", _allocator),
        .variant = try getOptionalString(platform_obj, "variant"),
        .features = try parseStringArray(platform_obj, "features", _allocator),
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

    const layers = try allocator.alloc(types.Descriptor, array.len());
    for (layers, 0..) |*layer, i| {
        const layer_value = array.get(i);
        if (layer_value.type != .object) return error.InvalidType;
        const layer_obj = layer_value.object();

        layer.* = types.Descriptor{
            .mediaType = try getString(layer_obj, "mediaType"),
            .size = @intCast(try getInt(layer_obj, "size")),
            .digest = try getString(layer_obj, "digest"),
            .urls = try parseStringArray(layer_obj, "urls", allocator),
            .annotations = try parseAnnotations(layer_obj, "annotations", allocator),
            .platform = try parsePlatform(layer_obj, "platform", allocator),
        };

        // Validate each layer
        try layer.validate();
    }

    return layers;
}

pub fn createManifest(
    _: std.mem.Allocator,
    config: types.Descriptor,
    layers: []types.Descriptor,
    annotations: ?std.StringHashMap([]const u8),
) !types.ImageManifest {
    var manifest = types.ImageManifest{
        .schemaVersion = 2, // OCI v1.0.2
        .config = config,
        .layers = layers,
        .annotations = annotations,
    };

    // Validate the created manifest
    try manifest.validate();

    return manifest;
}

pub fn serializeManifest(allocator: std.mem.Allocator, manifest: types.ImageManifest) ![]const u8 {
    return try zig_json.stringify(allocator, manifest, .{});
}

pub fn cloneManifest(allocator: std.mem.Allocator, manifest: *const types.ImageManifest) !types.ImageManifest {
    const cloned = types.ImageManifest{
        .schemaVersion = manifest.schemaVersion,
        .config = try cloneDescriptor(allocator, &manifest.config),
        .layers = try cloneDescriptors(allocator, manifest.layers),
        .annotations = if (manifest.annotations) |annotations|
            try cloneAnnotations(allocator, annotations)
        else
            null,
    };

    return cloned;
}

fn cloneDescriptor(allocator: std.mem.Allocator, descriptor: *const types.Descriptor) !types.Descriptor {
    const cloned = types.Descriptor{
        .mediaType = try allocator.dupe(u8, descriptor.mediaType),
        .size = descriptor.size,
        .digest = try allocator.dupe(u8, descriptor.digest),
        .urls = if (descriptor.urls) |urls|
            try cloneStringArray(allocator, urls)
        else
            null,
        .annotations = if (descriptor.annotations) |annotations|
            try cloneAnnotations(allocator, annotations)
        else
            null,
        .platform = if (descriptor.platform) |platform|
            try clonePlatform(allocator, &platform)
        else
            null,
    };

    return cloned;
}

fn cloneDescriptors(allocator: std.mem.Allocator, descriptors: []const types.Descriptor) ![]types.Descriptor {
    const cloned = try allocator.alloc(types.Descriptor, descriptors.len);
    for (cloned, 0..) |*cloned_desc, i| {
        cloned_desc.* = try cloneDescriptor(allocator, &descriptors[i]);
    }
    return cloned;
}

fn clonePlatform(allocator: std.mem.Allocator, platform: *const types.Platform) !types.Platform {
    const cloned = types.Platform{
        .architecture = try allocator.dupe(u8, platform.architecture),
        .os = try allocator.dupe(u8, platform.os),
        .os_version = if (platform.os_version) |version|
            try allocator.dupe(u8, version)
        else
            null,
        .os_features = if (platform.os_features) |features|
            try cloneStringArray(allocator, features)
        else
            null,
        .variant = if (platform.variant) |variant|
            try allocator.dupe(u8, variant)
        else
            null,
        .features = if (platform.features) |features|
            try cloneStringArray(allocator, features)
        else
            null,
    };

    return cloned;
}

fn cloneStringArray(allocator: std.mem.Allocator, strings: [][]const u8) ![][]const u8 {
    const cloned = try allocator.alloc([]const u8, strings.len);
    for (cloned, 0..) |*cloned_str, i| {
        cloned_str.* = try allocator.dupe(u8, strings[i]);
    }
    return cloned;
}

fn cloneAnnotations(allocator: std.mem.Allocator, annotations: std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
    var cloned = std.StringHashMap([]const u8).init(allocator);
    var it = annotations.iterator();
    while (it.next()) |entry| {
        try cloned.put(try allocator.dupe(u8, entry.key), try allocator.dupe(u8, entry.value));
    }
    return cloned;
}
