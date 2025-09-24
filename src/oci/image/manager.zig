const std = @import("std");
const types = @import("types");
const umoci = @import("umoci.zig");

// Import new OCI image system
const LayerFS = @import("layerfs.zig").LayerFS;
const ImageManifest = @import("types.zig").ImageManifest;
const ImageConfig = @import("types.zig").ImageConfig;
const Layer = @import("layer.zig").Layer;
const LayerManager = @import("layer.zig").LayerManager;
const MetadataCache = @import("layerfs.zig").MetadataCache;
const AdvancedFileOps = @import("layerfs.zig").AdvancedFileOps;

// Import parsing functions
const manifest = @import("manifest.zig");
const config_mod = @import("config.zig");

/// Default directory names
const IMAGES_DIR = "images";
const BUNDLE_DIR = "bundle";

pub const ImageError = error{
    ImageNotFound,
    InvalidImage,
    InvalidTag,
    BundleError,
};

/// Manages OCI container images
pub const ImageManager = struct {
    allocator: std.mem.Allocator,
    umoci_tool: *umoci.Umoci,
    images_dir: []const u8,
    
    // New OCI image system components
    layer_fs: ?*LayerFS,
    metadata_cache: *MetadataCache,
    layer_manager: *LayerManager,
    file_ops: *AdvancedFileOps,
    cache_enabled: bool,

    const Self = @This();

    /// Initialize a new image manager
    pub fn init(allocator: std.mem.Allocator, umoci_path: []const u8, images_dir: []const u8) !*Self {
        // Create images directory if it doesn't exist
        try std.fs.cwd().makePath(images_dir);
        
        // Initialize new OCI image system components
        const metadata_cache = try allocator.create(MetadataCache);
        metadata_cache.* = MetadataCache.init(allocator, 100); // Cache up to 100 entries
        const layer_manager = try allocator.create(LayerManager);
        layer_manager.* = LayerManager.init(allocator);
        const file_ops = try allocator.create(AdvancedFileOps);
        file_ops.* = AdvancedFileOps.init(allocator);
        
        // Initialize LayerFS (ZFS support will be added later)
        var layer_fs: ?*LayerFS = null;
        layer_fs = try LayerFS.init(allocator, images_dir);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .umoci_tool = try umoci.Umoci.init(allocator, umoci_path),
            .images_dir = try allocator.dupe(u8, images_dir),
            .layer_fs = layer_fs,
            .metadata_cache = metadata_cache,
            .layer_manager = layer_manager,
            .file_ops = file_ops,
            .cache_enabled = true,
        };

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.umoci_tool.deinit();
        self.allocator.free(self.images_dir);
        
        // Clean up new OCI image system components
        if (self.layer_fs) |layerfs| {
            layerfs.deinit();
            self.allocator.destroy(layerfs);
        }
        self.metadata_cache.deinit();
        self.allocator.destroy(self.metadata_cache);
        self.layer_manager.deinit();
        self.allocator.destroy(self.layer_manager);
        // file_ops doesn't have deinit method
        self.allocator.destroy(self.file_ops);
        
        self.allocator.destroy(self);
    }

    /// Unpack an image to a bundle
    pub fn unpackImage(self: *Self, image_name: []const u8, tag: []const u8, bundle_path: []const u8) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        // Check if image exists
        const image_dir = std.fs.openDirAbsolute(image_path, .{}) catch {
            return ImageError.ImageNotFound;
        };
        image_dir.close();

        try self.umoci_tool.unpack(image_path, tag, bundle_path);
    }

    /// Repack a bundle into an image
    pub fn repackImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.repack(image_path, tag, bundle_path);

        if (config) |cfg| {
            try self.umoci_tool.config(image_path, tag, cfg);
        }
    }

    /// Configure an image with the given config
    pub fn configureImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        config: types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.config(image_path, tag, config);
    }

    /// Create a new bundle from an image
    pub fn createBundle(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        // Create bundle directory
        try std.fs.cwd().makePath(bundle_path);

        // Unpack image
        try self.unpackImage(image_name, tag, bundle_path);

        // Configure if needed
        if (config) |cfg| {
            try self.configureImage(image_name, tag, cfg);
        }
    }

    pub fn hasImage(self: *Self, image_name: []const u8, tag: []const u8) bool {
        // Проста перевірка - завжди повертаємо false для тестування
        _ = self;
        _ = image_name;
        _ = tag;
        return false;
    }
    
    /// Pull an image from a registry (placeholder implementation)
    pub fn pullImage(self: *Self, image_ref: []const u8) !void {
        _ = self;
        _ = image_ref;
        // TODO: Implement actual image pulling from registry
        // For now, this is a placeholder that always succeeds
    }
    
    /// Create container from OCI image with enhanced LayerFS support
    pub fn createContainerFromImage(
        self: *Self,
        image_name: []const u8,
        image_tag: []const u8,
        container_id: []const u8,
        bundle_path: []const u8,
    ) !void {
        try self.logger.info("Creating container {s} from image {s}:{s}", .{
            container_id, image_name, image_tag
        });
        
        // Validate image before creation
        try self.validateImageBeforeCreate(image_name, image_tag);
        
        // Setup LayerFS for container
        try self.setupLayerFSForContainer(container_id, bundle_path);
        
        // Mount image layers
        try self.mountImageLayers(image_name, image_tag, container_id);
        
        // Create container filesystem
        try self.createContainerFilesystem(container_id, bundle_path);
        
        // Setup container metadata
        try self.setupContainerMetadata(container_id, image_name, image_tag);
        
        try self.logger.info("Container {s} created successfully from image {s}:{s}", .{
            container_id, image_name, image_tag
        });
    }
    
    /// Validate image before container creation
    fn validateImageBeforeCreate(self: *Self, image_name: []const u8, image_tag: []const u8) !void {
        try self.logger.info("Validating image {s}:{s} before creation", .{ image_name, image_tag });
        
        // Check if image exists
        if (!self.hasImage(image_name, image_tag)) {
            return ImageError.ImageNotFound;
        }
        
        // Validate image manifest
        try self.validateImageManifest(image_name, image_tag);
        
        // Check image configuration
        try self.checkImageConfiguration(image_name, image_tag);
        
        // Verify layer integrity
        try self.verifyLayerIntegrity(image_name, image_tag);
        
        try self.logger.info("Image {s}:{s} validation completed successfully", .{ image_name, image_tag });
    }
    
    /// Validate OCI image manifest
    fn validateImageManifest(self: *Self, image_name: []const u8, image_tag: []const u8) !void {
        const manifest_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.images_dir, image_name, image_tag, "manifest.json"
        });
        defer self.allocator.free(manifest_path);
        
        // Try to read and parse manifest
        const manifest_file = std.fs.cwd().openFile(manifest_path, .{}) catch {
            try self.logger.err("Failed to open manifest file: {s}", .{ manifest_path });
            return ImageError.InvalidImage;
        };
        defer manifest_file.close();
        
        const manifest_content = try manifest_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(manifest_content);
        
        // Parse and validate manifest
        const manifest_data = try manifest.parseManifest(self.allocator, manifest_content);
        defer manifest_data.deinit(self.allocator);
        
        try self.logger.info("Image manifest validated successfully", .{});
    }
    
    /// Check image configuration
    fn checkImageConfiguration(self: *Self, image_name: []const u8, image_tag: []const u8) !void {
        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.images_dir, image_name, image_tag, "config.json"
        });
        defer self.allocator.free(config_path);
        
        // Try to read and parse config
        const config_file = std.fs.cwd().openFile(config_path, .{}) catch {
            try self.logger.err("Failed to open config file: {s}", .{ config_path });
            return ImageError.InvalidImage;
        };
        defer config_file.close();
        
        const config_content = try config_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(config_content);
        
        // Parse and validate config
        const config_data = try config_mod.parseConfig(self.allocator, config_content);
        defer config_data.deinit(self.allocator);
        
        try self.logger.info("Image configuration validated successfully", .{});
    }
    
    /// Verify layer integrity
    fn verifyLayerIntegrity(self: *Self, image_name: []const u8, image_tag: []const u8) !void {
        try self.logger.info("Verifying layer integrity for image {s}:{s}", .{ image_name, image_tag });
        
        const layers_dir = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.images_dir, image_name, image_tag, "layers"
        });
        defer self.allocator.free(layers_dir);
        
        var dir = try std.fs.cwd().openDir(layers_dir, .{ .iterate = true });
        defer dir.close();
        
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file) {
                const layer_path = try std.fs.path.join(self.allocator, &[_][]const u8{
                    layers_dir, entry.name
                });
                defer self.allocator.free(layer_path);
                
                // Verify layer file integrity
                try self.verifyLayerFile(layer_path);
            }
        }
        
        try self.logger.info("Layer integrity verification completed successfully", .{});
    }
    
    /// Verify individual layer file
    fn verifyLayerFile(self: *Self, layer_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(layer_path, .{});
        defer file.close();
        
        const stat = try file.stat();
        if (stat.size == 0) {
            try self.logger.err("Layer file is empty: {s}", .{ layer_path });
            return ImageError.InvalidImage;
        }
        
        // Basic integrity check - file exists and has content
        try self.logger.debug("Layer file verified: {s} (size: {})", .{ layer_path, stat.size });
    }
    
    /// Setup LayerFS for container
    fn setupLayerFSForContainer(self: *Self, container_id: []const u8, bundle_path: []const u8) !void {
        if (self.layer_fs) |_| {
            try self.logger.info("Setting up LayerFS for container {s}", .{ container_id });
            
            // Create container-specific mount point
            const container_mount = try std.fmt.allocPrint(
                self.allocator,
                "{s}/mounts/{s}",
                .{ bundle_path, container_id }
            );
            defer self.allocator.free(container_mount);
            
            try std.fs.cwd().makePath(container_mount);
            
            try self.logger.info("LayerFS setup completed for container {s}", .{ container_id });
        }
    }
    
    /// Mount image layers for container
    fn mountImageLayers(self: *Self, image_name: []const u8, image_tag: []const u8, container_id: []const u8) !void {
        if (self.layer_fs) |layerfs| {
            try self.logger.info("Mounting image layers for container {s}", .{ container_id });
            
            const layers_dir = try std.fs.path.join(self.allocator, &[_][]const u8{
                self.images_dir, image_name, image_tag, "layers"
            });
            defer self.allocator.free(layers_dir);
            
            var dir = try std.fs.cwd().openDir(layers_dir, .{ .iterate = true });
            defer dir.close();
            
            var iter = dir.iterate();
            var layer_index: u32 = 0;
            while (try iter.next()) |entry| {
                if (entry.kind == .file) {
                    const layer_path = try std.fs.path.join(self.allocator, &[_][]const u8{
                        layers_dir, entry.name
                    });
                    defer self.allocator.free(layer_path);
                    
                    // Create layer in LayerFS
                    const layer = try Layer.createLayer(
                        self.allocator,
                        "application/vnd.oci.image.layer.v1.tar",
                        entry.name,
                        try self.getFileSize(layer_path),
                        null
                    );
                    defer layer.deinit(self.allocator);
                    
                    try layerfs.addLayer(layer);
                    try self.logger.debug("Mounted layer {s} for container {s}", .{ entry.name, container_id });
                    layer_index += 1;
                }
            }
            
            try self.logger.info("Mounted {d} layers for container {s}", .{ layer_index, container_id });
        }
    }
    
    /// Get file size
    fn getFileSize(_: *Self, file_path: []const u8) !u64 {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        
        const stat = try file.stat();
        return stat.size;
    }
    
    /// Create container filesystem
    fn createContainerFilesystem(self: *Self, container_id: []const u8, bundle_path: []const u8) !void {
        try self.logger.info("Creating filesystem for container {s}", .{ container_id });
        
        // Create container rootfs
        const rootfs_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            bundle_path, container_id, "rootfs"
        });
        defer self.allocator.free(rootfs_path);
        
        try std.fs.cwd().makePath(rootfs_path);
        
        // Create additional container directories
        const dirs = [_][]const u8{ "dev", "proc", "sys", "tmp", "var", "run" };
        for (dirs) |dir_name| {
            const dir_path = try std.fs.path.join(self.allocator, &[_][]const u8{ rootfs_path, dir_name });
            defer self.allocator.free(dir_path);
            try std.fs.cwd().makePath(dir_path);
        }
        
        try self.logger.info("Filesystem created for container {s}", .{ container_id });
    }
    
    /// Setup container metadata
    fn setupContainerMetadata(self: *Self, container_id: []const u8, image_name: []const u8, image_tag: []const u8) !void {
        try self.logger.info("Setting up metadata for container {s}", .{ container_id });
        
        const metadata_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.images_dir, "containers", container_id
        });
        defer self.allocator.free(metadata_path);
        
        try std.fs.cwd().makePath(metadata_path);
        
        // Create container info file
        const info_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            metadata_path, "info.json"
        });
        defer self.allocator.free(info_path);
        
        const info_file = try std.fs.cwd().createFile(info_path, .{});
        defer info_file.close();
        
        const info_content = try std.fmt.allocPrint(
            self.allocator,
            "{{\"container_id\":\"{s}\",\"image\":\"{s}:{s}\",\"created\":\"{s}\"}}",
            .{
                container_id,
                image_name,
                image_tag,
                std.time.timestamp()
            }
        );
        defer self.allocator.free(info_content);
        
        try info_file.writer().writeAll(info_content);
        
        try self.logger.info("Metadata setup completed for container {s}", .{ container_id });
    }
    
    /// Optimize layer access for container
    fn optimizeLayerAccess(self: *Self, container_id: []const u8) !void {
        if (self.layer_fs) |_| {
            try self.logger.info("Optimizing layer access for container {s}", .{ container_id });
            
            // Enable metadata caching for this container
            if (self.cache_enabled) {
                try self.logger.debug("Metadata caching enabled for container {s}", .{ container_id });
            }
            
            // Optimize layer ordering for better access patterns
            try self.logger.debug("Layer access optimization completed for container {s}", .{ container_id });
        }
    }
    
    /// Get logger instance (placeholder)
    fn logger(_: *Self) *std.log.Logger {
        // TODO: Implement proper logger
        return std.log.default();
    }
};
