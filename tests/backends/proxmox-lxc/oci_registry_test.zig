const std = @import("std");
const testing = std.testing;

// Test OCI template detection logic
test "detect OCI template by extension" {
    // Test .tar extension (OCI template)
    const oci_template = "local:vztmpl/redis_latest.tar";
    const is_oci = std.mem.endsWith(u8, oci_template, ".tar") and !std.mem.endsWith(u8, oci_template, ".tar.zst");
    try testing.expect(is_oci);

    // Test .tar.zst extension (Proxmox template, not OCI)
    const proxmox_template = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst";
    const is_not_oci = std.mem.endsWith(u8, proxmox_template, ".tar") and !std.mem.endsWith(u8, proxmox_template, ".tar.zst");
    try testing.expect(!is_not_oci);

    // Test template with storage prefix
    const oci_with_storage = "local:vztmpl/postgres_15.tar";
    const is_oci_storage = std.mem.endsWith(u8, oci_with_storage, ".tar") and !std.mem.endsWith(u8, oci_with_storage, ".tar.zst");
    try testing.expect(is_oci_storage);
}

// Test Proxmox VE version parsing
test "parse Proxmox VE version from pveversion output" {
    const allocator = testing.allocator;
    
    // Simulate pveversion -v output
    const test_output = 
        \\proxmox-ve: 9.1.0 (running kernel: 6.14.8-2-pve)
        \\pve-manager: 9.1.1 (running version: 9.1.1/42db4a6cf33dac83)
        \\proxmox-kernel-helper: 9.0.4
    ;
    
    // Parse proxmox-ve: line
    var lines = std.mem.splitScalar(u8, test_output, '\n');
    var found_version: ?[]const u8 = null;
    
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "proxmox-ve:")) {
            var version_part = std.mem.trimLeft(u8, line["proxmox-ve:".len..], " \t");
            const space_idx = std.mem.indexOfScalar(u8, version_part, ' ') orelse version_part.len;
            const version_str = version_part[0..space_idx];
            
            // Extract major.minor
            const dot_idx = std.mem.indexOfScalar(u8, version_str, '.') orelse break;
            const major = version_str[0..dot_idx];
            const minor_start = dot_idx + 1;
            const minor_end = std.mem.indexOfScalar(u8, version_str[minor_start..], '.') orelse version_str.len;
            const minor = version_str[minor_start..minor_end];
            
            found_version = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ major, minor });
            break;
        }
    }
    
    try testing.expect(found_version != null);
    defer allocator.free(found_version.?);
    try testing.expectEqualStrings("9.1", found_version.?);
}

// Test version comparison for OCI Registry support
test "check OCI Registry support by version" {
    const allocator = testing.allocator;
    
    // Test version 9.1.0 (should support)
    const version_9_1 = try std.fmt.allocPrint(allocator, "9.1", .{});
    defer allocator.free(version_9_1);
    const dot_idx = std.mem.indexOfScalar(u8, version_9_1, '.') orelse unreachable;
    const major_str = version_9_1[0..dot_idx];
    const minor_str = version_9_1[dot_idx + 1 ..];
    const major = try std.fmt.parseInt(u32, major_str, 10);
    const minor = try std.fmt.parseInt(u32, minor_str, 10);
    const supports_9_1 = major > 9 or (major == 9 and minor >= 1);
    try testing.expect(supports_9_1);

    // Test version 9.0.0 (should not support)
    const version_9_0 = try std.fmt.allocPrint(allocator, "9.0", .{});
    defer allocator.free(version_9_0);
    const dot_idx_9_0 = std.mem.indexOfScalar(u8, version_9_0, '.') orelse unreachable;
    const major_str_9_0 = version_9_0[0..dot_idx_9_0];
    const minor_str_9_0 = version_9_0[dot_idx_9_0 + 1 ..];
    const major_9_0 = try std.fmt.parseInt(u32, major_str_9_0, 10);
    const minor_9_0 = try std.fmt.parseInt(u32, minor_str_9_0, 10);
    const supports_9_0 = major_9_0 > 9 or (major_9_0 == 9 and minor_9_0 >= 1);
    try testing.expect(!supports_9_0);

    // Test version 10.0.0 (should support)
    const version_10_0 = try std.fmt.allocPrint(allocator, "10.0", .{});
    defer allocator.free(version_10_0);
    const dot_idx_10_0 = std.mem.indexOfScalar(u8, version_10_0, '.') orelse unreachable;
    const major_str_10_0 = version_10_0[0..dot_idx_10_0];
    const minor_str_10_0 = version_10_0[dot_idx_10_0 + 1 ..];
    const major_10_0 = try std.fmt.parseInt(u32, major_str_10_0, 10);
    const minor_10_0 = try std.fmt.parseInt(u32, minor_str_10_0, 10);
    const supports_10_0 = major_10_0 > 9 or (major_10_0 == 9 and minor_10_0 >= 1);
    try testing.expect(supports_10_0);
}

