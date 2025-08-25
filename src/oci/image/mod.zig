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

// Advanced LayerFS types
pub const GarbageCollectionResult = layerfs.GarbageCollectionResult;
pub const GarbageCollectionError = layerfs.GarbageCollectionError;
pub const DetailedLayerFSStats = layerfs.DetailedLayerFSStats;
pub const LayerDetail = layerfs.LayerDetail;
pub const LayerOperation = layerfs.LayerOperation;
pub const BatchOperationResult = layerfs.BatchOperationResult;
pub const LayerOperationError = layerfs.LayerOperationError;

// New Advanced LayerFS types
pub const MetadataCacheEntry = layerfs.MetadataCacheEntry;
pub const MetadataCache = layerfs.MetadataCache;
pub const LayerObjectPool = layerfs.LayerObjectPool;
pub const ParallelProcessingContext = layerfs.ParallelProcessingContext;
pub const FileOperationResult = layerfs.FileOperationResult;
pub const AdvancedFileOps = layerfs.AdvancedFileOps;

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

// Advanced LayerFS functions
pub const garbageCollect = layerfs.garbageCollect;
pub const getDetailedStats = layerfs.getDetailedStats;
pub const batchLayerOperations = layerfs.batchLayerOperations;

// New Advanced LayerFS functions
pub const createMetadataCache = layerfs.MetadataCache.init;
pub const createLayerObjectPool = layerfs.LayerObjectPool.init;
pub const createParallelProcessingContext = layerfs.ParallelProcessingContext.init;
pub const createAdvancedFileOps = layerfs.AdvancedFileOps.init;

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
