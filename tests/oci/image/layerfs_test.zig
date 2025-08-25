const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;
const LayerFS = @import("../../src/oci/image/layerfs.zig").LayerFS;
const Layer = @import("../../src/oci/image/layer.zig").Layer;
const LayerFSError = @import("../../src/oci/image/layerfs.zig").LayerFSError;
const LayerOperation = @import("../../src/oci/image/layerfs.zig").LayerOperation;
const GarbageCollectionResult = @import("../../src/oci/image/layerfs.zig").GarbageCollectionResult;
const DetailedLayerFSStats = @import("../../src/oci/image/layerfs.zig").DetailedLayerFSStats;
const BatchOperationResult = @import("../../src/oci/image/layerfs.zig").BatchOperationResult;
const MetadataCache = @import("../../src/oci/image/layerfs.zig").MetadataCache;
const MetadataCacheEntry = @import("../../src/oci/image/layerfs.zig").MetadataCacheEntry;
const LayerObjectPool = @import("../../src/oci/image/layerfs.zig").LayerObjectPool;
const ParallelProcessingContext = @import("../../src/oci/image/layerfs.zig").ParallelProcessingContext;
const AdvancedFileOps = @import("../../src/oci/image/layerfs.zig").AdvancedFileOps;

fn createTestDigest() []const u8 {
    return "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
}

test "LayerFS initialization" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    try testing.expectEqualStrings("/tmp/test-layers", layerfs.base_path);
    try testing.expectEqual(false, layerfs.readonly);
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());
    try testing.expectEqual(@as(usize, 0), layerfs.mount_points.count());
    try testing.expectEqual(@as(usize, 0), layerfs.overlay_mounts.count());
}

test "LayerFS with ZFS initialization" {
    const layerfs = try LayerFS.initWithZFS(allocator, "/tmp/test-layers", "tank", "containers");
    defer layerfs.deinit();
    
    try testing.expectEqualStrings("/tmp/test-layers", layerfs.base_path);
    try testing.expectEqual(false, layerfs.readonly);
    try testing.expectEqualStrings("tank", layerfs.zfs_pool.?);
    try testing.expectEqualStrings("containers", layerfs.zfs_dataset.?);
    try testing.expectEqual(true, layerfs.hasZFS());
    try testing.expectEqualStrings("tank", layerfs.getZFSPool().?);
    try testing.expectEqualStrings("containers", layerfs.getZFSDataset().?);
}

test "LayerFS without ZFS" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    try testing.expectEqual(false, layerfs.hasZFS());
    try testing.expectEqual(null, layerfs.getZFSPool());
    try testing.expectEqual(null, layerfs.getZFSDataset());
}

test "LayerFS add and get layer" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    
    const retrieved_layer = layerfs.getLayer(createTestDigest());
    try testing.expect(retrieved_layer != null);
    try testing.expectEqual(layer, retrieved_layer.?);
}

test "LayerFS remove layer" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    try testing.expectEqual(@as(usize, 1), layerfs.layers.count());
    
    try layerfs.removeLayer(createTestDigest());
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());
}

test "LayerFS create and get mount point" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    try layerfs.createMountPoint(createTestDigest(), "/tmp/test-mount");
    
    const mount_point = layerfs.getMountPoint(createTestDigest());
    try testing.expect(mount_point != null);
    try testing.expectEqualStrings("/tmp/test-mount", mount_point.?);
}

test "LayerFS mount and unmount overlay" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    try layerfs.mountOverlay(createTestDigest(), "/tmp/overlay");
    
    try testing.expectEqual(@as(usize, 1), layerfs.overlay_mounts.count());
    
    layerfs.unmountOverlay(createTestDigest());
    try testing.expectEqual(@as(usize, 0), layerfs.overlay_mounts.count());
}

test "LayerFS get layers in order" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create multiple layers
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    try layerfs.addLayer(layer1);
    try layerfs.addLayer(layer2);
    
    const ordered_layers = try layerfs.getLayersInOrder();
    defer allocator.free(ordered_layers);
    
    try testing.expectEqual(@as(usize, 2), ordered_layers.len);
}

test "LayerFS validate all layers" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    try layerfs.validateAllLayers();
}

test "LayerFS check circular dependencies" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    try layerfs.checkCircularDependencies();
}

