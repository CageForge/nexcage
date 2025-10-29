const std = @import("std");
const oci_bundle = @import("src/backends/proxmox-lxc/oci_bundle.zig");
const image_converter = @import("src/backends/proxmox-lxc/image_converter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing MySQL OCI bundle conversion...\n", .{});
    
    // Parse OCI bundle
    var parser = oci_bundle.OciBundleParser.init(allocator, null);
    var config = parser.parseBundle("/tmp/mysql-bundle") catch |err| {
        std.debug.print("Failed to parse bundle: {}\n", .{err});
        return;
    };
    defer config.deinit();
    
    std.debug.print("Parsed bundle successfully!\n", .{});
    
    // Show parsed metadata
    if (config.image_name) |name| {
        std.debug.print("Image name: {s}\n", .{name});
    }
    
    if (config.entrypoint) |entrypoint| {
        std.debug.print("ENTRYPOINT: ", .{});
        for (entrypoint, 0..) |arg, i| {
            if (i > 0) std.debug.print(" ", .{});
            std.debug.print("{s}", .{arg});
        }
        std.debug.print("\n", .{});
    }
    
    if (config.cmd) |cmd| {
        std.debug.print("CMD: ", .{});
        for (cmd, 0..) |arg, i| {
            if (i > 0) std.debug.print(" ", .{});
            std.debug.print("{s}", .{arg});
        }
        std.debug.print("\n", .{});
    }
    
    // Test command determination
    var converter = image_converter.ImageConverter.init(allocator, null);
    const main_command = converter.determineMainCommand(&config) catch |err| {
        std.debug.print("Failed to determine main command: {}\n", .{err});
        return;
    };
    defer allocator.free(main_command);
    
    std.debug.print("Determined main command: {s}\n", .{main_command});
    
    // Test template creation (without actual Proxmox upload)
    std.debug.print("Testing template creation...\n", .{});
    
    const temp_rootfs = try std.fmt.allocPrint(allocator, "/tmp/mysql-rootfs-test", .{});
    defer allocator.free(temp_rootfs);
    
    try converter.convertOciToLxcRootfs("/tmp/mysql-bundle", temp_rootfs);
    
    std.debug.print("Template conversion completed!\n", .{});
    std.debug.print("Check init script: /tmp/mysql-rootfs-test/sbin/init\n", .{});
}
