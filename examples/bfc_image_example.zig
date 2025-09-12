// Example of using BFC as OCI image storage
// This example demonstrates how to use BFC for storing OCI images

const std = @import("std");
const logger_mod = @import("logger");
const zfs_mod = @import("zfs/mod.zig");
const oci_image = @import("oci/image/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize logger
    var logger = logger_mod.Logger.init(allocator, .info);
    defer logger.deinit();
    
    // Initialize ZFS manager
    var zfs_manager = try zfs_mod.ZFSManager.init(allocator, &logger);
    defer zfs_manager.deinit();
    
    // Initialize BFC image handler
    var bfc_handler = oci_image.BFCImageHandler.init(allocator, &logger, &zfs_manager);
    defer bfc_handler.deinit();
    
    try logger.info("BFC OCI Image Handler Example", .{});
    
    // Create BFC image from directory
    try bfc_handler.createImageFromDirectory("ubuntu:20.04", "/tmp/ubuntu-rootfs");
    
    // List BFC images
    const images = try bfc_handler.listImages();
    defer allocator.free(images);
    
    try logger.info("Available BFC images:", .{});
    for (images) |image| {
        try logger.info("  - {s}", .{image});
    }
    
    // Get image info
    const image_info = try bfc_handler.getImageInfo("ubuntu:20.04");
    defer image_info.deinit(allocator);
    
    try logger.info("Image info for ubuntu:20.04:", .{});
    try logger.info("  Size: {d} bytes", .{image_info.size});
    try logger.info("  Created: {d}", .{image_info.created});
    try logger.info("  Compression: {s}", .{image_info.compression});
    try logger.info("  Encryption: {s}", .{image_info.encryption});
    
    // Extract image to ZFS dataset
    try bfc_handler.extractImage("ubuntu:20.04", "tank/containers/ubuntu-20.04");
    
    try logger.info("BFC OCI Image Handler Example completed successfully", .{});
}
