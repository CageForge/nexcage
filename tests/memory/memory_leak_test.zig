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

    return try Layer.createLayer(allocator, "application/vnd.oci.image.layer.v1.tar", try allocator.dupe(u8, digest), 1024 + index * 100, null);
}

test "Memory leak detection: LayerFS operations" {
    const test_dir = "/tmp/test-memory-leak-layerfs";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create and destroy LayerFS multiple times
    for (0..100) |_| {
        var layerfs = try LayerFS.init(allocator, test_dir);

        // Add some layers
        for (0..10) |i| {
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

test "Memory leak detection: MetadataCache operations" {
    // Create and destroy cache multiple times
    for (0..100) |_| {
        var cache = MetadataCache.init(allocator, 100);

        // Add some entries
        for (0..50) |i| {
            const entry = try allocator.create(@import("../../src/oci/image/layerfs.zig").MetadataCacheEntry);
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

test "Memory leak detection: LayerObjectPool operations" {
    // Create and destroy pool multiple times
    for (0..100) |_| {
        var pool = LayerObjectPool.init(allocator, 50);

        // Get and return layers
        for (0..100) |i| {
            var layer = try pool.getLayer();
            defer layer.deinit(allocator);

            // Simulate some work
            _ = i;

            pool.returnLayer(layer);
        }

        // This should clean up all resources
        pool.deinit();
    }

    try testing.expect(true);
}

test "Memory leak detection: Layer operations" {
    // Create and destroy layers multiple times
    for (0..1000) |i| {
        var layer = try createTestLayer(@intCast(i % 100));
        defer layer.deinit(allocator);

        // Simulate some operations
        try layer.validate(allocator);
        _ = layer.getOrder();
        _ = layer.isValidated();
    }

    try testing.expect(true);
}

test "Memory leak detection: complex operations" {
    const test_dir = "/tmp/test-memory-leak-complex";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Simulate complex workflow
    for (0..50) |_| {
        var layerfs = try LayerFS.init(allocator, test_dir);
        var cache = MetadataCache.init(allocator, 100);
        var pool = LayerObjectPool.init(allocator, 50);

        // Add layers
        for (0..20) |i| {
            var layer = try createTestLayer(i);
            defer layer.deinit(allocator);

            try layerfs.addLayer(layer);
        }

        // Use cache
        for (0..30) |i| {
            const entry = try allocator.create(@import("../../src/oci/image/layerfs.zig").MetadataCacheEntry);
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
        for (0..40) |i| {
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
}

test "Memory leak detection: string operations" {
    // Test string duplication and cleanup
    for (0..1000) |i| {
        const test_string = try std.fmt.allocPrint(allocator, "test_string_{d}", .{i});
        defer allocator.free(test_string);

        // Create some complex strings
        const complex_string = try std.fmt.allocPrint(allocator, "complex_{s}_string_{d}", .{ test_string, i * 2 });
        defer allocator.free(complex_string);

        // Simulate some operations
        _ = test_string.len;
        _ = complex_string.len;
    }

    try testing.expect(true);
}

test "Memory leak detection: hash map operations" {
    // Test hash map operations
    for (0..100) |_| {
        var map = std.StringHashMap([]const u8).init(allocator);
        defer map.deinit();

        // Add entries
        for (0..50) |i| {
            const key = try std.fmt.allocPrint(allocator, "key_{d}", .{i});
            defer allocator.free(key);

            const value = try std.fmt.allocPrint(allocator, "value_{d}", .{i});
            defer allocator.free(value);

            try map.put(key, value);
        }

        // Iterate over entries
        var iter = map.iterator();
        while (iter.next()) |entry| {
            _ = entry.key_ptr.*;
            _ = entry.value_ptr.*;
        }
    }

    try testing.expect(true);
}

test "Memory leak detection: array operations" {
    // Test array operations
    for (0..100) |_| {
        var array = std.ArrayList([]const u8).init(allocator);
        defer array.deinit();

        // Add strings
        for (0..20) |i| {
            const item = try std.fmt.allocPrint(allocator, "item_{d}", .{i});
            defer allocator.free(item);

            try array.append(item);
        }

        // Process array
        for (array.items) |item| {
            _ = item.len;
        }
    }

    try testing.expect(true);
}

test "Memory leak detection: nested structures" {
    // Test nested structure operations
    for (0..50) |_| {
        var outer_map = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator);
        defer outer_map.deinit();

        // Create nested structure
        for (0..10) |i| {
            const outer_key = try std.fmt.allocPrint(allocator, "outer_{d}", .{i});
            defer allocator.free(outer_key);

            var inner_map = std.StringHashMap([]const u8).init(allocator);

            for (0..5) |j| {
                const inner_key = try std.fmt.allocPrint(allocator, "inner_{d}_{d}", .{ i, j });
                defer allocator.free(inner_key);

                const value = try std.fmt.allocPrint(allocator, "value_{d}_{d}", .{ i, j });
                defer allocator.free(value);

                try inner_map.put(inner_key, value);
            }

            try outer_map.put(outer_key, inner_map);
        }

        // Process nested structure
        var outer_iter = outer_map.iterator();
        while (outer_iter.next()) |outer_entry| {
            var inner_iter = outer_entry.value_ptr.iterator();
            while (inner_iter.next()) |inner_entry| {
                _ = inner_entry.key_ptr.*;
                _ = inner_entry.value_ptr.*;
            }
        }
    }

    try testing.expect(true);
}
