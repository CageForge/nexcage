const std = @import("std");
const testing = std.testing;
const image = @import("../../../src/oci/image");

test "Layer creation and basic properties" {
    const allocator = testing.allocator;

    // Create basic layer
    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer layer.deinit(allocator);

    // Test basic properties
    try testing.expectEqualStrings("application/vnd.oci.image.layer.v1.tar", layer.media_type);
    try testing.expectEqualStrings("sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", layer.digest);
    try testing.expectEqual(@as(u64, 1024), layer.size);
    try testing.expect(layer.annotations == null);
    try testing.expect(layer.created == null);
    try testing.expect(layer.author == null);
    try testing.expect(layer.comment == null);
    try testing.expect(layer.dependencies == null);
    try testing.expectEqual(@as(u32, 0), layer.order);
    try testing.expect(layer.storage_path == null);
    try testing.expectEqual(false, layer.compressed);
    try testing.expect(layer.compression_type == null);
    try testing.expectEqual(false, layer.validated);
    try testing.expect(layer.last_validated == null);
}

test "Layer creation with metadata" {
    const allocator = testing.allocator;

    // Create annotations
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();
    try annotations.put("version", "1.0.0");
    try annotations.put("author", "test@example.com");

    // Create dependencies
    const dependencies = try allocator.alloc([]const u8, 1);
    defer allocator.free(dependencies);
    dependencies[0] = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";

    // Create layer with full metadata
    var layer = try image.createLayerWithMetadata(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        2048,
        annotations,
        "2024-01-01T00:00:00Z",
        "Test Author",
        "Test comment",
        dependencies,
        1,
        "/tmp/layer.tar",
        true,
        "gzip",
    );
    defer layer.deinit(allocator);

    // Test metadata properties
    try testing.expectEqualStrings("2024-01-01T00:00:00Z", layer.created.?);
    try testing.expectEqualStrings("Test Author", layer.author.?);
    try testing.expectEqualStrings("Test comment", layer.comment.?);
    try testing.expectEqual(@as(usize, 1), layer.dependencies.?.len);
    try testing.expectEqualStrings("sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890", layer.dependencies.?[0]);
    try testing.expectEqual(@as(u32, 1), layer.order);
    try testing.expectEqualStrings("/tmp/layer.tar", layer.storage_path.?);
    try testing.expectEqual(true, layer.compressed);
    try testing.expectEqualStrings("gzip", layer.compression_type.?);
}

test "Layer validation" {
    const allocator = testing.allocator;

    // Create valid layer
    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer layer.deinit(allocator);

    // Test validation
    try layer.validate(allocator);
    try testing.expectEqual(true, layer.validated);
    try testing.expect(layer.last_validated != null);

    // Test invalid media type
    var invalid_media_layer = try image.createLayer(
        allocator,
        "",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer invalid_media_layer.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidMediaType, invalid_media_layer.validate(allocator));

    // Test invalid digest format
    var invalid_digest_layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "invalid-digest",
        1024,
        null,
    );
    defer invalid_digest_layer.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidDigestFormat, invalid_digest_layer.validate(allocator));

    // Test invalid digest length
    var invalid_length_layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef",
        1024,
        null,
    );
    defer invalid_length_layer.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidDigestLength, invalid_length_layer.validate(allocator));

    // Test invalid size
    var invalid_size_layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        0,
        null,
    );
    defer invalid_size_layer.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidSize, invalid_size_layer.validate(allocator));
}

test "Layer dependencies management" {
    const allocator = testing.allocator;

    // Create layer
    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer layer.deinit(allocator);

    // Test initial state
    try testing.expectEqual(false, layer.hasDependencies());
    try testing.expectEqual(@as(usize, 0), layer.getDependencyCount());

    // Add dependency
    try layer.addDependency(allocator, "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890");
    try testing.expectEqual(true, layer.hasDependencies());
    try testing.expectEqual(@as(usize, 1), layer.getDependencyCount());
    try testing.expectEqual(true, layer.dependsOn("sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"));

    // Add another dependency
    try layer.addDependency(allocator, "sha256:fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321");
    try testing.expectEqual(@as(usize, 2), layer.getDependencyCount());

    // Remove dependency
    try layer.removeDependency(allocator, "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890");
    try testing.expectEqual(@as(usize, 1), layer.getDependencyCount());
    try testing.expectEqual(false, layer.dependsOn("sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"));
    try testing.expectEqual(true, layer.dependsOn("sha256:fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321"));
}

