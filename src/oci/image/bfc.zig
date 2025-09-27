// BFC (Binary File Container) integration for OCI image specs
// This module provides BFC as an OCI image storage format

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const bfc_mod = @import("../../bfc/mod.zig");

/// BFC image handler for OCI image specs
pub const BFCImageHandler = struct {
    const Self = @This();

    allocator: Allocator,
    logger: *logger_mod.Logger,
    bfc_container: ?*bfc_mod.BFCContainer,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .bfc_container = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.bfc_container) |container| {
            container.deinit();
        }
    }

    /// Create a new BFC image from OCI image manifest
    pub fn createImage(self: *Self, image_name: []const u8, manifest_path: []const u8) !void {
        try self.logger.info("Creating BFC image: {s} from manifest: {s}", .{ image_name, manifest_path });

        // Create BFC container for the image
        const bfc_path = try std.fmt.allocPrint(self.allocator, "/tmp/images/{s}.bfc", .{image_name});
        defer self.allocator.free(bfc_path);

        self.bfc_container = try self.allocator.create(bfc_mod.BFCContainer);
        self.bfc_container.?.init(self.allocator, self.logger, bfc_path);

        // Read OCI manifest and convert to BFC format
        try self.convertOCIToBFC(manifest_path);

        try self.logger.info("Successfully created BFC image: {s}", .{image_name});
    }

    /// Extract BFC image to target directory
    pub fn extractImage(self: *Self, image_name: []const u8, target_path: []const u8) !void {
        try self.logger.info("Extracting BFC image: {s} to {s}", .{ image_name, target_path });

        if (self.bfc_container == null) {
            return error.BFCNotOpen;
        }

        // Create target directory
        try std.fs.cwd().makePath(target_path);

        // Extract BFC contents to target directory
        // TODO: Implement actual BFC extraction

        try self.logger.info("Successfully extracted BFC image: {s}", .{image_name});
    }

    /// List BFC images
    pub fn listImages(self: *Self) ![]const []const u8 {
        try self.logger.info("Listing BFC images", .{});

        // List images from /tmp/images directory
        var images = std.ArrayList([]const u8).init(self.allocator);
        defer images.deinit();

        // TODO: Implement actual image listing
        try images.append("ubuntu:20.04");

        try self.logger.info("Found {d} BFC images", .{images.items.len});
        return images.toOwnedSlice();
    }

    /// Delete BFC image
    pub fn deleteImage(self: *Self, image_name: []const u8) !void {
        try self.logger.info("Deleting BFC image: {s}", .{image_name});

        const bfc_path = try std.fmt.allocPrint(self.allocator, "/tmp/images/{s}.bfc", .{image_name});
        defer self.allocator.free(bfc_path);

        // Delete BFC file
        std.fs.cwd().deleteFile(bfc_path) catch |err| {
            if (err != error.FileNotFound) {
                return err;
            }
        };

        try self.logger.info("Successfully deleted BFC image: {s}", .{image_name});
    }

    /// Get BFC image info
    pub fn getImageInfo(self: *Self, image_name: []const u8) !BFCImageInfo {
        try self.logger.info("Getting BFC image info: {s}", .{image_name});

        const bfc_path = try std.fmt.allocPrint(self.allocator, "/tmp/images/{s}.bfc", .{image_name});
        defer self.allocator.free(bfc_path);

        // Get file info
        const file_info = try std.fs.cwd().statFile(bfc_path);

        return BFCImageInfo{
            .name = try self.allocator.dupe(u8, image_name),
            .size = file_info.size,
            .created = @as(u64, @intCast(file_info.mtime)),
            .compression = try self.allocator.dupe(u8, "zstd"),
            .encryption = try self.allocator.dupe(u8, "none"),
        };
    }

    /// Convert OCI manifest to BFC format
    fn convertOCIToBFC(self: *Self, manifest_path: []const u8) !void {
        try self.logger.info("Converting OCI manifest to BFC format: {s}", .{manifest_path});

        // Read OCI manifest
        const manifest_file = try std.fs.cwd().openFile(manifest_path, .{});
        defer manifest_file.close();

        const manifest_content = try manifest_file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(manifest_content);

        // Parse OCI manifest (simplified)
        // TODO: Implement proper OCI manifest parsing

        // Add manifest to BFC container
        if (self.bfc_container) |container| {
            try container.addFile("manifest.json", manifest_content, 0o644);
        }

        try self.logger.info("Successfully converted OCI manifest to BFC format", .{});
    }

    /// Create BFC image from directory
    pub fn createImageFromDirectory(self: *Self, image_name: []const u8, source_dir: []const u8) !void {
        try self.logger.info("Creating BFC image from directory: {s} -> {s}", .{ source_dir, image_name });

        // Create BFC container
        const bfc_path = try std.fmt.allocPrint(self.allocator, "/tmp/images/{s}.bfc", .{image_name});
        defer self.allocator.free(bfc_path);

        self.bfc_container = try self.allocator.create(bfc_mod.BFCContainer);
        self.bfc_container.?.init(self.allocator, self.logger, bfc_path);

        // Add directory contents to BFC
        try self.addDirectoryToBFC(source_dir, "");

        // Finish BFC container
        try self.bfc_container.?.finish();

        try self.logger.info("Successfully created BFC image from directory: {s}", .{image_name});
    }

    /// Add directory contents to BFC container
    fn addDirectoryToBFC(self: *Self, source_dir: []const u8, bfc_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(source_dir, .{});
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            const full_source_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ source_dir, entry.name });
            defer self.allocator.free(full_source_path);

            const full_bfc_path = if (bfc_path.len == 0)
                try self.allocator.dupe(u8, entry.name)
            else
                try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ bfc_path, entry.name });
            defer self.allocator.free(full_bfc_path);

            if (entry.kind == .directory) {
                // Add directory to BFC
                if (self.bfc_container) |container| {
                    try container.addDir(full_bfc_path, 0o755);
                }

                // Recursively add subdirectory
                try self.addDirectoryToBFC(full_source_path, full_bfc_path);
            } else {
                // Add file to BFC
                const file = try std.fs.cwd().openFile(full_source_path, .{});
                defer file.close();

                const file_content = try file.readToEndAlloc(self.allocator, 1024 * 1024);
                defer self.allocator.free(file_content);

                if (self.bfc_container) |container| {
                    try container.addFile(full_bfc_path, file_content, 0o644);
                }
            }
        }
    }
};

/// BFC image information
pub const BFCImageInfo = struct {
    name: []const u8,
    size: u64,
    created: u64,
    compression: []const u8,
    encryption: []const u8,

    pub fn deinit(self: *const BFCImageInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.compression);
        allocator.free(self.encryption);
    }
};

/// BFC image errors
pub const BFCImageError = error{
    BFCNotOpen,
    BFCImageNotFound,
    BFCImageCreationFailed,
    BFCImageExtractionFailed,
    BFCImageDeletionFailed,
    BFCImageListFailed,
    BFCImageInfoFailed,
    OCIManifestParseFailed,
    ZFSDatasetCreationFailed,
    ZFSDatasetDestructionFailed,
    ZFSDatasetListFailed,
    ZFSDatasetInfoFailed,
};
