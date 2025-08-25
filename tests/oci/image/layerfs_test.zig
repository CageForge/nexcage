const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;
const LayerFS = @import("image").LayerFS;
const Layer = @import("image").Layer;
const LayerFSError = @import("image").LayerFSError;

fn createTestDigest() []const u8 {
    return "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
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
