const std = @import("std");
const logger_mod = @import("src/common/logger.zig");
const types = @import("src/common/types.zig");
const oci = @import("src/oci/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create logger
    var logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "test");
    defer logger.deinit();

    // Test LXC container creation without Proxmox API
    try logger.info("Testing LXC container creation...", .{});

    // Create LXC manager
    const lxc_manager = try oci.lxc.LXCManager.init(allocator);
    defer allocator.destroy(lxc_manager);

    // Create ZFS manager (simplified)
    const zfs_manager = try oci.zfs.ZFSManager.init(allocator, &logger);
    defer allocator.destroy(zfs_manager);

    // Create image manager (simplified)
    const image_manager = try oci.image.ImageManager.init(allocator, "/usr/bin/umoci", "./images");
    defer allocator.destroy(image_manager);

    // Test container creation options
    const container_id = "test-nginx-lxc";
    const bundle_path = "./nginx-bundle";
    const runtime = "lxc";

    try logger.info("Container ID: {s}", .{container_id});
    try logger.info("Bundle path: {s}", .{bundle_path});
    try logger.info("Runtime: {s}", .{runtime});

    // Test bundle validation
    try logger.info("Validating bundle...", .{});

    // Check if bundle exists
    const bundle_dir = try std.fs.cwd().openDir(bundle_path, .{});
    defer bundle_dir.close();

    try logger.info("Bundle directory opened successfully", .{});

    // Check if config.json exists
    const config_file = try bundle_dir.openFile("config.json", .{});
    defer config_file.close();

    try logger.info("Config file opened successfully", .{});

    // Check if rootfs exists
    const rootfs_dir = try bundle_dir.openDir("rootfs", .{});
    defer rootfs_dir.close();

    try logger.info("Rootfs directory opened successfully", .{});

    try logger.info("Bundle validation completed successfully!", .{});
    try logger.info("LXC container creation test completed!", .{});
}