test "Layer compression and storage" {
    const allocator = testing.allocator;

    // Create layer with compression
    var layer = try image.createLayerWithMetadata(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
        null,
        null,
        null,
        null,
        0,
        "/tmp/compressed.tar.gz",
        true,
        "gzip",
    );
    defer layer.deinit(allocator);

    // Test compression properties
    try testing.expectEqual(true, layer.isCompressed());
    try testing.expectEqualStrings("gzip", layer.getCompressionType().?);
    try testing.expectEqualStrings("/tmp/compressed.tar.gz", layer.storage_path.?);

    // Test uncompressed layer
    var uncompressed_layer = try image.createLayerWithMetadata(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        null,
        null,
        null,
        null,
        null,
        0,
        "/tmp/uncompressed.tar",
        false,
        null,
    );
    defer uncompressed_layer.deinit(allocator);

    try testing.expectEqual(false, uncompressed_layer.isCompressed());
    try testing.expect(uncompressed_layer.getCompressionType() == null);
}

test "Layer ordering" {
    const allocator = testing.allocator;

    // Create layer
    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer layer.deinit(allocator);

    // Test initial order
    try testing.expectEqual(@as(u32, 0), layer.getOrder());

    // Set order
    layer.setOrder(5);
    try testing.expectEqual(@as(u32, 5), layer.getOrder());

    // Change order
    layer.setOrder(10);
    try testing.expectEqual(@as(u32, 10), layer.getOrder());
}

test "Layer cloning" {
    const allocator = testing.allocator;

    // Create original layer with metadata
    var original = try image.createLayerWithMetadata(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
        "2024-01-01T00:00:00Z",
        "Test Author",
        "Test comment",
        null,
        1,
        "/tmp/original.tar",
        false,
        null,
    );
    defer original.deinit(allocator);

    // Clone layer
    var cloned = try original.clone(allocator);
    defer cloned.deinit(allocator);

    // Test that cloned layer has same properties
    try testing.expectEqualStrings(original.media_type, cloned.media_type);
    try testing.expectEqualStrings(original.digest, cloned.digest);
    try testing.expectEqual(original.size, cloned.size);
    try testing.expectEqualStrings(original.created.?, cloned.created.?);
    try testing.expectEqualStrings(original.author.?, cloned.author.?);
    try testing.expectEqualStrings(original.comment.?, cloned.comment.?);
    try testing.expectEqual(original.order, cloned.order);
    try testing.expectEqualStrings(original.storage_path.?, cloned.storage_path.?);
    try testing.expectEqual(original.compressed, cloned.compressed);

    // Test that they are independent (modify original)
    original.setOrder(99);
    try testing.expectEqual(@as(u32, 99), original.getOrder());
    try testing.expectEqual(@as(u32, 1), cloned.getOrder());
}