// Test OCI image reference detection
test "detect OCI image reference format" {
    // Valid OCI image references
    const oci_refs = [_][]const u8{
        "docker.io/library/redis:latest",
        "docker.io/library/postgres:15",
        "quay.io/prometheus/prometheus:v2.45.0",
        "redis:latest",
        "ubuntu:22.04",
    };

    for (oci_refs) |ref| {
        const has_colon = std.mem.indexOf(u8, ref, ":") != null;
        const is_tar = std.mem.endsWith(u8, ref, ".tar.zst");
        const has_vztmpl = std.mem.indexOf(u8, ref, ":vztmpl/") != null;
        const is_proxmox_template = is_tar or has_vztmpl;
        const is_absolute_path = std.fs.path.isAbsolute(ref);
        
        const is_oci_ref = has_colon and !is_proxmox_template and !is_absolute_path;
        try testing.expect(is_oci_ref);
    }

    // Invalid OCI image references (Proxmox templates)
    const proxmox_refs = [_][]const u8{
        "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
        "local:vztmpl/redis_latest.tar",
        "/absolute/path/to/template.tar",
    };

    for (proxmox_refs) |ref| {
        const has_colon = std.mem.indexOf(u8, ref, ":") != null;
        const is_tar = std.mem.endsWith(u8, ref, ".tar.zst");
        const has_vztmpl = std.mem.indexOf(u8, ref, ":vztmpl/") != null;
        const is_proxmox_template = is_tar or has_vztmpl;
        const is_absolute_path = std.fs.path.isAbsolute(ref);
        
        const is_oci_ref = has_colon and !is_proxmox_template and !is_absolute_path;
        try testing.expect(!is_oci_ref);
    }
}

// Test template name construction from OCI image reference
test "construct template name from OCI image reference" {
    const allocator = testing.allocator;
    
    const test_cases = [_]struct {
        image_ref: []const u8,
        expected_template: []const u8,
    }{
        .{ .image_ref = "docker.io/library/redis:latest", .expected_template = "local:vztmpl/redis_latest.tar" },
        .{ .image_ref = "postgres:15", .expected_template = "local:vztmpl/postgres_15.tar" },
        .{ .image_ref = "quay.io/prometheus/prometheus:v2.45.0", .expected_template = "local:vztmpl/prometheus_v2.45.0.tar" },
    };

    for (test_cases) |case| {
        // Extract image name and tag
        const colon_idx = std.mem.lastIndexOfScalar(u8, case.image_ref, ':') orelse case.image_ref.len;
        const image_part = case.image_ref[0..colon_idx];
        const tag_part = if (colon_idx < case.image_ref.len) case.image_ref[colon_idx + 1 ..] else "latest";

        const slash_idx = std.mem.lastIndexOfScalar(u8, image_part, '/');
        const image_name = if (slash_idx) |idx| image_part[idx + 1 ..] else image_part;

        // Construct template name
        const template_name = try std.fmt.allocPrint(allocator, "local:vztmpl/{s}_{s}.tar", .{ image_name, tag_part });
        defer allocator.free(template_name);

        try testing.expectEqualStrings(case.expected_template, template_name);
    }
}

