const std = @import("std");
const types = @import("types.zig");
const fs = std.fs;
const crypto = std.crypto;
const Sha256 = crypto.hash.sha2.Sha256;

pub const LayerError = error{
    InvalidLayer,
    InvalidCompression,
    InvalidMediaType,
    FileError,
};

pub const Layer = struct {
    path: []const u8,
    compressed_size: i64,
    uncompressed_size: i64,
    digest: []const u8,
    media_type: []const u8,
    diff_id: []const u8,
};

pub fn createLayer(
    allocator: std.mem.Allocator,
    path: []const u8,
    media_type: []const u8,
) !Layer {
    const file = try fs.openFileAbsolute(path, .{});
    defer file.close();
    
    const stat = try file.stat();
    const compressed_size = stat.size;
    
    // Calculate SHA256 of the layer
    var hasher = Sha256.init(.{});
    var buffer: [8192]u8 = undefined;
    
    while (true) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }
    
    var hash: [Sha256.digest_length]u8 = undefined;
    hasher.final(&hash);
    
    const digest = try std.fmt.allocPrint(allocator, "sha256:{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    
    return Layer{
        .path = path,
        .compressed_size = compressed_size,
        .uncompressed_size = compressed_size, // For now assume same size
        .digest = digest,
        .media_type = media_type,
        .diff_id = digest, // For now assume same as digest
    };
}

pub fn createDescriptor(layer: Layer) types.Descriptor {
    return types.Descriptor{
        .mediaType = layer.media_type,
        .digest = layer.digest,
        .size = layer.compressed_size,
    };
}

pub fn validateLayer(layer: Layer) !void {
    if (layer.compressed_size <= 0 or layer.uncompressed_size <= 0) {
        return LayerError.InvalidLayer;
    }
    
    if (!std.mem.startsWith(u8, layer.media_type, "application/vnd.oci.image.layer.")) {
        return LayerError.InvalidMediaType;
    }
} 