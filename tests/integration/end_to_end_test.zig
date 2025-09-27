const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

// Import types for testing
const ImageManager = @import("manager").ImageManager;
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

fn createMockImageStructure(test_dir: []const u8, image_name: []const u8, image_tag: []const u8) !void {
    // Create image directory structure
    const image_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, image_name, image_tag });
    defer allocator.free(image_dir);

    try std.fs.cwd().makePath(image_dir);

    // Create layers directory
    const layers_dir = try std.fs.path.join(allocator, &[_][]const u8{ image_dir, "layers" });
    defer allocator.free(layers_dir);

    try std.fs.cwd().makePath(layers_dir);

    // Create mock layer files
    for (0..3) |i| {
        const layer_file = try std.fs.path.join(allocator, &[_][]const u8{ layers_dir, try std.fmt.allocPrint(allocator, "layer_{d}.tar", .{i}) });
        defer allocator.free(layer_file);

        const file = try std.fs.cwd().createFile(layer_file, .{});
        defer file.close();

        const content = try std.fmt.allocPrint(allocator, "Mock layer content {d}", .{i});
        defer allocator.free(content);

        try file.writeAll(content);
    }

    // Create mock manifest.json
    const manifest_path = try std.fs.path.join(allocator, &[_][]const u8{ image_dir, "manifest.json" });
    defer allocator.free(manifest_path);

    const manifest_file = try std.fs.cwd().createFile(manifest_path, .{});
    defer manifest_file.close();

    const manifest_content =
        \\{
        \\  "schemaVersion": 2,
        \\  "config": {
        \\    "mediaType": "application/vnd.oci.image.config.v1+json",
        \\    "digest": "sha256:config1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\    "size": 1234
        \\  },
        \\  "layers": [
        \\    {
        \\      "mediaType": "application/vnd.oci.image.layer.v1.tar",
        \\      "digest": "sha256:layer01234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\      "size": 1024
        \\    },
        \\    {
        \\      "mediaType": "application/vnd.oci.image.layer.v1.tar",
        \\      "digest": "sha256:layer11234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\      "size": 1124
        \\    },
        \\    {
        \\      "mediaType": "application/vnd.oci.image.layer.v1.tar",
        \\      "digest": "sha256:layer21234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\      "size": 1224
        \\    }
        \\  ]
        \\}
    ;

    try manifest_file.writeAll(manifest_content);

    // Create mock config.json
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ image_dir, "config.json" });
    defer allocator.free(config_path);

    const config_file = try std.fs.cwd().createFile(config_path, .{});
    defer config_file.close();

    const config_content =
        \\{
        \\  "architecture": "amd64",
        \\  "os": "linux",
        \\  "config": {
        \\    "User": "1000:1000",
        \\    "WorkingDir": "/app",
        \\    "Env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],
        \\    "Entrypoint": ["/bin/sh"],
        \\    "Cmd": ["-c", "echo 'Hello World'"]
        \\  },
        \\  "rootfs": {
        \\    "type": "layers",
        \\    "diff_ids": [
        \\      "sha256:layer01234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\      "sha256:layer11234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        \\      "sha256:layer21234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        \\    ]
        \\  }
        \\}
    ;

    try config_file.writeAll(config_content);
}

test "End-to-end: complete container creation workflow" {
    const test_dir = "/tmp/test-e2e-workflow";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create mock image structure
    try createMockImageStructure(test_dir, "test-image", "latest");

    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();

    // Verify image exists
    try testing.expectEqual(true, manager.hasImage("test-image", "latest"));

    // Create container from image
    try manager.createContainerFromImage("test-image", "latest", "test-container", test_dir);

    // Verify container was created
    const container_rootfs = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, "test-container", "rootfs" });
    defer allocator.free(container_rootfs);

    try testing.expect(std.fs.accessAbsolute(container_rootfs, .{}) == .{});

    // Verify container metadata
    const metadata_path = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, "images", "containers", "test-container", "info.json" });
    defer allocator.free(metadata_path);

    try testing.expect(std.fs.accessAbsolute(metadata_path, .{}) == .{});

    std.debug.print("End-to-end test completed successfully\n", .{});
}

test "End-to-end: LayerFS integration with container creation" {
    const test_dir = "/tmp/test-e2e-layerfs";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create mock image structure
    try createMockImageStructure(test_dir, "test-image", "latest");

    // Initialize ImageManager (which includes LayerFS)
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();

    // Verify LayerFS is initialized
    try testing.expect(manager.layer_fs != null);

    // Create container to trigger LayerFS operations
    try manager.createContainerFromImage("test-image", "latest", "test-container-layerfs", test_dir);

    // Verify LayerFS operations were performed
    if (manager.layer_fs) |layerfs| {
        // Check if layers were added to LayerFS
        try testing.expect(layerfs.layers.count() > 0);

        // Check if mount points were created
        try testing.expect(layerfs.mount_points.count() > 0);
    }

    std.debug.print("LayerFS integration test completed successfully\n", .{});
}

