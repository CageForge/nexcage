const std = @import("std");
const testing = std.testing;
const image = @import("src/oci/image");

test "ImageManifest creation and validation" {
    const allocator = testing.allocator;

    // Create a valid descriptor
    const config = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    // Create a valid layer descriptor
    const layer = image.Descriptor{
        .mediaType = "application/vnd.oci.image.layer.v1.tar+gzip",
        .size = 5678,
        .digest = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    const layers = try allocator.alloc(image.Descriptor, 1);
    layers[0] = layer;

    // Create manifest
    var manifest = try image.createManifest(allocator, config, layers, null);
    defer manifest.deinit(allocator);

    // Test validation
    try manifest.validate();

    // Test schema version
    try testing.expectEqual(@as(u32, 2), manifest.schemaVersion);

    // Test config
    try testing.expectEqualStrings("application/vnd.oci.image.config.v1+json", manifest.config.mediaType);
    try testing.expectEqual(@as(u64, 1234), manifest.config.size);

    // Test layers
    try testing.expectEqual(@as(usize, 1), manifest.layers.len);
    try testing.expectEqualStrings("application/vnd.oci.image.layer.v1.tar+gzip", manifest.layers[0].mediaType);
    try testing.expectEqual(@as(u64, 5678), manifest.layers[0].size);
}

test "ImageManifest with platform" {
    const allocator = testing.allocator;

    // Create platform
    const platform = image.Platform{
        .architecture = "amd64",
        .os = "linux",
        .os_version = null,
        .os_features = null,
        .variant = null,
        .features = null,
    };

    // Create descriptor with platform
    const config = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = platform,
    };

    const layers = try allocator.alloc(image.Descriptor, 0);

    // Create manifest
    var manifest = try image.createManifest(allocator, config, layers, null);
    defer manifest.deinit(allocator);

    // Test validation
    try manifest.validate();

    // Test platform
    try testing.expect(manifest.config.platform != null);
    if (manifest.config.platform) |platform_config| {
        try testing.expectEqualStrings("amd64", platform_config.architecture);
        try testing.expectEqualStrings("linux", platform_config.os);
    }
}

test "ImageManifest with annotations" {
    const allocator = testing.allocator;

    // Create annotations
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();
    try annotations.put("org.opencontainers.image.title", "test-image");
    try annotations.put("org.opencontainers.image.version", "1.0.0");

    // Create config
    const config = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    const layers = try allocator.alloc(image.Descriptor, 0);

    // Create manifest with annotations
    var manifest = try image.createManifest(allocator, config, layers, annotations);
    defer manifest.deinit(allocator);

    // Test validation
    try manifest.validate();

    // Test annotations
    try testing.expect(manifest.annotations != null);
    if (manifest.annotations) |anns| {
        try testing.expectEqualStrings("test-image", anns.get("org.opencontainers.image.title").?);
        try testing.expectEqualStrings("1.0.0", anns.get("org.opencontainers.image.version").?);
    }
}

test "ImageManifest validation errors" {
    // Test invalid schema version
    var invalid_manifest = image.ImageManifest{
        .schemaVersion = 1, // Invalid - should be 2
        .config = undefined,
        .layers = undefined,
        .annotations = null,
    };

    try testing.expectError(image.ImageError.InvalidSchemaVersion, invalid_manifest.validate());
}

test "Descriptor validation errors" {
    // Test invalid media type
    const invalid_descriptor = image.Descriptor{
        .mediaType = "", // Invalid - empty
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    try testing.expectError(image.ImageError.InvalidMediaType, invalid_descriptor.validate());

    // Test invalid size
    const invalid_size_descriptor = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 0, // Invalid - zero size
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    try testing.expectError(image.ImageError.InvalidSize, invalid_size_descriptor.validate());

    // Test invalid digest
    const invalid_digest_descriptor = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "", // Invalid - empty
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    try testing.expectError(image.ImageError.InvalidDigest, invalid_digest_descriptor.validate());

    // Test invalid digest format
    const invalid_format_descriptor = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "invalid-digest", // Invalid - no sha256: prefix
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    try testing.expectError(image.ImageError.InvalidDigestFormat, invalid_format_descriptor.validate());
}

test "Platform validation errors" {
    // Test invalid architecture
    const invalid_arch_platform = image.Platform{
        .architecture = "invalid-arch", // Invalid architecture
        .os = "linux",
        .os_version = null,
        .os_features = null,
        .variant = null,
        .features = null,
    };

    try testing.expectError(image.ImageError.InvalidArchitecture, invalid_arch_platform.validate());

    // Test invalid OS
    const invalid_os_platform = image.Platform{
        .architecture = "amd64",
        .os = "invalid-os", // Invalid OS
        .os_version = null,
        .os_features = null,
        .variant = null,
        .features = null,
    };

    try testing.expectError(image.ImageError.InvalidOS, invalid_os_platform.validate());
}

test "ImageManifest cloning" {
    const allocator = testing.allocator;

    // Create original manifest
    const config = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    const layers = try allocator.alloc(image.Descriptor, 0);

    var original = try image.createManifest(allocator, config, layers, null);
    defer original.deinit(allocator);

    // Clone manifest
    var cloned = try image.cloneManifest(allocator, &original);
    defer cloned.deinit(allocator);

    // Test that cloned is identical
    try testing.expectEqual(original.schemaVersion, cloned.schemaVersion);
    try testing.expectEqualStrings(original.config.mediaType, cloned.config.mediaType);
    try testing.expectEqual(original.config.size, cloned.config.size);
    try testing.expectEqualStrings(original.config.digest, cloned.config.digest);
    try testing.expectEqual(original.layers.len, cloned.layers.len);

    // Test that cloned is independent
    try cloned.validate();
}

test "ImageManifest serialization" {
    const allocator = testing.allocator;

    // Create manifest
    const config = image.Descriptor{
        .mediaType = "application/vnd.oci.image.config.v1+json",
        .size = 1234,
        .digest = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        .urls = null,
        .annotations = null,
        .platform = null,
    };

    const layers = try allocator.alloc(image.Descriptor, 0);

    var manifest = try image.createManifest(allocator, config, layers, null);
    defer manifest.deinit(allocator);

    // Serialize
    const serialized = try image.serializeManifest(allocator, manifest);
    defer allocator.free(serialized);

    // Test that serialized is not empty
    try testing.expect(serialized.len > 0);

    // Test that serialized contains expected content
    try testing.expect(std.mem.indexOf(u8, serialized, "schemaVersion") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "config") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "layers") != null);
}