test "LayerFS set and check read-only mode" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Set read-only
    layerfs.setReadOnly(true);
    try testing.expectEqual(true, layerfs.isReadOnly());
    
    // Set read-write
    layerfs.setReadOnly(false);
    try testing.expectEqual(false, layerfs.isReadOnly());
}

test "LayerFS error cases" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Try to get non-existent layer
    const non_existent = layerfs.getLayer("sha256:nonexistent");
    try testing.expect(non_existent == null);
    
    // Try to create mount point for non-existent layer
    try testing.expectError(LayerFSError.LayerNotFound, 
        layerfs.createMountPoint("sha256:nonexistent", "/tmp/test"));
    
    // Try to mount overlay for non-existent layer
    try testing.expectError(LayerFSError.LayerNotFound, 
        layerfs.mountOverlay("sha256:nonexistent", "/tmp/overlay"));
    
    // Try to remove non-existent layer
    try layerfs.removeLayer("sha256:nonexistent"); // Should not error
}

test "LayerFS duplicate operations" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create a test layer
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    
    // Try to add the same layer again
    try testing.expectError(LayerFSError.LayerNotFound, layerfs.addLayer(layer));
    
    // Create mount point
    try layerfs.createMountPoint(createTestDigest(), "/tmp/test");
    
    // Try to create mount point again
    try testing.expectError(LayerFSError.InvalidMountPoint, 
        layerfs.createMountPoint(createTestDigest(), "/tmp/test2"));
    
    // Mount overlay
    try layerfs.mountOverlay(createTestDigest(), "/tmp/overlay");
    
    // Try to mount overlay again
    try testing.expectError(LayerFSError.InvalidOverlay, 
        layerfs.mountOverlay(createTestDigest(), "/tmp/overlay2"));
}

test "LayerFS layer stacking" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create multiple layers
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    try layerfs.addLayer(layer1);
    try layerfs.addLayer(layer2);
    
    var layer_digests = [_][]const u8{
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    };
    
    try layerfs.stackLayers(&layer_digests, "/tmp/stacked");
    
    // Verify that layers were mounted
    try testing.expectEqual(@as(usize, 2), layerfs.overlay_mounts.count());
}

test "LayerFS layer merging" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create multiple layers
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    try layerfs.addLayer(layer1);
    try layerfs.addLayer(layer2);
    
    var layer_digests = [_][]const u8{
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
    };
    
    const target_digest = "sha256:mergedabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
    try layerfs.mergeLayers(&layer_digests, target_digest);
    
    // Verify that merged layer was created
    const merged_layer = layerfs.getLayer(target_digest);
    try testing.expect(merged_layer != null);
    try testing.expectEqualStrings("Merged layer from multiple source layers", merged_layer.?.comment.?);
}

test "LayerFS get stats with ZFS" {
    const layerfs = try LayerFS.initWithZFS(allocator, "/tmp/test-layers", "tank", "containers");
    defer layerfs.deinit();
    
    const layer = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        createTestDigest(),
        1024,
        null
    );
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    
    var stats = try layerfs.getStats();
    defer stats.deinit(allocator);
    
    try testing.expectEqual(@as(u32, 1), stats.total_layers);
    try testing.expectEqual(@as(u32, 0), stats.mounted_layers);
    try testing.expectEqual(@as(u64, 1024), stats.total_size);
    try testing.expectEqualStrings("/tmp/test-layers", stats.base_path);
    try testing.expectEqualStrings("tank", stats.zfs_pool.?);
    try testing.expectEqualStrings("containers", stats.zfs_dataset.?);
}

test "LayerFS memory management" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    
    // Add multiple layers
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        var digest: [128]u8 = undefined;
        _ = std.fmt.bufPrint(&digest, "sha256:layer{}abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .{i}) catch unreachable;
        
        const layer = try Layer.createLayer(
            allocator,
            "application/vnd.oci.image.layer.v1.tar",
            &digest,
            @as(u64, i) * 1024,
            null
        );
        defer layer.deinit(allocator);
        
        try layerfs.addLayer(layer);
        
        // Create mount points and overlays
        var mount_path: [32]u8 = undefined;
        _ = std.fmt.bufPrint(&mount_path, "/tmp/layer{}", .{i}) catch unreachable;
        
        try layerfs.createMountPoint(&digest, &mount_path);
        try layerfs.mountOverlay(&digest, &mount_path);
    }
    
    // Verify all layers were added
    try testing.expectEqual(@as(usize, 10), layerfs.layers.count());
    try testing.expectEqual(@as(usize, 10), layerfs.mount_points.count());
    try testing.expectEqual(@as(usize, 10), layerfs.overlay_mounts.count());
    
    // Cleanup should not leak memory
    layerfs.deinit();
}

