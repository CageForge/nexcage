const std = @import("std");
const types = @import("types");
const crypto = std.crypto;
const hash = crypto.hash;
const mem = std.mem;
const fs = std.fs;
const path = std.fs.path;

pub const LayerError = error{
    InvalidLayer,
    InvalidDigest,
    InvalidSize,
    InvalidMediaType,
    InvalidDigestFormat,
    InvalidDigestLength,
    InvalidAnnotations,
    LayerNotFound,
    LayerCorrupted,
    UnsupportedMediaType,
    InvalidLayerOrder,
    DependencyNotFound,
    IntegrityCheckFailed,
    MetadataError,
    StorageError,
};

/// OCI image layer
pub const Layer = struct {
    media_type: []const u8,
    digest: []const u8,
    size: u64,
    annotations: ?std.StringHashMap([]const u8),

    /// Create a new layer
    pub fn createLayer(
        allocator: std.mem.Allocator,
        media_type: []const u8,
        digest: []const u8,
        size: u64,
        annotations: ?std.StringHashMap([]const u8),
    ) !Layer {
        return Layer{
            .media_type = try allocator.dupe(u8, media_type),
            .digest = try allocator.dupe(u8, digest),
            .size = size,
            .annotations = annotations,
        };
    }

    /// Create a descriptor for this layer
    pub fn createDescriptor(layer: Layer) types.Descriptor {
        return types.Descriptor{
            .media_type = layer.media_type,
            .digest = layer.digest,
            .size = layer.size,
            .annotations = layer.annotations,
        };
    }
};
