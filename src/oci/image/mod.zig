// OCI Image System Module
// Exports all image-related functionality

pub const types = @import("types.zig");
pub const manifest = @import("manifest.zig");
pub const config = @import("config.zig");
pub const descriptor = @import("descriptor.zig");
pub const index = @import("index.zig");
pub const layer = @import("layer.zig");
pub const manager = @import("manager.zig");
pub const raw = @import("raw.zig");
pub const umoci = @import("umoci.zig");

// Re-export commonly used types
pub const ImageManifest = types.ImageManifest;
pub const ImageConfig = types.ImageConfig;
pub const Descriptor = types.Descriptor;
pub const Platform = types.Platform;
pub const ImageError = types.ImageError;
pub const ImageManager = manager.ImageManager;

// Re-export commonly used functions
pub const parseManifest = manifest.parseManifest;
pub const createManifest = manifest.createManifest;
pub const serializeManifest = manifest.serializeManifest;
pub const cloneManifest = manifest.cloneManifest;

// Test exports
test {
    _ = types;
    _ = manifest;
    _ = config;
    _ = descriptor;
    _ = index;
    _ = layer;
    _ = manager;
    _ = raw;
    _ = umoci;
}
