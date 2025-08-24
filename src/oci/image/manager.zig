const std = @import("std");
const types = @import("types");
const umoci = @import("umoci.zig");

/// Default directory names
const IMAGES_DIR = "images";
const BUNDLE_DIR = "bundle";

pub const ImageError = error{
    ImageNotFound,
    InvalidImage,
    InvalidTag,
    BundleError,
};

/// Manages OCI container images
pub const ImageManager = struct {
    allocator: std.mem.Allocator,
    umoci_tool: *umoci.Umoci,
    images_dir: []const u8,

    const Self = @This();

    /// Initialize a new image manager
    pub fn init(allocator: std.mem.Allocator, umoci_path: []const u8, images_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .umoci_tool = try umoci.Umoci.init(allocator, umoci_path),
            .images_dir = try allocator.dupe(u8, images_dir),
        };

        // Create images directory if it doesn't exist
        try std.fs.cwd().makePath(images_dir);

        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.umoci_tool.deinit();
        self.allocator.free(self.images_dir);
        self.allocator.destroy(self);
    }

    /// Unpack an image to a bundle
    pub fn unpackImage(self: *Self, image_name: []const u8, tag: []const u8, bundle_path: []const u8) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        // Check if image exists
        const image_dir = std.fs.openDirAbsolute(image_path, .{}) catch {
            return ImageError.ImageNotFound;
        };
        image_dir.close();

        try self.umoci_tool.unpack(image_path, tag, bundle_path);
    }

    /// Repack a bundle into an image
    pub fn repackImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.repack(image_path, tag, bundle_path);

        if (config) |cfg| {
            try self.umoci_tool.config(image_path, tag, cfg);
        }
    }

    /// Configure an image with the given config
    pub fn configureImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        config: types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.config(image_path, tag, config);
    }

    /// Create a new bundle from an image
    pub fn createBundle(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        // Create bundle directory
        try std.fs.cwd().makePath(bundle_path);

        // Unpack image
        try self.unpackImage(image_name, tag, bundle_path);

        // Configure if needed
        if (config) |cfg| {
            try self.configureImage(image_name, tag, cfg);
        }
    }

    pub fn hasImage(self: *Self, image_name: []const u8, tag: []const u8) bool {
        // Формуємо шлях до образу: images_dir/image_name/tag
        const fs = std.fs;
        const allocator = self.allocator;
        const image_path = fs.path.join(allocator, &[_][]const u8{ self.images_dir, image_name, tag }) catch return false;
        defer allocator.free(image_path);
        
        var dir = fs.cwd().openDir(image_path, .{}) catch return false;
        dir.close();
        return true;
    }
    
    /// Pull an image from a registry (placeholder implementation)
    pub fn pullImage(self: *Self, image_ref: []const u8) !void {
        _ = self;
        _ = image_ref;
        // TODO: Implement actual image pulling from registry
        // For now, this is a placeholder that always succeeds
    }
};