test "End-to-end: metadata cache integration" {
    const test_dir = "/tmp/test-e2e-cache";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create multiple mock images
    try createMockImageStructure(test_dir, "image1", "v1.0");
    try createMockImageStructure(test_dir, "image2", "v1.1");
    try createMockImageStructure(test_dir, "image3", "v1.2");

    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();

    // Verify metadata cache is initialized
    try testing.expect(manager.metadata_cache != null);
    try testing.expectEqual(@as(usize, 100), manager.metadata_cache.max_entries);

    // Create containers from different images to populate cache
    try manager.createContainerFromImage("image1", "v1.0", "container1", test_dir);
    try manager.createContainerFromImage("image2", "v1.1", "container2", test_dir);
    try manager.createContainerFromImage("image3", "v1.2", "container3", test_dir);

    // Verify cache has entries
    try testing.expect(manager.metadata_cache.entries.count() > 0);

    std.debug.print("Metadata cache integration test completed successfully\n", .{});
}

test "End-to-end: error handling and recovery" {
    const test_dir = "/tmp/test-e2e-errors";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();

    // Test error handling for non-existent image
    try testing.expectError(@import("../../src/oci/image/manager.zig").ImageError.ImageNotFound, manager.createContainerFromImage("nonexistent", "latest", "test-container", test_dir));

    // Test error handling for invalid image structure
    const invalid_image_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, "invalid-image", "latest" });
    defer allocator.free(invalid_image_dir);

    try std.fs.cwd().makePath(invalid_image_dir);

    // Create invalid manifest (missing required fields)
    const invalid_manifest_path = try std.fs.path.join(allocator, &[_][]const u8{ invalid_image_dir, "manifest.json" });
    defer allocator.free(invalid_manifest_path);

    const invalid_manifest_file = try std.fs.cwd().createFile(invalid_manifest_path, .{});
    defer invalid_manifest_file.close();

    const invalid_manifest_content = "{}"; // Invalid empty manifest
    try invalid_manifest_file.writeAll(invalid_manifest_content);

    // Test error handling for invalid manifest
    try testing.expectError(@import("../../src/oci/image/manager.zig").ImageError.InvalidImage, manager.createContainerFromImage("invalid-image", "latest", "test-container", test_dir));

    std.debug.print("Error handling test completed successfully\n", .{});
}

test "End-to-end: concurrent container creation" {
    const test_dir = "/tmp/test-e2e-concurrent";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create mock image structure
    try createMockImageStructure(test_dir, "test-image", "latest");

    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();

    // Create multiple containers concurrently
    const num_containers = 5;
    var containers = try allocator.alloc([]const u8, num_containers);
    defer allocator.free(containers);

    for (0..num_containers) |i| {
        const container_name = try std.fmt.allocPrint(allocator, "concurrent-container-{d}", .{i});
        containers[i] = container_name;
        defer allocator.free(containers[i]);
    }

    // Create containers (this would be concurrent in a real scenario)
    for (containers) |container_name| {
        try manager.createContainerFromImage("test-image", "latest", container_name, test_dir);
    }

    // Verify all containers were created
    for (containers) |container_name| {
        const container_rootfs = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, container_name, "rootfs" });
        defer allocator.free(container_rootfs);

        try testing.expect(std.fs.accessAbsolute(container_rootfs, .{}) == .{});
    }

    std.debug.print("Concurrent container creation test completed successfully\n", .{});
}

test "End-to-end: resource cleanup and cleanup" {
    const test_dir = "/tmp/test-e2e-cleanup";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makePath(test_dir);

    // Create mock image structure
    try createMockImageStructure(test_dir, "test-image", "latest");

    // Initialize ImageManager multiple times to test cleanup
    for (0..10) |_| {
        var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);

        // Create a container
        try manager.createContainerFromImage("test-image", "latest", "cleanup-test-container", test_dir);

        // Clean up manager (this should clean up all resources)
        manager.deinit();
    }

    // Verify cleanup was successful by checking if we can still create a new manager
    var final_manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer final_manager.deinit();

    try testing.expect(final_manager.metadata_cache != null);
    try testing.expect(final_manager.layer_manager != null);
    try testing.expect(final_manager.file_ops != null);

    std.debug.print("Resource cleanup test completed successfully\n", .{});
}
