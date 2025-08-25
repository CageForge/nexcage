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
    
    return try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        try allocator.dupe(u8, digest),
        1024 + index * 100,
        null
    );
}

test "Comprehensive: LayerFS performance - adding multiple layers" {
    const num_layers = 50; // Reduced for testing
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
    try testing.expect(duration < 2000); // Should complete in less than 2 seconds
    
    std.debug.print("Added {d} layers in {d}ms\n", .{ num_layers, duration });
}

test "Comprehensive: MetadataCache performance" {
    const num_entries = 100; // Reduced for testing
    var cache = MetadataCache.init(allocator, num_entries);
    defer cache.deinit();
    
    const start_time = std.time.milliTimestamp();
    
    // Add cache entries
    for (0..num_entries) |i| {
        const entry = try allocator.create(@import("image").MetadataCacheEntry);
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
    try testing.expect(duration < 1000); // Should complete in less than 1 second
    
    std.debug.print("Added {d} cache entries in {d}ms\n", .{ num_entries, duration });
}

test "Comprehensive: LayerObjectPool operations" {
    const pool_size = 50;
    var pool = LayerObjectPool.init(allocator, pool_size);
    defer pool.deinit();
    
    const start_time = std.time.milliTimestamp();
    
    // Get and return layers multiple times
    for (0..500) |i| { // Reduced for testing
        var layer = try pool.getLayer();
        defer layer.deinit(allocator);
        
        // Simulate some work
        _ = i;
        
        pool.returnLayer(layer);
    }
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    try testing.expect(duration < 2000); // Should complete in less than 2 seconds
    
    std.debug.print("Processed 500 layer operations in {d}ms\n", .{ duration });
}

test "Comprehensive: Memory leak detection - LayerFS operations" {
    const test_dir = "/tmp/test-memory-leak-layerfs";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    // Create and destroy LayerFS multiple times
    for (0..50) |_| { // Reduced for testing
        var layerfs = try LayerFS.init(allocator, test_dir);
        
        // Add some layers
        for (0..5) |i| { // Reduced for testing
            var layer = try createTestLayer(i);
            defer layer.deinit(allocator);
            
            try layerfs.addLayer(layer);
        }
        
        // This should clean up all resources
        layerfs.deinit();
    }
    
    // If we reach here without memory issues, the test passes
    try testing.expect(true);
}

test "Comprehensive: Memory leak detection - MetadataCache operations" {
    // Create and destroy cache multiple times
    for (0..50) |_| { // Reduced for testing
        var cache = MetadataCache.init(allocator, 50);
        
        // Add some entries
        for (0..25) |i| { // Reduced for testing
            const entry = try allocator.create(@import("image").MetadataCacheEntry);
            entry.* = .{
                .digest = try allocator.dupe(u8, createTestDigest(i)),
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
        
        // This should clean up all resources
        cache.deinit();
    }
    
    try testing.expect(true);
}

test "Comprehensive: Memory leak detection - Layer operations" {
    // Create and destroy layers multiple times
    for (0..500) |i| { // Reduced for testing
        var layer = try createTestLayer(@intCast(i % 50));
        defer layer.deinit(allocator);
        
        // Simulate some operations
        try layer.validate(allocator);
        _ = layer.getOrder();
        _ = layer.isValidated();
    }
    
    try testing.expect(true);
}

test "Comprehensive: Cache hit rate analysis" {
    const num_entries = 50; // Reduced for testing
    const num_accesses = 200; // Reduced for testing
    var cache = MetadataCache.init(allocator, num_entries);
    defer cache.deinit();
    
    // Add entries
    for (0..num_entries) |i| {
        const entry = try allocator.create(@import("image").MetadataCacheEntry);
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
    
    // Simulate access pattern
    for (0..num_accesses) |i| {
        const index = i % (num_entries + 10); // Some hits, some misses
        const digest = if (index < num_entries) 
            createTestDigest(@intCast(index)) 
        else 
            createTestDigest(@intCast(index + 1000)); // Different range for misses
        
        defer allocator.free(digest);
        
        if (cache.get(digest) != null) {
            hits += 1;
        } else {
            misses += 1;
        }
    }
    
    const hit_rate = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(num_accesses));
    
    try testing.expect(hit_rate > 0.5); // Should have at least 50% hit rate
    std.debug.print("Cache hit rate: {d:.2}% ({d}/{d})\n", .{ hit_rate * 100, hits, num_accesses });
}

test "Comprehensive: Stress test - multiple operations" {
    const test_dir = "/tmp/test-stress";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    // Simulate complex workflow
    for (0..25) |_| { // Reduced for testing
        var layerfs = try LayerFS.init(allocator, test_dir);
        var cache = MetadataCache.init(allocator, 50);
        var pool = LayerObjectPool.init(allocator, 25);
        
        // Add layers
        for (0..10) |i| { // Reduced for testing
            var layer = try createTestLayer(i);
            defer layer.deinit(allocator);
            
            try layerfs.addLayer(layer);
        }
        
        // Use cache
        for (0..15) |i| { // Reduced for testing
            const entry = try allocator.create(@import("image").MetadataCacheEntry);
            entry.* = .{
                .digest = try allocator.dupe(u8, createTestDigest(i)),
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
        
        // Use pool
        for (0..20) |i| { // Reduced for testing
            var layer = try pool.getLayer();
            defer layer.deinit(allocator);
            
            _ = i;
            pool.returnLayer(layer);
        }
        
        // Clean up
        layerfs.deinit();
        cache.deinit();
        pool.deinit();
    }
    
    try testing.expect(true);
    std.debug.print("Stress test completed successfully\n", .{});
}
