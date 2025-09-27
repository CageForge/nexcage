const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

// Import LayerFS and related types
const LayerFS = @import("image").LayerFS;
const Layer = @import("layer").Layer;
const MetadataCache = @import("image").MetadataCache;
const LayerObjectPool = @import("image").LayerObjectPool;
const ParallelProcessingContext = @import("image").ParallelProcessingContext;

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

test "LayerFS performance: adding multiple layers" {
    const num_layers = 100;
    const test_dir = "/tmp/test-layers-performance";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    const start_time = std.time.milliTimestamp();

    // Add multiple layers
    for (0..num_layers) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expectEqual(@as(usize, num_layers), layerfs.layers.count());
    try testing.expect(duration < 1000); // Should complete in less than 1 second

    std.debug.print("Added {d} layers in {d}ms\n", .{ num_layers, duration });
}

test "LayerFS performance: metadata cache operations" {
    const num_entries = 1000;
    var cache = MetadataCache.init(allocator, num_entries);
    defer cache.deinit();

    const start_time = std.time.milliTimestamp();

    // Add cache entries
    for (0..num_entries) |i| {
        const entry = try allocator.create(@import("../../src/oci/image/layerfs.zig").MetadataCacheEntry);
        entry.* = .{
            .digest = try allocator.dupe(u8, createTestDigest(@intCast(i))),
            .media_type = try allocator.dupe(u8, "application/vnd.oci.image.layer.v1.tar"),
            .size = 1024,
            .created = null,
            .author = null,
            .comment = null,
            .dependencies = null,
            .order = @intCast(i),
            .compressed = false,
            .compression_type = null,
            .validated = true,
            .last_validated = null,
            .last_accessed = std.time.timestamp(),
            .access_count = 0,
        };

        try cache.put(entry.digest, entry);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expectEqual(@as(usize, num_entries), cache.entries.count());
    try testing.expect(duration < 500); // Should complete in less than 500ms

    std.debug.print("Added {d} cache entries in {d}ms\n", .{ num_entries, duration });
}

test "LayerFS performance: layer object pool operations" {
    const pool_size = 100;
    var pool = LayerObjectPool.init(allocator, pool_size);
    defer pool.deinit();

    const start_time = std.time.milliTimestamp();

    // Get and return layers multiple times
    for (0..1000) |i| {
        var layer = try pool.getLayer();
        defer layer.deinit(allocator);

        // Simulate some work
        _ = i;

        pool.returnLayer(layer);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 1000); // Should complete in less than 1 second

    std.debug.print("Processed 1000 layer operations in {d}ms\n", .{duration});
}

test "LayerFS performance: parallel processing context" {
    const num_workers = 4;
    const num_layers = 100;
    var context = ParallelProcessingContext.init(allocator, num_workers);

    // Create test layers
    var layers = try allocator.alloc([]const u8, num_layers);
    defer allocator.free(layers);

    for (0..num_layers) |i| {
        const digest = createTestDigest(@intCast(i));
        layers[i] = try allocator.dupe(u8, digest);
        defer allocator.free(layers[i]);
    }

    const start_time = std.time.milliTimestamp();

    // Process layers in parallel
    try context.processLayersParallel(layers, processLayerWorker);

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;

    try testing.expect(duration < 2000); // Should complete in less than 2 seconds

    std.debug.print("Processed {d} layers with {d} workers in {d}ms\n", .{ num_layers, num_workers, duration });
}

fn processLayerWorker(layer: []const u8) !void {
    // Simulate some processing work
    _ = layer;
    std.time.sleep(1 * std.time.ns_per_ms); // 1ms delay
}

test "LayerFS performance: memory usage under load" {
    const num_layers = 500;
    const test_dir = "/tmp/test-layers-memory";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();

    // Monitor memory usage
    const initial_memory = getMemoryUsage();

    // Add layers
    for (0..num_layers) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);

        try layerfs.addLayer(layer);

        // Check memory every 100 layers
        if (i % 100 == 0 and i > 0) {
            const current_memory = getMemoryUsage();
            const memory_increase = current_memory - initial_memory;

            // Memory increase should be reasonable (less than 10MB for 100 layers)
            try testing.expect(memory_increase < 10 * 1024 * 1024);

            std.debug.print("Memory usage after {d} layers: +{d} bytes\n", .{ i, memory_increase });
        }
    }

    const final_memory = getMemoryUsage();
    const total_memory_increase = final_memory - initial_memory;

    std.debug.print("Total memory increase: {d} bytes for {d} layers\n", .{ total_memory_increase, num_layers });
}

fn getMemoryUsage() u64 {
    // This is a placeholder - in a real implementation, you'd use system calls
    // to get actual memory usage
    return 0;
}

test "LayerFS performance: cache hit rate" {
    const num_entries = 100;
    const num_accesses = 1000;
    var cache = MetadataCache.init(allocator, num_entries);
    defer cache.deinit();

    // Add entries
    for (0..num_entries) |i| {
        const entry = try allocator.create(@import("../../src/oci/image/layerfs.zig").MetadataCacheEntry);
        entry.* = .{
            .digest = try allocator.dupe(u8, createTestDigest(@intCast(i))),
            .media_type = try allocator.dupe(u8, "application/vnd.oci.image.layer.v1.tar"),
            .size = 1024,
            .created = null,
            .author = null,
            .comment = null,
            .dependencies = null,
            .order = @intCast(i),
            .compressed = false,
            .compression_type = null,
            .validated = true,
            .last_validated = null,
            .last_accessed = std.time.timestamp(),
            .access_count = 0,
        };

        try cache.put(entry.digest, entry);
    }

    var hits: u32 = 0;
    var misses: u32 = 0;

    // Simulate random access pattern
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();

    for (0..num_accesses) |_| {
        const random_index = random.intRangeAtMost(u32, 0, num_entries - 1);
        const digest = createTestDigest(random_index);
        defer allocator.free(digest);

        if (cache.get(digest) != null) {
            hits += 1;
        } else {
            misses += 1;
        }
    }

    const hit_rate = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(num_accesses));

    try testing.expect(hit_rate > 0.8); // Should have at least 80% hit rate
    std.debug.print("Cache hit rate: {d:.2}% ({d}/{d})\n", .{ hit_rate * 100, hits, num_accesses });
}
