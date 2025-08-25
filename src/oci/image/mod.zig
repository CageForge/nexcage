// OCI Image System Module
// Exports all image-related functionality

pub const types = @import("types.zig");
pub const manifest = @import("manifest.zig");
pub const config = @import("config.zig");
pub const descriptor = @import("descriptor.zig");
pub const index = @import("index.zig");
pub const layer = @import("layer.zig");
pub const layerfs = @import("layerfs.zig");
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

// Re-export layer types
pub const Layer = layer.Layer;
pub const LayerManager = layer.LayerManager;
pub const LayerError = layer.LayerError;

// Re-export layerfs types
pub const LayerFS = layerfs.LayerFS;
pub const LayerFSStats = layerfs.LayerFSStats;
pub const LayerFSError = layerfs.LayerFSError;

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

// Re-export layer functions
pub const createLayer = layer.Layer.createLayer;
pub const createLayerWithMetadata = layer.Layer.createLayerWithMetadata;
pub const createDescriptor = layer.Layer.createDescriptor;
pub const validate = layer.Layer.validate;
pub const verifyIntegrity = layer.Layer.verifyIntegrity;
pub const addDependency = layer.Layer.addDependency;
pub const removeDependency = layer.Layer.removeDependency;
pub const dependsOn = layer.Layer.dependsOn;
pub const clone = layer.Layer.clone;
pub const initLayerManager = layer.LayerManager.init;

// Re-export layerfs functions
pub const createLayerFS = layerfs.createLayerFS;
pub const initLayerFS = layerfs.initLayerFS;

// Test exports
test {
    _ = types;
    _ = manifest;
    _ = config;
    _ = descriptor;
    _ = index;
    _ = layer;
    _ = layerfs;
    _ = manager;
    _ = raw;
    _ = umoci;
}
