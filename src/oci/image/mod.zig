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

// Re-export configuration types
pub const HealthCheck = config.HealthCheck;
pub const Volume = config.Volume;
pub const MountPoint = config.MountPoint;
pub const ConfigError = config.ConfigError;

// Re-export commonly used functions
pub const parseManifest = manifest.parseManifest;
pub const createManifest = manifest.createManifest;
pub const serializeManifest = manifest.serializeManifest;
pub const cloneManifest = manifest.cloneManifest;

// Re-export configuration functions
pub const parseConfig = config.parseConfig;
pub const createConfig = config.createConfig;
pub const createContainerConfig = config.createContainerConfig;
pub const createHealthCheck = config.createHealthCheck;
pub const createVolume = config.createVolume;
pub const createMountPoint = config.createMountPoint;
pub const serializeConfig = config.serializeConfig;
pub const validateContainerConfig = config.validateContainerConfig;
pub const validateImageConfig = config.validateImageConfig;
pub const parseExposedPortsFromArray = config.parseExposedPortsFromArray;
pub const parseVolumesFromArray = config.parseVolumesFromArray;

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
