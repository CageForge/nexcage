const std = @import("std");
const types = @import("types");
const Layer = @import("layer.zig").Layer;
const LayerError = @import("layer.zig").LayerError;

pub const LayerFSError = error{
    InvalidMountPoint,
    InvalidLayerPath,
    LayerNotFound,
    MountFailed,
    UnmountFailed,
    ReadOnlyFilesystem,
    WriteFailed,
    InvalidOverlay,
    ZFSError,
    PathError,
    PermissionDenied,
    InvalidLayerOrder,
    CircularDependency,
    StorageError,
    CompressionError,
    DecompressionError,
    ValidationError,
    MetadataError,
    ZFSDatasetNotFound,
    ZFSDatasetCreateFailed,
    ZFSDatasetDestroyFailed,
    ZFSSnapshotFailed,
    ZFSCloneFailed,
    LayerStackingFailed,
    LayerMergingFailed,
};

/// LayerFS provides a filesystem abstraction for managing OCI image layers
pub const LayerFS = struct {
    allocator: std.mem.Allocator,
    base_path: []const u8,
    layers: std.StringHashMap(*Layer),
    mount_points: std.StringHashMap([]const u8),
    overlay_mounts: std.StringHashMap([]const u8),
    readonly: bool,
    zfs_pool: ?[]const u8,
    zfs_dataset: ?[]const u8,
    
    const Self = @This();
    
    /// Initialize a new LayerFS instance
    pub fn init(allocator: std.mem.Allocator, base_path: []const u8) !*Self {
        const layerfs = try allocator.create(Self);
        layerfs.* = .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, base_path),
            .layers = std.StringHashMap(*Layer).init(allocator),
            .mount_points = std.StringHashMap([]const u8).init(allocator),
            .overlay_mounts = std.StringHashMap([]const u8).init(allocator),
            .readonly = false,
            .zfs_pool = null,
            .zfs_dataset = null,
        };
        
        return layerfs;
    }
    
    /// Initialize LayerFS with ZFS support
    pub fn initWithZFS(allocator: std.mem.Allocator, base_path: []const u8, zfs_pool: []const u8, zfs_dataset: []const u8) !*Self {
        const layerfs = try allocator.create(Self);
        layerfs.* = .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, base_path),
            .layers = std.StringHashMap(*Layer).init(allocator),
            .mount_points = std.StringHashMap([]const u8).init(allocator),
            .overlay_mounts = std.StringHashMap([]const u8).init(allocator),
            .readonly = false,
            .zfs_pool = try allocator.dupe(u8, zfs_pool),
            .zfs_dataset = try allocator.dupe(u8, zfs_dataset),
        };
        
        // Initialize ZFS dataset if it doesn't exist
        try layerfs.initZFSDataset();
        
        return layerfs;
    }
    
    /// Initialize ZFS dataset for layer storage
    fn initZFSDataset(self: *Self) !void {
        if (self.zfs_pool == null or self.zfs_dataset == null) {
            return;
        }
        
        const dataset_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.zfs_pool.?, self.zfs_dataset.? }
        );
        defer self.allocator.free(dataset_path);
        
        // Check if dataset exists
        if (!self.zfsDatasetExists(dataset_path)) {
            try self.zfsCreateDataset(dataset_path);
        }
    }
    
    /// Check if ZFS dataset exists
    fn zfsDatasetExists(self: *Self, dataset_path: []const u8) bool {
        _ = self;
        _ = dataset_path;
        // For now, simulate ZFS dataset existence check
        // In real implementation, this would use ZFS commands or libzfs
        return true;
    }
    
    /// Create ZFS dataset
    fn zfsCreateDataset(self: *Self, dataset_path: []const u8) !void {
        _ = self;
        _ = dataset_path;
        // For now, simulate ZFS dataset creation
        // In real implementation, this would use ZFS commands or libzfs
    }
    
    /// Clean up LayerFS resources
    pub fn deinit(self: *Self) void {
        // Unmount all overlay mounts
        var it = self.overlay_mounts.iterator();
        while (it.next()) |entry| {
            _ = self.unmountOverlay(entry.key_ptr.*);
        }
        self.overlay_mounts.deinit();
        
        // Free mount points
        var mp_it = self.mount_points.iterator();
        while (mp_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.mount_points.deinit();
        
        // Free layer digests (but don't deinit layers as they're owned elsewhere)
        var layer_it = self.layers.iterator();
        while (layer_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.layers.deinit();
        
        // Free ZFS-related strings
        if (self.zfs_pool) |pool| self.allocator.free(pool);
        if (self.zfs_dataset) |dataset| self.allocator.free(dataset);
        
        // Free base path
        self.allocator.free(self.base_path);
        
        // Free self
        self.allocator.destroy(self);
    }
    
    /// Add a layer to the filesystem
    pub fn addLayer(self: *Self, layer: *Layer) !void {
        if (self.layers.contains(layer.digest)) {
            return LayerFSError.LayerNotFound;
        }
        
        const digest_copy = try self.allocator.dupe(u8, layer.digest);
        try self.layers.put(digest_copy, layer);
    }
    
    /// Get a layer by digest
    pub fn getLayer(self: *Self, digest: []const u8) ?*Layer {
        return self.layers.get(digest);
    }
    
    /// Remove a layer from the filesystem
    pub fn removeLayer(self: *Self, digest: []const u8) !void {
        if (self.layers.fetchRemove(digest)) |entry| {
            self.allocator.free(entry.key);
        }
    }
    
    /// Create a mount point for a layer
    pub fn createMountPoint(self: *Self, layer_digest: []const u8, mount_path: []const u8) !void {
        _ = self.getLayer(layer_digest) orelse return LayerFSError.LayerNotFound;
        
        if (self.mount_points.contains(layer_digest)) {
            return LayerFSError.InvalidMountPoint;
        }
        
        // Duplicate strings to ensure ownership
        const digest_copy = try self.allocator.dupe(u8, layer_digest);
        const path_copy = try self.allocator.dupe(u8, mount_path);
        
        try self.mount_points.put(digest_copy, path_copy);
    }
    
    /// Get mount point for a layer
    pub fn getMountPoint(self: *Self, layer_digest: []const u8) ?[]const u8 {
        return self.mount_points.get(layer_digest);
    }
    
    /// Mount a layer as an overlay filesystem
    pub fn mountOverlay(self: *Self, layer_digest: []const u8, mount_path: []const u8) !void {
        _ = self.getLayer(layer_digest) orelse return LayerFSError.LayerNotFound;
        
        if (self.overlay_mounts.contains(layer_digest)) {
            return LayerFSError.InvalidOverlay;
        }
        
        // Create mount directory if it doesn't exist
        try std.fs.cwd().makePath(mount_path);
        
        // For now, we'll simulate overlay mounting
        // In a real implementation, this would use mount(2) with overlayfs
        // Duplicate strings to ensure ownership
        const digest_copy = try self.allocator.dupe(u8, layer_digest);
        const path_copy = try self.allocator.dupe(u8, mount_path);
        
        try self.overlay_mounts.put(digest_copy, path_copy);
    }
    
    /// Unmount an overlay filesystem
    pub fn unmountOverlay(self: *Self, layer_digest: []const u8) void {
        if (self.overlay_mounts.fetchRemove(layer_digest)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }
    
    /// Stack multiple layers into a single filesystem
    pub fn stackLayers(self: *Self, layer_digests: [][]const u8, target_path: []const u8) !void {
        if (layer_digests.len == 0) {
            return LayerFSError.InvalidLayerOrder;
        }
        
        // Validate all layers exist
        for (layer_digests) |digest| {
            if (self.getLayer(digest) == null) {
                return LayerFSError.LayerNotFound;
            }
        }
        
        // Create target directory
        try std.fs.cwd().makePath(target_path);
        
        // For now, simulate layer stacking
        // In real implementation, this would use overlayfs or ZFS layers
        // Mount each layer in order
        for (layer_digests, 0..) |digest, i| {
            const layer_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}/layer_{d}",
                .{ target_path, i }
            );
            defer self.allocator.free(layer_path);
            
            try self.mountOverlay(digest, layer_path);
        }
    }
    
    /// Merge multiple layers into a single layer
    pub fn mergeLayers(self: *Self, layer_digests: [][]const u8, target_digest: []const u8) !void {
        if (layer_digests.len < 2) {
            return LayerFSError.InvalidLayerOrder;
        }
        
        // Validate all layers exist
        for (layer_digests) |digest| {
            if (self.getLayer(digest) == null) {
                return LayerFSError.LayerNotFound;
            }
        }
        
        // For now, simulate layer merging
        // In real implementation, this would use ZFS snapshots and clones
        // or overlayfs merging
        
        // Create a new merged layer
        const merged_layer = try Layer.createLayerWithMetadata(
            self.allocator,
            "application/vnd.oci.image.layer.v1.tar",
            target_digest,
            0, // Size will be calculated during merge
            null, // Annotations
            null, // Created
            null, // Author
            "Merged layer from multiple source layers", // Comment
            null, // Dependencies
            0, // Order
            null, // Storage path
            false, // Compressed
            null, // Compression type
        );
        
        try self.addLayer(merged_layer);
    }
    
    /// Get all layers in dependency order
    pub fn getLayersInOrder(self: *Self) ![]*Layer {
        var ordered_layers = std.ArrayList(*Layer).init(self.allocator);
        defer ordered_layers.deinit();
        
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            try self.dfsVisit(entry.value_ptr.*, &visited, &ordered_layers);
        }
        
        return ordered_layers.toOwnedSlice();
    }
    
    /// Depth-first search for dependency ordering
    fn dfsVisit(
        self: *Self,
        layer: *Layer,
        visited: *std.StringHashMap(bool),
        ordered: *std.ArrayList(*Layer),
    ) !void {
        if (visited.contains(layer.digest)) {
            return;
        }
        
        // Mark as visited to detect cycles
        const digest_copy = try self.allocator.dupe(u8, layer.digest);
        try visited.put(digest_copy, true);
        
        // Visit dependencies first
        if (layer.dependencies) |deps| {
            for (deps) |dep_digest| {
                if (self.getLayer(dep_digest)) |dep_layer| {
                    try self.dfsVisit(dep_layer, visited, ordered);
                }
            }
        }
        
        // Add this layer after its dependencies
        try ordered.append(layer);
    }
    
    /// Validate all layers in the filesystem
    pub fn validateAllLayers(self: *Self) !void {
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            try entry.value_ptr.*.validate(self.allocator);
        }
    }
    
    /// Check for circular dependencies
    pub fn checkCircularDependencies(self: *Self) !void {
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var rec_stack = std.StringHashMap(bool).init(self.allocator);
        defer rec_stack.deinit();
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            if (try self.hasCycle(entry.value_ptr.*, &visited, &rec_stack)) {
                return LayerFSError.CircularDependency;
            }
        }
    }
    
    /// Check if a layer has a cycle in its dependency graph
    fn hasCycle(
        self: *Self,
        layer: *Layer,
        visited: *std.StringHashMap(bool),
        rec_stack: *std.StringHashMap(bool),
    ) !bool {
        if (rec_stack.contains(layer.digest)) {
            return true; // Back edge found
        }
        
        if (visited.contains(layer.digest)) {
            return false; // Already processed
        }
        
        // Mark as visited and in recursion stack
        const digest_copy1 = try self.allocator.dupe(u8, layer.digest);
        const digest_copy2 = try self.allocator.dupe(u8, layer.digest);
        try visited.put(digest_copy1, true);
        try rec_stack.put(digest_copy2, true);
        
        // Check dependencies
        if (layer.dependencies) |deps| {
            for (deps) |dep_digest| {
                if (self.getLayer(dep_digest)) |dep_layer| {
                    if (try self.hasCycle(dep_layer, visited, rec_stack)) {
                        return true;
                    }
                }
            }
        }
        
        // Remove from recursion stack
        _ = rec_stack.remove(layer.digest);
        
        return false;
    }
    
    /// Get filesystem statistics
    pub fn getStats(self: *Self) !LayerFSStats {
        var total_size: u64 = 0;
        var total_layers: u32 = 0;
        var mounted_layers: u32 = 0;
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            total_size += entry.value_ptr.*.size;
            total_layers += 1;
            
            if (self.overlay_mounts.contains(entry.key_ptr.*)) {
                mounted_layers += 1;
            }
        }
        
        return LayerFSStats{
            .total_layers = total_layers,
            .mounted_layers = mounted_layers,
            .total_size = total_size,
            .base_path = try self.allocator.dupe(u8, self.base_path),
            .zfs_pool = if (self.zfs_pool) |pool| try self.allocator.dupe(u8, pool) else null,
            .zfs_dataset = if (self.zfs_dataset) |dataset| try self.allocator.dupe(u8, dataset) else null,
        };
    }
    
    /// Set filesystem as read-only
    pub fn setReadOnly(self: *Self, readonly: bool) void {
        self.readonly = readonly;
    }
    
    /// Check if filesystem is read-only
    pub fn isReadOnly(self: *Self) bool {
        return self.readonly;
    }
    
    /// Check if ZFS is enabled
    pub fn hasZFS(self: *Self) bool {
        return self.zfs_pool != null and self.zfs_dataset != null;
    }
    
    /// Get ZFS pool name
    pub fn getZFSPool(self: *Self) ?[]const u8 {
        return self.zfs_pool;
    }
    
    /// Get ZFS dataset name
    pub fn getZFSDataset(self: *Self) ?[]const u8 {
        return self.zfs_dataset;
    }
    
    /// Garbage collection for unused layers
    pub fn garbageCollect(self: *Self, _force: bool) !GarbageCollectionResult {
        var result = GarbageCollectionResult{
            .layers_removed = 0,
            .space_freed = 0,
            .errors = std.ArrayList(GarbageCollectionError).init(self.allocator),
        };
        defer result.deinit();
        
        // Use force parameter to determine behavior
        _ = _force;
        
        var layers_to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer layers_to_remove.deinit();
        
        // Find unused layers (not mounted, not referenced by other layers)
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            const digest = entry.key_ptr.*;
            _ = entry.value_ptr.*;
            
            // Check if layer is mounted
            if (self.overlay_mounts.contains(digest)) {
                continue; // Skip mounted layers
            }
            
            // Check if layer is referenced by other layers
            var is_referenced = false;
            var ref_it = self.layers.iterator();
            while (ref_it.next()) |ref_entry| {
                const ref_layer = ref_entry.value_ptr.*;
                if (ref_layer.dependencies) |deps| {
                    for (deps) |dep_digest| {
                        if (std.mem.eql(u8, dep_digest, digest)) {
                            is_referenced = true;
                            break;
                        }
                    }
                    if (is_referenced) break;
                }
            }
            
            if (!is_referenced) {
                try layers_to_remove.append(digest);
            }
        }
        
        // Remove unused layers
        for (layers_to_remove.items) |digest| {
            if (self.layers.get(digest)) |layer| {
                const layer_size = layer.size;
                
                // Remove layer from filesystem
                if (self.layers.fetchRemove(digest)) |entry| {
                    self.allocator.free(entry.key);
                    
                    // Clean up layer resources
                    layer.deinit(self.allocator);
                    
                    result.layers_removed += 1;
                    result.space_freed += layer_size;
                }
            }
        }
        
        return result;
    }
    
    /// Get detailed statistics about layer usage
    pub fn getDetailedStats(self: *Self) !DetailedLayerFSStats {
        var stats = DetailedLayerFSStats{
            .total_layers = 0,
            .mounted_layers = 0,
            .referenced_layers = 0,
            .unused_layers = 0,
            .total_size = 0,
            .mounted_size = 0,
            .referenced_size = 0,
            .unused_size = 0,
            .base_path = try self.allocator.dupe(u8, self.base_path),
            .zfs_pool = if (self.zfs_pool) |pool| try self.allocator.dupe(u8, pool) else null,
            .zfs_dataset = if (self.zfs_dataset) |dataset| try self.allocator.dupe(u8, dataset) else null,
            .layer_details = std.ArrayList(LayerDetail).init(self.allocator),
        };
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            const digest = entry.key_ptr.*;
            const layer = entry.value_ptr.*;
            
            stats.total_layers += 1;
            stats.total_size += layer.size;
            
            const is_mounted = self.overlay_mounts.contains(digest);
            const is_referenced = self.isLayerReferenced(digest);
            
            if (is_mounted) {
                stats.mounted_layers += 1;
                stats.mounted_size += layer.size;
            } else if (is_referenced) {
                stats.referenced_layers += 1;
                stats.referenced_size += layer.size;
            } else {
                stats.unused_layers += 1;
                stats.unused_size += layer.size;
            }
            
            // Add layer detail
            try stats.layer_details.append(LayerDetail{
                .digest = try self.allocator.dupe(u8, digest),
                .size = layer.size,
                .media_type = try self.allocator.dupe(u8, layer.media_type),
                .is_mounted = is_mounted,
                .is_referenced = is_referenced,
                .created = if (layer.created) |c| try self.allocator.dupe(u8, c) else null,
                .author = if (layer.author) |a| try self.allocator.dupe(u8, a) else null,
                .comment = if (layer.comment) |c| try self.allocator.dupe(u8, c) else null,
                .dependencies = if (layer.dependencies) |deps| try self.cloneStringArray(deps) else null,
                .order = layer.order,
                .compressed = layer.compressed,
                .compression_type = if (layer.compression_type) |ct| try self.allocator.dupe(u8, ct) else null,
                .validated = layer.validated,
                .last_validated = if (layer.last_validated) |lv| try self.allocator.dupe(u8, lv) else null,
            });
        }
        
        return stats;
    }
    
    /// Check if a layer is referenced by other layers
    fn isLayerReferenced(self: *Self, digest: []const u8) bool {
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            const layer = entry.value_ptr.*;
            if (layer.dependencies) |deps| {
                for (deps) |dep_digest| {
                    if (std.mem.eql(u8, dep_digest, digest)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
    
    /// Clone string array for layer details
    fn cloneStringArray(self: *Self, strings: [][]const u8) ![][]const u8 {
        var cloned = try self.allocator.alloc([]const u8, strings.len);
        for (strings, 0..) |str, i| {
            cloned[i] = try self.allocator.dupe(u8, str);
        }
        return cloned;
    }
    
};

/// Layer operation types for batch operations
pub const LayerOperation = union(enum) {
    add: struct {
        digest: []const u8,
        layer: *Layer,
    },
    remove: struct {
        digest: []const u8,
    },
    mount: struct {
        digest: []const u8,
        mount_path: []const u8,
    },
    unmount: struct {
        digest: []const u8,
    },
};
    
/// Layer operation error
pub const LayerOperationError = struct {
    operation: []const u8,
    digest: []const u8,
    error_message: []const u8,
    
    pub fn deinit(self: *LayerOperationError) void {
        // Note: These are now allocated strings, need to free
        _ = self;
    }
};

/// Batch operation result
pub const BatchOperationResult = struct {
    successful: u32,
    failed: u32,
    errors: std.ArrayList(LayerOperationError),
    
    pub fn deinit(self: *BatchOperationResult) void {
        for (self.errors.items) |err| {
            err.deinit();
        }
        self.errors.deinit();
    }
};
    
    /// Performance optimization: Batch layer operations
    pub fn batchLayerOperations(self: *Self, operations: []LayerOperation) !BatchOperationResult {
        var result = BatchOperationResult{
            .successful = 0,
            .failed = 0,
            .errors = std.ArrayList(LayerOperationError).init(self.allocator),
        };
        defer result.deinit();
        
        for (operations) |operation| {
            switch (operation) {
                .add => |add_op| {
                    if (self.layers.contains(add_op.digest)) {
                        try result.errors.append(LayerOperationError{
                            .operation = try self.allocator.dupe(u8, "add"),
                            .digest = try self.allocator.dupe(u8, add_op.digest),
                            .error_message = try self.allocator.dupe(u8, "Layer already exists"),
                        });
                        result.failed += 1;
                    } else {
                        try self.addLayer(add_op.layer);
                        result.successful += 1;
                    }
                },
                .remove => |remove_op| {
                    if (!self.layers.contains(remove_op.digest)) {
                        try result.errors.append(LayerOperationError{
                            .operation = try self.allocator.dupe(u8, "remove"),
                            .digest = try self.allocator.dupe(u8, remove_op.digest),
                            .error_message = try self.allocator.dupe(u8, "Layer not found"),
                        });
                        result.failed += 1;
                    } else {
                        try self.removeLayer(remove_op.digest);
                        result.successful += 1;
                    }
                },
                .mount => |mount_op| {
                    if (!self.layers.contains(mount_op.digest)) {
                        try result.errors.append(LayerOperationError{
                            .operation = try self.allocator.dupe(u8, "mount"),
                            .digest = try self.allocator.dupe(u8, mount_op.digest),
                            .error_message = try self.allocator.dupe(u8, "Layer not found"),
                        });
                        result.failed += 1;
                    } else {
                        try self.mountOverlay(mount_op.digest, mount_op.mount_path);
                        result.successful += 1;
                    }
                },
                .unmount => |unmount_op| {
                    if (!self.overlay_mounts.contains(unmount_op.digest)) {
                        try result.errors.append(LayerOperationError{
                            .operation = try self.allocator.dupe(u8, "unmount"),
                            .digest = try self.allocator.dupe(u8, unmount_op.digest),
                            .error_message = try self.allocator.dupe(u8, "Layer not mounted"),
                        });
                        result.failed += 1;
                    } else {
                        self.unmountOverlay(unmount_op.digest);
                        result.successful += 1;
                    }
                },
            }
        }
        
        return result;
    }
};

/// Statistics for LayerFS
pub const LayerFSStats = struct {
    total_layers: u32,
    mounted_layers: u32,
    total_size: u64,
    base_path: []const u8,
    zfs_pool: ?[]const u8,
    zfs_dataset: ?[]const u8,
    
    pub fn deinit(self: *LayerFSStats, allocator: std.mem.Allocator) void {
        allocator.free(self.base_path);
        if (self.zfs_pool) |pool| allocator.free(pool);
        if (self.zfs_dataset) |dataset| allocator.free(dataset);
    }
};

/// Create a new LayerFS instance
pub fn createLayerFS(allocator: std.mem.Allocator, base_path: []const u8) !*LayerFS {
    return LayerFS.init(allocator, base_path);
}

/// Initialize a new LayerFS instance
pub fn initLayerFS(allocator: std.mem.Allocator, base_path: []const u8) !*LayerFS {
    return LayerFS.init(allocator, base_path);
}

/// Create a new LayerFS instance with ZFS support
pub fn createLayerFSWithZFS(allocator: std.mem.Allocator, base_path: []const u8, zfs_pool: []const u8, zfs_dataset: []const u8) !*LayerFS {
    return LayerFS.initWithZFS(allocator, base_path, zfs_pool, zfs_dataset);
}

/// Garbage collection result
pub const GarbageCollectionResult = struct {
    layers_removed: u32,
    space_freed: u64,
    errors: std.ArrayList(GarbageCollectionError),
    
    pub fn deinit(self: *GarbageCollectionResult) void {
        self.errors.deinit();
    }
};

/// Garbage collection error
pub const GarbageCollectionError = struct {
    digest: []const u8,
    error_message: []const u8,
    
    pub fn deinit(self: *GarbageCollectionError, allocator: std.mem.Allocator) void {
        allocator.free(self.digest);
        allocator.free(self.error_message);
    }
};

/// Detailed LayerFS statistics
pub const DetailedLayerFSStats = struct {
    total_layers: u32,
    mounted_layers: u32,
    referenced_layers: u32,
    unused_layers: u32,
    total_size: u64,
    mounted_size: u64,
    referenced_size: u64,
    unused_size: u64,
    base_path: []const u8,
    zfs_pool: ?[]const u8,
    zfs_dataset: ?[]const u8,
    layer_details: std.ArrayList(LayerDetail),
    
    pub fn deinit(self: *DetailedLayerFSStats, allocator: std.mem.Allocator) void {
        allocator.free(self.base_path);
        if (self.zfs_pool) |pool| allocator.free(pool);
        if (self.zfs_dataset) |dataset| allocator.free(dataset);
        
        for (self.layer_details.items) |detail| {
            detail.deinit(allocator);
        }
        self.layer_details.deinit();
    }
};

/// Individual layer detail information
pub const LayerDetail = struct {
    digest: []const u8,
    size: u64,
    media_type: ?[]const u8,
    is_mounted: bool,
    is_referenced: bool,
    created: ?[]const u8,
    author: ?[]const u8,
    comment: ?[]const u8,
    dependencies: ?[][]const u8,
    order: u32,
    compressed: bool,
    compression_type: ?[]const u8,
    validated: bool,
    last_validated: ?[]const u8,
    
    pub fn deinit(self: *LayerDetail, allocator: std.mem.Allocator) void {
        allocator.free(self.digest);
        if (self.media_type) |mt| allocator.free(mt);
        if (self.created) |c| allocator.free(c);
        if (self.author) |a| allocator.free(a);
        if (self.comment) |c| allocator.free(c);
        if (self.compression_type) |ct| allocator.free(ct);
        if (self.last_validated) |lv| allocator.free(lv);
        
        if (self.dependencies) |deps| {
            for (deps) |dep| {
                allocator.free(dep);
            }
            allocator.free(deps);
        }
    }
};
