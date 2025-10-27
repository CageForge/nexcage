const std = @import("std");
const testing = std.testing;
const oci_bundle = @import("oci_bundle.zig");

test "OciBundleParser init" {
    const parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    try testing.expect(parser.allocator == testing.allocator);
    try testing.expect(parser.logger == null);
}

test "OciBundleConfig deinit" {
    var config = oci_bundle.OciBundleConfig{
        .allocator = testing.allocator,
        .rootfs_path = try testing.allocator.dupe(u8, "/test/rootfs"),
        .hostname = try testing.allocator.dupe(u8, "test-host"),
        .process_args = null,
        .environment = null,
        .mounts = null,
        .memory_limit = 512 * 1024 * 1024,
        .cpu_limit = 2.0,
        .capabilities = null,
        .seccomp_profile = null,
    };
    
    // Should not crash
    config.deinit();
}

test "MountConfig deinit" {
    var mount = oci_bundle.MountConfig{
        .allocator = testing.allocator,
        .source = try testing.allocator.dupe(u8, "/host/path"),
        .destination = try testing.allocator.dupe(u8, "/container/path"),
        .type = try testing.allocator.dupe(u8, "bind"),
        .options = null,
    };
    
    // Should not crash
    mount.deinit();
}

test "parseBundle with non-existent config" {
    const parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    const result = parser.parseBundle("/non/existent/path");
    try testing.expectError(error.ConfigFileNotFound, result);
}

test "parseBundle with non-existent rootfs" {
    // Create a temporary directory with config.json but no rootfs
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle") catch {};
    
    // Create config.json
    const config_file = try tmp_dir.createFile("config.json", .{});
    defer config_file.close();
    
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2",
        \\  "process": {
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
        \\  },
        \\  "root": {
        \\    "path": "rootfs"
        \\  },
        \\  "hostname": "test-container"
        \\}
    ;
    try config_file.writeAll(config_content);
    
    const parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    const result = parser.parseBundle("test_bundle");
    try testing.expectError(error.RootfsNotFound, result);
}

test "parseBundle with valid bundle" {
    // Create a temporary directory with config.json and rootfs
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle_valid", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle_valid", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle_valid") catch {};
    
    // Create config.json
    const config_file = try tmp_dir.createFile("config.json", .{});
    defer config_file.close();
    
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2",
        \\  "process": {
        \\    "args": ["/bin/sh"],
        \\    "env": ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
        \\  },
        \\  "root": {
        \\    "path": "rootfs"
        \\  },
        \\  "hostname": "test-container",
        \\  "linux": {
        \\    "resources": {
        \\      "memory": {
        \\        "limit": 536870912
        \\      },
        \\      "cpu": {
        \\        "shares": 1024
        \\      }
        \\    }
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);
    
    // Create rootfs directory
    try tmp_dir.makeDir("rootfs");
    
    const parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    var bundle_config = try parser.parseBundle("test_bundle_valid");
    defer bundle_config.deinit();
    
    // Verify parsed values
    try testing.expectEqualStrings("test_bundle_valid/rootfs", bundle_config.rootfs_path);
    try testing.expectEqualStrings("test-container", bundle_config.hostname.?);
    try testing.expect(bundle_config.memory_limit.? == 536870912);
    try testing.expect(bundle_config.cpu_limit.? == 1024.0);
    try testing.expect(bundle_config.process_args != null);
    try testing.expect(bundle_config.process_args.?.len == 1);
    try testing.expectEqualStrings("/bin/sh", bundle_config.process_args.?[0]);
    try testing.expect(bundle_config.environment != null);
    try testing.expect(bundle_config.environment.?.len == 1);
    try testing.expectEqualStrings("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", bundle_config.environment.?[0]);
}