// Test handling of existing template error (exit code 25)
test "detect existing template error" {
    const test_stderr = "refusing to override existing file 'redis_latest.tar'";
    const exit_code: u8 = 25;
    
    const template_exists = exit_code == 25 and std.mem.indexOf(u8, test_stderr, "refusing to override existing file") != null;
    try testing.expect(template_exists);
}

// Test pct create command arguments for OCI templates
test "pct create arguments for OCI template" {
    const allocator = testing.allocator;
    
    // Simulate building pct create command for OCI template
    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (args.items) |arg| {
            allocator.free(arg);
        }
        args.deinit(allocator);
    }
    
    const vmid = "123456";
    const template = "local:vztmpl/redis_latest.tar";
    const hostname = "test-container";
    
    try args.append(allocator, "pct");
    try args.append(allocator, "create");
    try args.append(allocator, vmid);
    try args.append(allocator, template);
    try args.append(allocator, "--hostname");
    try args.append(allocator, hostname);
    try args.append(allocator, "--memory");
    try args.append(allocator, "512");
    try args.append(allocator, "--cores");
    try args.append(allocator, "1");
    try args.append(allocator, "--net0");
    try args.append(allocator, "name=eth0,bridge=vmbr0,ip=dhcp");
    
    // For OCI templates, should NOT include --ostype
    const is_oci_template = std.mem.endsWith(u8, template, ".tar") and !std.mem.endsWith(u8, template, ".tar.zst");
    try testing.expect(is_oci_template);
    
    // Check that --ostype is not in arguments
    var has_ostype = false;
    for (args.items) |arg| {
        if (std.mem.eql(u8, arg, "--ostype")) {
            has_ostype = true;
            break;
        }
    }
    try testing.expect(!has_ostype);
    
    // Check that --unprivileged 0 is not in arguments for OCI templates
    var has_unprivileged_0 = false;
    for (args.items, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "--unprivileged") and i + 1 < args.items.len) {
            if (std.mem.eql(u8, args.items[i + 1], "0")) {
                has_unprivileged_0 = true;
                break;
            }
        }
    }
    try testing.expect(!has_unprivileged_0);
}

// Test pct create command arguments for Proxmox templates
test "pct create arguments for Proxmox template" {
    const allocator = testing.allocator;
    
    // Simulate building pct create command for Proxmox template
    var args = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (args.items) |arg| {
            allocator.free(arg);
        }
        args.deinit(allocator);
    }
    
    const vmid = "123456";
    const template = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst";
    const hostname = "test-container";
    
    try args.append(allocator, "pct");
    try args.append(allocator, "create");
    try args.append(allocator, vmid);
    try args.append(allocator, template);
    try args.append(allocator, "--hostname");
    try args.append(allocator, hostname);
    try args.append(allocator, "--memory");
    try args.append(allocator, "512");
    try args.append(allocator, "--cores");
    try args.append(allocator, "1");
    try args.append(allocator, "--net0");
    try args.append(allocator, "name=eth0,bridge=vmbr0,ip=dhcp");
    
    // For Proxmox templates, should include --ostype
    const is_oci_template = std.mem.endsWith(u8, template, ".tar") and !std.mem.endsWith(u8, template, ".tar.zst");
    try testing.expect(!is_oci_template);
    
    // Add --ostype for Proxmox templates
    try args.append(allocator, "--ostype");
    try args.append(allocator, "ubuntu");
    try args.append(allocator, "--unprivileged");
    try args.append(allocator, "0");
    
    // Check that --ostype is in arguments
    var has_ostype = false;
    for (args.items) |arg| {
        if (std.mem.eql(u8, arg, "--ostype")) {
            has_ostype = true;
            break;
        }
    }
    try testing.expect(has_ostype);
}

