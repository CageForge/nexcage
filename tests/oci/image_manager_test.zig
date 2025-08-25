const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

// Import ImageManager and related types
const ImageManager = @import("../../src/oci/image/manager.zig").ImageManager;
const ImageError = @import("../../src/oci/image/manager.zig").ImageError;

test "ImageManager initialization with OCI image system" {
    // Create a temporary directory for testing
    const test_dir = "/tmp/test-images";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Verify that all components are initialized
    try testing.expect(manager.metadata_cache != null);
    try testing.expect(manager.layer_manager != null);
    try testing.expect(manager.file_ops != null);
    try testing.expect(manager.cache_enabled == true);
    
    try testing.expectEqualStrings(test_dir, manager.images_dir);
}

test "ImageManager metadata cache functionality" {
    const test_dir = "/tmp/test-images-cache";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Test cache initialization
    try testing.expectEqual(@as(usize, 0), manager.metadata_cache.entries.count());
    try testing.expectEqual(@as(usize, 100), manager.metadata_cache.max_entries);
}

test "ImageManager layer manager functionality" {
    const test_dir = "/tmp/test-images-layers";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Test layer manager initialization
    try testing.expect(manager.layer_manager != null);
}

test "ImageManager file operations functionality" {
    const test_dir = "/tmp/test-images-files";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Test file operations initialization
    try testing.expect(manager.file_ops != null);
}

test "ImageManager hasImage functionality" {
    const test_dir = "/tmp/test-images-has";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Test hasImage with non-existent image
    try testing.expectEqual(false, manager.hasImage("nonexistent", "latest"));
    
    // Create a test image structure
    const test_image_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, "test-image", "latest" });
    defer allocator.free(test_image_dir);
    
    try std.fs.cwd().makePath(test_image_dir);
    
    // Test hasImage with existing image
    try testing.expectEqual(true, manager.hasImage("test-image", "latest"));
}
