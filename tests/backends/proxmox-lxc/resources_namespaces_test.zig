/// Test for OCI bundle resources and namespaces parsing and application
const std = @import("std");
const testing = std.testing;
const oci_bundle = @import("oci_bundle.zig");

test "parseBundle with resources and namespaces" {
    // Create a temporary directory with config.json and rootfs
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle_resources_ns", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle_resources_ns", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle_resources_ns") catch {};
    
    // Create config.json with resources and namespaces
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
        \\  "hostname": "test-resources-ns",
        \\  "linux": {
        \\    "resources": {
        \\      "memory": {
        \\        "limit": 268435456
        \\      },
        \\      "cpu": {
        \\        "shares": 512
        \\      }
        \\    },
        \\    "namespaces": [
        \\      {"type": "pid"},
        \\      {"type": "network"},
        \\      {"type": "ipc"},
        \\      {"type": "uts"},
        \\      {"type": "mount"},
        \\      {"type": "user"}
        \\    ]
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);
    
    // Create rootfs directory
    try tmp_dir.makeDir("rootfs");
    
    var parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    var bundle_config = try parser.parseBundle("test_bundle_resources_ns");
    defer bundle_config.deinit();
    
    // Verify parsed resource values
    try testing.expect(bundle_config.memory_limit != null);
    try testing.expect(bundle_config.memory_limit.? == 268435456); // 256 MB
    
    try testing.expect(bundle_config.cpu_limit != null);
    try testing.expect(bundle_config.cpu_limit.? == 512.0);
    
    // Verify parsed namespaces
    try testing.expect(bundle_config.namespaces != null);
    try testing.expect(bundle_config.namespaces.?.len == 6);
    
    // Verify namespace types
    const namespaces = bundle_config.namespaces.?;
    var found_pid = false;
    var found_network = false;
    var found_ipc = false;
    var found_uts = false;
    var found_mount = false;
    var found_user = false;
    
    for (namespaces) |ns| {
        if (std.mem.eql(u8, ns.type, "pid")) found_pid = true;
        if (std.mem.eql(u8, ns.type, "network")) found_network = true;
        if (std.mem.eql(u8, ns.type, "ipc")) found_ipc = true;
        if (std.mem.eql(u8, ns.type, "uts")) found_uts = true;
        if (std.mem.eql(u8, ns.type, "mount")) found_mount = true;
        if (std.mem.eql(u8, ns.type, "user")) found_user = true;
    }
    
    try testing.expect(found_pid);
    try testing.expect(found_network);
    try testing.expect(found_ipc);
    try testing.expect(found_uts);
    try testing.expect(found_mount);
    try testing.expect(found_user);
}

test "parseBundle memory limit conversion" {
    // Test that memory limit is correctly parsed from bytes
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle_memory", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle_memory", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle_memory") catch {};
    
    const config_file = try tmp_dir.createFile("config.json", .{});
    defer config_file.close();
    
    // 512 MB = 536870912 bytes
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2",
        \\  "process": {"args": ["/bin/sh"]},
        \\  "root": {"path": "rootfs"},
        \\  "linux": {
        \\    "resources": {
        \\      "memory": {"limit": 536870912}
        \\    }
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);
    try tmp_dir.makeDir("rootfs");
    
    var parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    var bundle_config = try parser.parseBundle("test_bundle_memory");
    defer bundle_config.deinit();
    
    try testing.expect(bundle_config.memory_limit.? == 536870912);
    
    // Verify conversion: 536870912 bytes = 512 MB
    const mb = bundle_config.memory_limit.? / (1024 * 1024);
    try testing.expect(mb == 512);
}

test "parseBundle CPU shares conversion" {
    // Test that CPU shares are correctly parsed
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle_cpu", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle_cpu", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle_cpu") catch {};
    
    const config_file = try tmp_dir.createFile("config.json", .{});
    defer config_file.close();
    
    // 1024 shares = 1 core (approximation)
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2",
        \\  "process": {"args": ["/bin/sh"]},
        \\  "root": {"path": "rootfs"},
        \\  "linux": {
        \\    "resources": {
        \\      "cpu": {"shares": 1024}
        \\    }
        \\  }
        \\}
    ;
    try config_file.writeAll(config_content);
    try tmp_dir.makeDir("rootfs");
    
    var parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    var bundle_config = try parser.parseBundle("test_bundle_cpu");
    defer bundle_config.deinit();
    
    try testing.expect(bundle_config.cpu_limit.? == 1024.0);
    
    // Verify conversion: 1024 shares / 1024 = 1.0 cores
    const cores = bundle_config.cpu_limit.? / 1024.0;
    try testing.expect(cores == 1.0);
}

test "parseBundle without namespaces" {
    // Test that parsing works even without namespaces
    const tmp_dir = std.fs.cwd().makeOpenPath("test_bundle_no_ns", .{}) catch |err| switch (err) {
        error.PathAlreadyExists => std.fs.cwd().openDir("test_bundle_no_ns", .{}),
        else => return err,
    };
    defer tmp_dir.close();
    defer std.fs.cwd().deleteTree("test_bundle_no_ns") catch {};
    
    const config_file = try tmp_dir.createFile("config.json", .{});
    defer config_file.close();
    
    const config_content = 
        \\{
        \\  "ociVersion": "1.0.2",
        \\  "process": {"args": ["/bin/sh"]},
        \\  "root": {"path": "rootfs"}
        \\}
    ;
    try config_file.writeAll(config_content);
    try tmp_dir.makeDir("rootfs");
    
    var parser = oci_bundle.OciBundleParser.init(testing.allocator, null);
    var bundle_config = try parser.parseBundle("test_bundle_no_ns");
    defer bundle_config.deinit();
    
    // Namespaces should be null if not specified
    try testing.expect(bundle_config.namespaces == null);
}

