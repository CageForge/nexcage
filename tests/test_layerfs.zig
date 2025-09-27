const std = @import("std");
const testing = std.testing;

// Import our modules
const image = @import("src/oci/image/mod.zig");
const LayerFS = image.LayerFS;
const Layer = image.Layer;
const LayerFSError = image.LayerFSError;

test "LayerFS basic functionality" {
    const allocator = testing.allocator;

    // Test initialization
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();

    try testing.expectEqualStrings("/tmp/test-layers", layerfs.base_path);
    try testing.expectEqual(false, layerfs.readonly);
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());

    // Test adding a layer
    const layer = try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", "sha256:1234567890abcdef", 1024, null);
    defer layer.deinit(allocator);

    try layerfs.addLayer(layer);
    try testing.expectEqual(@as(usize, 1), layerfs.layers.count());

    // Test getting the layer
    const retrieved_layer = layerfs.getLayer("sha256:1234567890abcdef");
    try testing.expect(retrieved_layer != null);
    try testing.expectEqual(layer, retrieved_layer.?);

    // Test creating mount point
    try layerfs.createMountPoint("sha256:1234567890abcdef", "/mnt/test");
    const mount_path = layerfs.getMountPoint("sha256:1234567890abcdef");
    try testing.expect(mount_path != null);
    try testing.expectEqualStrings("/mnt/test", mount_path.?);

    // Test mounting overlay
    try layerfs.mountOverlay("sha256:1234567890abcdef", "/mnt/overlay");
    try testing.expect(layerfs.overlay_mounts.contains("sha256:1234567890abcdef"));

    // Test getting stats
    const stats = try layerfs.getStats();
    defer stats.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), stats.total_layers);
    try testing.expectEqual(@as(u32, 1), stats.mounted_layers);
    try testing.expectEqual(@as(u64, 1024), stats.total_size);

    std.debug.print("✅ LayerFS basic functionality test passed!\n", .{});
}

test "LayerFS dependency ordering" {
    const allocator = testing.allocator;

    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();

    // Create base layer
    const base_layer = try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", "sha256:base1234567890", 1024, null);
    defer base_layer.deinit(allocator);

    // Create app layer with dependency
    const app_layer = try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", "sha256:app1234567890", 2048, null);
    defer app_layer.deinit(allocator);

    // Set dependency
    try app_layer.addDependency(allocator, "sha256:base1234567890");

    // Add layers to filesystem
    try layerfs.addLayer(base_layer);
    try layerfs.addLayer(app_layer);

    // Get layers in order
    const ordered_layers = try layerfs.getLayersInOrder();
    defer allocator.free(ordered_layers);

    try testing.expectEqual(@as(usize, 2), ordered_layers.len);
    try testing.expectEqualStrings("sha256:base1234567890", ordered_layers[0].digest);
    try testing.expectEqualStrings("sha256:app1234567890", ordered_layers[1].digest);

    std.debug.print("✅ LayerFS dependency ordering test passed!\n", .{});
}

test "LayerFS error handling" {
    const allocator = testing.allocator;

    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();

    // Test getting non-existent layer
    const non_existent = layerfs.getLayer("sha256:nonexistent");
    try testing.expect(non_existent == null);

    // Test creating mount point for non-existent layer
    try testing.expectError(image.LayerFSError.LayerNotFound, layerfs.createMountPoint("sha256:nonexistent", "/mnt/test"));

    // Test mounting overlay for non-existent layer
    try testing.expectError(image.LayerFSError.LayerNotFound, layerfs.mountOverlay("sha256:nonexistent", "/mnt/overlay"));

    std.debug.print("✅ LayerFS error handling test passed!\n", .{});
}
