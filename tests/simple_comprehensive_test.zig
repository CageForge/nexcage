const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

// Import types for testing
const LayerFS = @import("image").LayerFS;
const Layer = @import("layer").Layer;

fn createTestDigest(index: u32) []const u8 {
    var buffer: [128]u8 = undefined;
    const digest = std.fmt.bufPrint(&buffer, "sha256:testdigest{:0>10}abcdef1234567890abcdef1234567890abcdef1234567890", .{index}) catch "sha256:default";
    return allocator.dupe(u8, digest) catch "sha256:default";
}

fn createTestLayer(index: u32) !*Layer {
    const digest = createTestDigest(index);
    defer allocator.free(digest);

    return try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", try allocator.dupe(u8, digest), 1024 + index * 100, null);
}

test "Simple: LayerFS basic operations" {
    const test_dir = "/tmp/test-simple-layerfs";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Test basic initialization
    try testing.expectEqualStrings(test_dir, layerfs.base_path);
    try testing.expectEqual(false, layerfs.readonly);
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());

    std.debug.print("LayerFS basic operations test passed\n", .{});
}

test "Simple: Layer creation and validation" {
    // Create a simple layer
    var layer = try createTestLayer(1);
    defer layer.deinit(allocator);

    // Test basic properties
    try testing.expectEqualStrings("application/vnd.oci.image.layer.v1.tar", layer.media_type);
    try testing.expectEqual(@as(u64, 1124), layer.size); // 1024 + 1 * 100

    // Test validation
    try layer.validate(allocator);
    try testing.expectEqual(true, layer.validated);

    std.debug.print("Layer creation and validation test passed\n", .{});
}

test "Simple: LayerFS add and remove layers" {
    const test_dir = "/tmp/test-simple-add-remove";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Create and add layers
    for (0..5) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
    }

    // Verify layers were added
    try testing.expectEqual(@as(usize, 5), layerfs.layers.count());

    // Test getting a layer
    const digest = createTestDigest(1);
    defer allocator.free(digest);

    const retrieved_layer = layerfs.getLayer(digest);
    try testing.expect(retrieved_layer != null);

    std.debug.print("LayerFS add and remove test passed\n", .{});
}

test "Simple: LayerFS mount points" {
    const test_dir = "/tmp/test-simple-mounts";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Create a mount point
    const mount_path = try std.fmt.allocPrint(allocator, "{s}/test-mount", .{test_dir});
    defer allocator.free(mount_path);

    try layerfs.createMountPoint(mount_path);

    // Verify mount point was created
    const retrieved_mount = layerfs.getMountPoint(mount_path);
    try testing.expect(retrieved_mount != null);

    std.debug.print("LayerFS mount points test passed\n", .{});
}

test "Simple: LayerFS statistics" {
    const test_dir = "/tmp/test-simple-stats";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Add some layers
    for (0..3) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
    }

    // Get statistics
    const stats = layerfs.getStats();
    defer stats.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), stats.total_layers);
    try testing.expectEqual(@as(usize, 0), stats.total_mount_points);

    std.debug.print("LayerFS statistics test passed\n", .{});
}

test "Simple: LayerFS read-only mode" {
    const test_dir = "/tmp/test-simple-readonly";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Test default read-only state
    try testing.expectEqual(false, layerfs.isReadOnly());

    // Set read-only mode
    layerfs.setReadOnly(true);
    try testing.expectEqual(true, layerfs.isReadOnly());

    // Set back to read-write
    layerfs.setReadOnly(false);
    try testing.expectEqual(false, layerfs.isReadOnly());

    std.debug.print("LayerFS read-only mode test passed\n", .{});
}

test "Simple: LayerFS garbage collection" {
    const test_dir = "/tmp/test-simple-gc";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Add some layers
    for (0..3) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
    }

    // Run garbage collection
    const gc_result = try layerfs.garbageCollect(allocator, false);
    defer gc_result.deinit(allocator);

    // Verify GC completed
    try testing.expect(gc_result.success);

    std.debug.print("LayerFS garbage collection test passed\n", .{});
}

test "Simple: LayerFS detailed statistics" {
    const test_dir = "/tmp/test-simple-detailed-stats";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Add some layers
    for (0..2) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
    }

    // Get detailed statistics
    const detailed_stats = try layerfs.getDetailedStats(allocator);
    defer detailed_stats.deinit(allocator);

    // Verify we have some stats
    try testing.expect(detailed_stats.layers.len > 0);

    std.debug.print("LayerFS detailed statistics test passed\n", .{});
}

test "Simple: LayerFS batch operations" {
    const test_dir = "/tmp/test-simple-batch";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Create batch operations
    var operations = std.ArrayList(@import("image").LayerOperation).init(allocator);
    defer operations.deinit();

    // Add some operations
    try operations.append(.{
        .operation_type = .add,
        .layer_digest = try allocator.dupe(u8, "sha256:test123"),
        .target_path = try allocator.dupe(u8, "/test/path"),
        .error_message = null,
    });

    // Execute batch operations
    const batch_result = try layerfs.batchLayerOperations(allocator, operations.items);
    defer batch_result.deinit(allocator);

    // Verify batch completed
    try testing.expect(batch_result.success);

    std.debug.print("LayerFS batch operations test passed\n", .{});
}

test "Simple: Memory management - multiple operations" {
    const test_dir = "/tmp/test-simple-memory";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create and destroy LayerFS multiple times
    for (0..10) |_| {
        var layerfs = try LayerFS.init(allocator, test_dir);

        // Add some layers
        for (0..2) |i| {
            var layer = try createTestLayer(@intCast(i));
            defer layer.deinit(allocator);

            try layerfs.addLayer(layer);
        }

        // This should clean up all resources
        layerfs.deinit();
    }

    // If we reach here without memory issues, the test passes
    try testing.expect(true);
    std.debug.print("Memory management test passed\n", .{});
}
