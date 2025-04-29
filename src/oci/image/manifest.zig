const std = @import("std");
const types = @import("types.zig");
const json = std.json;

pub const ManifestError = error{
    InvalidManifest,
    InvalidDescriptor,
    InvalidConfig,
    InvalidLayer,
    InvalidPlatform,
};

pub fn parseManifest(allocator: std.mem.Allocator, data: []const u8) !types.ImageManifest {
    var parsed = try json.parseFromSlice(types.ImageManifest, allocator, data, .{});
    defer parsed.deinit();
    
    // Validate required fields
    if (parsed.value.schemaVersion != 2) {
        return ManifestError.InvalidManifest;
    }
    
    // Validate config descriptor
    try validateDescriptor(parsed.value.config);
    
    // Validate layers
    for (parsed.value.layers) |layer| {
        try validateDescriptor(layer);
    }
    
    return parsed.value;
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
    return try json.stringifyAlloc(allocator, manifest, .{});
} 