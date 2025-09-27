const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

// Import types for testing
const LayerFS = @import("image").LayerFS;
const Layer = @import("layer").Layer;
const MetadataCache = @import("image").MetadataCache;
const LayerObjectPool = @import("image").LayerObjectPool;

fn createTestDigest(index: u32) []const u8 {
    var buffer: [128]u8 = undefined;
    const digest = std.fmt.bufPrint(&buffer, "sha256:testdigest{:0>10}abcdef1234567890abcdef1234567890abcdef1234567890", .{index}) catch "sha256:default";
    return allocator.dupe(u8, digest) catch "sha256:default";
}

fn createTestLayer(index: u32) !*Layer {
    const digest = createTestDigest(index);
    defer allocator.free(digest);

    return try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", try allocator.dupe(u8, digest), 1024 + index * 100, // Varying sizes
        null);
}

fn createTestMetadataEntry(index: u32) !*MetadataCache.MetadataCacheEntry {
    const digest = createTestDigest(index);
    defer allocator.free(digest);

    return try allocator.create(MetadataCache.MetadataCacheEntry);
}

test "Optimized: MetadataCache LRU performance" {
    const test_dir = "/tmp/test-optimized-metadata-cache";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var cache = MetadataCache.init(allocator, 1000);
    defer cache.deinit();

    const num_entries = 500;
    const start_time = std.time.milliTimestamp();

    // Add many entries to test LRU performance
    for (0..num_entries) |i| {
        const entry = try createTestMetadataEntry(@intCast(i));
        defer allocator.destroy(entry);

        try cache.put(entry.digest, entry);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 100); // Should complete in less than 100ms
    std.debug.print("Added {d} entries in {d}ms\n", .{ num_entries, duration });
}

test "Optimized: LayerFS batch operations performance" {
    const test_dir = "/tmp/test-optimized-layerfs-batch";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    const num_layers = 100;
    var layers = try allocator.alloc(*Layer, num_layers);
    defer {
        for (layers) |layer| {
            layer.deinit(allocator);
            allocator.destroy(layer);
        }
        allocator.free(layers);
    }

    // Create layers
    for (0..num_layers) |i| {
        layers[i] = try createTestLayer(@intCast(i));
    }

    const start_time = std.time.milliTimestamp();

    // Add layers in batch
    for (layers) |layer| {
        try layerfs.addLayer(layer);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 200); // Should complete in less than 200ms
    std.debug.print("Added {d} layers in {d}ms\n", .{ num_layers, duration });
}

test "Optimized: LayerObjectPool performance" {
    var pool = LayerObjectPool.init(allocator, 1000);
    defer pool.deinit();

    const num_operations = 1000;
    const start_time = std.time.milliTimestamp();

    // Test pool operations
    for (0..num_operations) |_| {
        const layer = try pool.getLayer();
        defer pool.returnLayer(layer);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 50); // Should complete in less than 50ms
    std.debug.print("Completed {d} pool operations in {d}ms\n", .{ num_operations, duration });
}

test "Optimized: Memory allocation patterns" {
    const test_dir = "/tmp/test-optimized-memory-patterns";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    const num_iterations = 100;
    const start_time = std.time.milliTimestamp();

    // Test memory allocation patterns
    for (0..num_iterations) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
        try layerfs.removeLayer(layer.digest);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 300); // Should complete in less than 300ms
    std.debug.print("Completed {d} memory pattern operations in {d}ms\n", .{ num_iterations, duration });
}

test "Optimized: Cache hit rate improvement" {
    var cache = MetadataCache.init(allocator, 100);
    defer cache.deinit();

    const num_entries = 50;
    const access_patterns = 200;

    // Add entries
    for (0..num_entries) |i| {
        const entry = try createTestMetadataEntry(@intCast(i));
        defer allocator.destroy(entry);

        try cache.put(entry.digest, entry);
    }

    const start_time = std.time.milliTimestamp();

    // Access entries in a pattern that should benefit from LRU
    for (0..access_patterns) |i| {
        const digest_index = i % num_entries;
        const digest = createTestDigest(@intCast(digest_index));
        defer allocator.free(digest);

        _ = cache.get(digest);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 100); // Should complete in less than 100ms
    std.debug.print("Completed {d} cache accesses in {d}ms\n", .{ access_patterns, duration });
}