test "LayerFS garbage collection" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create multiple layers
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    const layer3 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer3abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        4096,
        null
    );
    defer layer3.deinit(allocator);
    
    // Add layers to filesystem
    try layerfs.addLayer(layer1);
    try layerfs.addLayer(layer2);
    try layerfs.addLayer(layer3);
    
    // Mount layer1 (will be protected from GC)
    try layerfs.mountOverlay("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", "/tmp/mounted");
    
    // Set layer2 as dependency of layer3 (will be protected from GC)
    try layer3.addDependency(allocator, "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890");
    
    // Verify initial state
    try testing.expectEqual(@as(usize, 3), layerfs.layers.count());
    
    // Run garbage collection
    const gc_result = try layerfs.garbageCollect(false);
    defer gc_result.deinit();
    
    // Only layer3 should be removed (unused, not mounted, not referenced)
    try testing.expectEqual(@as(u32, 1), gc_result.layers_removed);
    try testing.expectEqual(@as(u64, 4096), gc_result.space_freed);
    
    // Verify final state
    try testing.expectEqual(@as(usize, 2), layerfs.layers.count());
    
    // layer1 should still exist (mounted)
    try testing.expect(layerfs.getLayer("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") != null);
    
    // layer2 should still exist (referenced by layer3)
    try testing.expect(layerfs.getLayer("sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") != null);
    
    // layer3 should be removed
    try testing.expect(layerfs.getLayer("sha256:layer3abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") == null);
}

test "LayerFS detailed statistics" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create layers with different states
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    const layer3 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer3abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        4096,
        null
    );
    defer layer3.deinit(allocator);
    
    // Add all layers
    try layerfs.addLayer(layer1);
    try layerfs.addLayer(layer2);
    try layerfs.addLayer(layer3);
    
    // Mount layer1
    try layerfs.mountOverlay("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", "/tmp/mounted");
    
    // Set layer2 as dependency of layer3
    try layer3.addDependency(allocator, "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890");
    
    // Get detailed statistics
    const stats = try layerfs.getDetailedStats();
    defer stats.deinit(allocator);
    
    // Verify statistics
    try testing.expectEqual(@as(u32, 3), stats.total_layers);
    try testing.expectEqual(@as(u32, 1), stats.mounted_layers);
    try testing.expectEqual(@as(u32, 1), stats.referenced_layers);
    try testing.expectEqual(@as(u32, 1), stats.unused_layers);
    
    try testing.expectEqual(@as(u64, 7168), stats.total_size); // 1024 + 2048 + 4096
    try testing.expectEqual(@as(u64, 1024), stats.mounted_size);
    try testing.expectEqual(@as(u64, 2048), stats.referenced_size);
    try testing.expectEqual(@as(u64, 4096), stats.unused_size);
    
    // Verify layer details
    try testing.expectEqual(@as(usize, 3), stats.layer_details.items.len);
    
    // Find layer1 (mounted)
    var found_mounted = false;
    for (stats.layer_details.items) |detail| {
        if (std.mem.eql(u8, detail.digest, "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")) {
            try testing.expectEqual(true, detail.is_mounted);
            try testing.expectEqual(false, detail.is_referenced);
            try testing.expectEqual(@as(u64, 1024), detail.size);
            found_mounted = true;
        }
    }
    try testing.expect(found_mounted);
    
    // Find layer2 (referenced)
    var found_referenced = false;
    for (stats.layer_details.items) |detail| {
        if (std.mem.eql(u8, detail.digest, "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")) {
            try testing.expectEqual(false, detail.is_mounted);
            try testing.expectEqual(true, detail.is_referenced);
            try testing.expectEqual(@as(u64, 2048), detail.size);
            found_referenced = true;
        }
    }
    try testing.expect(found_referenced);
    
    // Find layer3 (unused)
    var found_unused = false;
    for (stats.layer_details.items) |detail| {
        if (std.mem.eql(u8, detail.digest, "sha256:layer3abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890")) {
            try testing.expectEqual(false, detail.is_mounted);
            try testing.expectEqual(false, detail.is_referenced);
            try testing.expectEqual(@as(u64, 4096), detail.size);
            found_unused = true;
        }
    }
    try testing.expect(found_unused);
}