test "LayerManager basic operations" {
    const allocator = testing.allocator;

    // Initialize manager
    var manager = image.initLayerManager(allocator);
    defer manager.deinit();

    // Create layers
    var layer1 = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1111111111111111111111111111111111111111111111111111111111111111",
        1024,
        null,
    );
    defer layer1.deinit(allocator);

    var layer2 = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:2222222222222222222222222222222222222222222222222222222222222222",
        2048,
        null,
    );
    defer layer2.deinit(allocator);

    // Add layers to manager
    try manager.addLayer(layer1);
    try manager.addLayer(layer2);

    // Test getting layers
    try testing.expect(manager.getLayer("sha256:1111111111111111111111111111111111111111111111111111111111111111") != null);
    try testing.expect(manager.getLayer("sha256:2222222222222222222222222222222222222222222222222222222222222222") != null);
    try testing.expect(manager.getLayer("sha256:3333333333333333333333333333333333333333333333333333333333333333") == null);

    // Test getting all layers
    const all_layers = manager.getAllLayers();
    try testing.expectEqual(@as(usize, 2), all_layers.len);

    // Test removing layer
    try manager.removeLayer("sha256:1111111111111111111111111111111111111111111111111111111111111111");
    try testing.expect(manager.getLayer("sha256:1111111111111111111111111111111111111111111111111111111111111111") == null);
    try testing.expectEqual(@as(usize, 1), manager.getAllLayers().len);
}

test "LayerManager dependency management" {
    const allocator = testing.allocator;

    // Initialize manager
    var manager = image.initLayerManager(allocator);
    defer manager.deinit();

    // Create layers with dependencies
    var base_layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:basebasebasebasebasebasebasebasebasebasebasebasebasebasebasebase",
        1024,
        null,
    );
    defer base_layer.deinit(allocator);

    var app_layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:appappappappappappappappappappappappappappappappappappappappapp",
        2048,
        null,
    );
    defer app_layer.deinit(allocator);

    // Add dependency
    try app_layer.addDependency(allocator, base_layer.digest);

    // Add layers to manager
    try manager.addLayer(base_layer);
    try manager.addLayer(app_layer);

    // Test dependency checking
    try manager.checkCircularDependencies();

    // Test sorting by dependencies
    const sorted_layers = try manager.sortLayersByDependencies();
    try testing.expectEqual(@as(usize, 2), sorted_layers.len);

    // Base layer should come first (no dependencies)
    try testing.expectEqualStrings("sha256:basebasebasebasebasebasebasebasebasebasebasebasebasebasebasebase", sorted_layers[0].digest);
    // App layer should come second (depends on base)
    try testing.expectEqualStrings("sha256:appappappappappappappappappappappappappappappappappappappappapp", sorted_layers[1].digest);
}

test "Layer integrity verification" {
    const allocator = testing.allocator;

    // Create a temporary file for testing
    const test_file = "test_layer_data";
    const test_content = "This is test layer data for integrity verification";

    // Write test file
    const file = try fs.cwd().createFile(test_file, .{});
    defer file.close();
    try file.writeAll(test_content);

    // Calculate expected hash
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(test_content);
    const hash_result = hasher.finalResult();
    const expected_digest = try std.fmt.allocPrint(allocator, "sha256:{x:0>64}", .{hash_result});
    defer allocator.free(expected_digest);

    // Create layer with file path
    var layer = try image.createLayerWithMetadata(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        expected_digest,
        @intCast(test_content.len),
        null,
        null,
        null,
        null,
        null,
        0,
        test_file,
        false,
        null,
    );
    defer layer.deinit(allocator);

    // Test integrity verification
    try layer.verifyIntegrity(allocator);
    try testing.expectEqual(true, layer.validated);
    try testing.expect(layer.last_validated != null);

    // Clean up test file
    fs.cwd().deleteFile(test_file) catch {};
}

test "Layer validation errors" {
    const allocator = testing.allocator;

    // Test invalid annotations
    var invalid_annotations = std.StringHashMap([]const u8).init(allocator);
    defer invalid_annotations.deinit();
    try invalid_annotations.put("", "value"); // Empty key

    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        invalid_annotations,
    );
    defer layer.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidAnnotations, layer.validate(allocator));

    // Test invalid annotations with empty value
    var invalid_annotations2 = std.StringHashMap([]const u8).init(allocator);
    defer invalid_annotations2.deinit();
    try invalid_annotations2.put("key", ""); // Empty value

    var layer2 = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        2048,
        invalid_annotations2,
    );
    defer layer2.deinit(allocator);

    try testing.expectError(image.LayerError.InvalidAnnotations, layer2.validate(allocator));
}