test "LayerFS batch operations" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create test layers
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    const layer2 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null
    );
    defer layer2.deinit(allocator);
    
    // Create batch operations
    const operations = [_]LayerOperation{
        .{ .add = .{ .digest = "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .layer = layer1 } },
        .{ .add = .{ .digest = "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .layer = layer2 } },
        .{ .mount = .{ .digest = "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .mount_path = "/tmp/mounted" } },
        .{ .remove = .{ .digest = "sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890" } },
    };
    
    // Execute batch operations
    const result = try layerfs.batchLayerOperations(&operations);
    defer result.deinit();
    
    // Verify results
    try testing.expectEqual(@as(u32, 4), result.successful);
    try testing.expectEqual(@as(u32, 0), result.failed);
    try testing.expectEqual(@as(usize, 0), result.errors.items.len);
    
    // Verify final state
    try testing.expectEqual(@as(usize, 1), layerfs.layers.count());
    try testing.expectEqual(@as(usize, 1), layerfs.overlay_mounts.count());
    
    // layer1 should exist and be mounted
    try testing.expect(layerfs.getLayer("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") != null);
    try testing.expect(layerfs.overlay_mounts.contains("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"));
    
    // layer2 should be removed
    try testing.expect(layerfs.getLayer("sha256:layer2abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") == null);
}

test "LayerFS batch operations with errors" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Create test layer
    const layer1 = try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        1024,
        null
    );
    defer layer1.deinit(allocator);
    
    // Create batch operations with some errors
    const operations = [_]LayerOperation{
        .{ .add = .{ .digest = "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .layer = layer1 } },
        .{ .add = .{ .digest = "sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .layer = layer1 } }, // Duplicate
        .{ .remove = .{ .digest = "sha256:nonexistent" } }, // Non-existent
        .{ .mount = .{ .digest = "sha256:nonexistent", .mount_path = "/tmp/mounted" } }, // Non-existent
    };
    
    // Execute batch operations
    const result = try layerfs.batchLayerOperations(&operations);
    defer result.deinit();
    
    // Verify results
    try testing.expectEqual(@as(u32, 1), result.successful);
    try testing.expectEqual(@as(u32, 3), result.failed);
    try testing.expectEqual(@as(usize, 3), result.errors.items.len);
    
    // Verify final state
    try testing.expectEqual(@as(usize, 1), layerfs.layers.count());
    
    // layer1 should exist
    try testing.expect(layerfs.getLayer("sha256:layer1abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890") != null);
}

test "LayerFS performance optimization features" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    // Test with many layers for performance
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        var digest: [128]u8 = undefined;
        _ = std.fmt.bufPrint(&digest, "sha256:layer{}abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", .{i}) catch unreachable;
        
        const layer = try Layer.createLayer(
            allocator,
            "application/vnd.oci.image.layer.v1.tar",
            &digest,
            @as(u64, i) * 1024,
            null
        );
        defer layer.deinit(allocator);
        
        try layerfs.addLayer(layer);
    }
    
    // Verify all layers were added
    try testing.expectEqual(@as(usize, 100), layerfs.layers.count());
    
    // Test garbage collection performance
    const start_time = std.time.milliTimestamp();
    const gc_result = try layerfs.garbageCollect(false);
    defer gc_result.deinit();
    const end_time = std.time.milliTimestamp();
    
    // Garbage collection should complete in reasonable time (< 100ms)
    const duration = @as(i64, end_time - start_time);
    try testing.expect(duration < 100);
    
    // All layers should be removed (they're all unused)
    try testing.expectEqual(@as(u32, 100), gc_result.layers_removed);
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());
}

// Advanced LayerFS Operations Tests

test "MetadataCache initialization and basic operations" {
    var cache = MetadataCache.init(allocator, 10);
    defer cache.deinit();
    
    try testing.expectEqual(@as(usize, 0), cache.entries.count());
    try testing.expectEqual(@as(usize, 10), cache.max_entries);
}

test "MetadataCache put and get operations" {
    var cache = MetadataCache.init(allocator, 5);
    defer cache.deinit();
    
    const entry = try allocator.create(MetadataCacheEntry);
    entry.* = .{
        .digest = try allocator.dupe(u8, createTestDigest()),
        .media_type = try allocator.dupe(u8, "application/vnd.oci.image.layer.v1.tar"),
        .size = 1024,
        .created = null,
        .author = null,
        .comment = null,
        .dependencies = null,
        .order = 0,
        .compressed = false,
        .compression_type = null,
        .validated = true,
        .last_validated = null,
        .last_accessed = std.time.timestamp(),
        .access_count = 0,
    };
    defer entry.deinit(allocator);
    defer allocator.destroy(entry);
    
    try cache.put(entry.digest, entry);
    try testing.expectEqual(@as(usize, 1), cache.entries.count());
    
    const retrieved = cache.get(entry.digest);
    try testing.expect(retrieved != null);
    try testing.expectEqual(entry, retrieved.?);
    try testing.expectEqual(@as(u32, 1), retrieved.?.access_count);
}

test "LayerObjectPool initialization and operations" {
    var pool = LayerObjectPool.init(allocator, 5);
    defer pool.deinit();
    
    try testing.expectEqual(@as(u32, 0), pool.total_allocated);
    try testing.expectEqual(@as(u32, 5), pool.max_pool_size);
    
    const layer1 = try pool.getLayer();
    defer layer1.deinit(allocator);
    
    try testing.expectEqual(@as(u32, 1), pool.total_allocated);
    
    pool.returnLayer(layer1);
    try testing.expectEqual(@as(usize, 1), pool.available_layers.items.len);
}

test "ParallelProcessingContext initialization" {
    const context = ParallelProcessingContext.init(allocator, 4);
    try testing.expectEqual(@as(u32, 4), context.max_workers);
}

test "AdvancedFileOps copy operation" {
    var file_ops = AdvancedFileOps.init(allocator);
    
    // Create a test file
    const test_file = try std.fs.cwd().createFile("/tmp/test_source.txt", .{});
    defer test_file.close();
    defer std.fs.cwd().deleteFile("/tmp/test_source.txt") catch {};
    
    try test_file.writer().writeAll("Hello, World!");
    
    const result = try file_ops.copyLayerData("/tmp/test_source.txt", "/tmp/test_dest.txt");
    defer result.deinit(allocator);
    defer std.fs.cwd().deleteFile("/tmp/test_dest.txt") catch {};
    
    try testing.expectEqual(true, result.success);
    try testing.expectEqual(@as(u64, 13), result.bytes_processed);
    try testing.expectEqual(null, result.error_message);
}

test "AdvancedFileOps move operation" {
    var file_ops = AdvancedFileOps.init(allocator);
    
    // Create a test file
    const test_file = try std.fs.cwd().createFile("/tmp/test_move.txt", .{});
    defer test_file.close();
    
    try test_file.writer().writeAll("Test content");
    
    const result = try file_ops.moveLayerData("/tmp/test_move.txt", "/tmp/test_moved.txt");
    defer result.deinit(allocator);
    defer std.fs.cwd().deleteFile("/tmp/test_moved.txt") catch {};
    
    try testing.expectEqual(true, result.success);
    try testing.expectEqual(@as(u64, 0), result.bytes_processed);
    try testing.expectEqual(null, result.error_message);
}

test "AdvancedFileOps sync operation" {
    var file_ops = AdvancedFileOps.init(allocator);
    
    // Create a test file
    const test_file = try std.fs.cwd().createFile("/tmp/test_sync.txt", .{});
    defer test_file.close();
    defer std.fs.cwd().deleteFile("/tmp/test_sync.txt") catch {};
    
    try test_file.writer().writeAll("Test content");
    
    const result = try file_ops.syncLayerData("/tmp/test_sync.txt");
    defer result.deinit(allocator);
    
    try testing.expectEqual(true, result.success);
    try testing.expectEqual(@as(u64, 0), result.bytes_processed);
    try testing.expectEqual(null, result.error_message);
}
