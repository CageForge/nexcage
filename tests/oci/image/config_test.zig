const std = @import("std");
const testing = std.testing;
const image = @import("../../../src/oci/image");

test "HealthCheck creation and validation" {
    const allocator = testing.allocator;
    
    // Create health check with test command
    const test_cmd = try allocator.alloc([]const u8, 2);
    defer allocator.free(test_cmd);
    test_cmd[0] = "curl";
    test_cmd[1] = "-f";
    
    var health_check = try image.createHealthCheck(
        allocator,
        test_cmd,
        30000000000, // 30 seconds
        5000000000,  // 5 seconds
        10000000000, // 10 seconds
        3,           // 3 retries
    );
    defer health_check.deinit(allocator);
    
    // Test validation
    try health_check.validate();
    
    // Test properties
    try testing.expect(health_check.test != null);
    if (health_check.test) |test| {
        try testing.expectEqual(@as(usize, 2), test.len);
        try testing.expectEqualStrings("curl", test[0]);
        try testing.expectEqualStrings("-f", test[1]);
    }
    
    try testing.expectEqual(@as(i64, 30000000000), health_check.interval.?);
    try testing.expectEqual(@as(i64, 5000000000), health_check.timeout.?);
    try testing.expectEqual(@as(i64, 10000000000), health_check.start_period.?);
    try testing.expectEqual(@as(u32, 3), health_check.retries.?);
}

test "Volume creation and validation" {
    const allocator = testing.allocator;
    
    // Create volume
    var volume = try image.createVolume(allocator, "/data", false);
    defer volume.deinit(allocator);
    
    // Test validation
    try volume.validate();
    
    // Test properties
    try testing.expectEqualStrings("/data", volume.path);
    try testing.expectEqual(false, volume.read_only);
    
    // Test read-only volume
    var ro_volume = try image.createVolume(allocator, "/config", true);
    defer ro_volume.deinit(allocator);
    
    try testing.expectEqualStrings("/config", ro_volume.path);
    try testing.expectEqual(true, ro_volume.read_only);
}

test "MountPoint creation and validation" {
    const allocator = testing.allocator;
    
    // Create mount point
    var mount_point = try image.createMountPoint(
        allocator,
        "/host/data",
        "/container/data",
        false,
        "shared"
    );
    defer mount_point.deinit(allocator);
    
    // Test validation
    try mount_point.validate();
    
    // Test properties
    try testing.expectEqualStrings("/host/data", mount_point.source);
    try testing.expectEqualStrings("/container/data", mount_point.destination);
    try testing.expectEqual(false, mount_point.read_only);
    try testing.expectEqualStrings("shared", mount_point.bind_propagation.?);
    
    // Test without bind propagation
    var simple_mount = try image.createMountPoint(
        allocator,
        "/host/config",
        "/container/config",
        true,
        null
    );
    defer simple_mount.deinit(allocator);
    
    try testing.expectEqualStrings("/host/config", simple_mount.source);
    try testing.expectEqualStrings("/container/config", simple_mount.destination);
    try testing.expectEqual(true, simple_mount.read_only);
    try testing.expect(simple_mount.bind_propagation == null);
}

test "Container configuration creation" {
    const allocator = testing.allocator;
    
    // Create environment variables
    const env_vars = try allocator.alloc([]const u8, 2);
    defer allocator.free(env_vars);
    env_vars[0] = "PATH=/usr/local/bin:/usr/bin:/bin";
    env_vars[1] = "HOME=/home/user";
    
    // Create entrypoint
    const entrypoint = try allocator.alloc([]const u8, 1);
    defer allocator.free(entrypoint);
    entrypoint[0] = "/bin/bash";
    
    // Create command
    const cmd = try allocator.alloc([]const u8, 2);
    defer allocator.free(cmd);
    cmd[0] = "-c";
    cmd[1] = "echo 'Hello World'";
    
    // Create exposed ports
    const ports = try allocator.alloc([]const u8, 2);
    defer allocator.free(ports);
    ports[0] = "8080/tcp";
    ports[1] = "9000/udp";
    
    // Create labels
    var labels = std.StringHashMap([]const u8).init(allocator);
    defer labels.deinit();
    try labels.put("version", "1.0.0");
    try labels.put("maintainer", "test@example.com");
    
    // Create container configuration
    var config = try image.createContainerConfig(
        allocator,
        "user:group",
        "/app",
        entrypoint,
        cmd,
        env_vars,
        ports,
        null, // volumes
        labels,
        "SIGTERM",
        null, // health_check
        null, // mount_points
    );
    
    // Test validation
    try image.validateContainerConfig(&config);
    
    // Test properties
    try testing.expectEqualStrings("user:group", config.user.?);
    try testing.expectEqualStrings("/app", config.working_dir.?);
    try testing.expectEqualStrings("SIGTERM", config.stop_signal.?);
    
    // Test entrypoint
    try testing.expect(config.entrypoint != null);
    if (config.entrypoint) |ep| {
        try testing.expectEqual(@as(usize, 1), ep.len);
        try testing.expectEqualStrings("/bin/bash", ep[0]);
    }
    
    // Test command
    try testing.expect(config.cmd != null);
    if (config.cmd) |c| {
        try testing.expectEqual(@as(usize, 2), c.len);
        try testing.expectEqualStrings("-c", c[0]);
        try testing.expectEqualStrings("echo 'Hello World'", c[1]);
    }
    
    // Test environment variables
    try testing.expect(config.env != null);
    if (config.env) |env| {
        try testing.expectEqual(@as(usize, 2), env.len);
        try testing.expectEqualStrings("PATH=/usr/local/bin:/usr/bin:/bin", env[0]);
        try testing.expectEqualStrings("HOME=/home/user", env[1]);
    }
    
    // Test exposed ports
    try testing.expect(config.exposed_ports != null);
    
    // Test labels
    try testing.expect(config.labels != null);
    if (config.labels) |l| {
        try testing.expectEqualStrings("1.0.0", l.get("version").?);
        try testing.expectEqualStrings("test@example.com", l.get("maintainer").?);
    }
}

test "Image configuration creation" {
    const allocator = testing.allocator;
    
    // Create rootfs
    const diff_ids = try allocator.alloc([]const u8, 1);
    defer allocator.free(diff_ids);
    diff_ids[0] = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    
    var rootfs = image.types.Rootfs{
        .type = "layers",
        .diff_ids = diff_ids,
    };
    
    // Create image configuration
    var image_config = try image.createConfig(
        allocator,
        "amd64",
        "linux",
        null, // config
        rootfs,
        null, // history
    );
    
    // Test properties
    try testing.expectEqualStrings("amd64", image_config.architecture);
    try testing.expectEqualStrings("linux", image_config.os);
    try testing.expectEqualStrings("layers", image_config.rootfs.type);
    try testing.expectEqual(@as(usize, 1), image_config.rootfs.diff_ids.len);
    try testing.expectEqualStrings("sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef", image_config.rootfs.diff_ids[0]);
}

test "Configuration validation errors" {
    // Test invalid architecture
    const diff_ids = try std.testing.allocator.alloc([]const u8, 1);
    defer std.testing.allocator.free(diff_ids);
    diff_ids[0] = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    
    var rootfs = image.types.Rootfs{
        .type = "layers",
        .diff_ids = diff_ids,
    };
    
    // Test with empty architecture
    try std.testing.expectError(image.ConfigError.InvalidConfig, image.createConfig(
        std.testing.allocator,
        "",
        "linux",
        null,
        rootfs,
        null,
    ));
    
    // Test with empty OS
    try std.testing.expectError(image.ConfigError.InvalidConfig, image.createConfig(
        std.testing.allocator,
        "amd64",
        "",
        null,
        rootfs,
        null,
    ));
    
    // Test with empty rootfs type
    var invalid_rootfs = image.types.Rootfs{
        .type = "",
        .diff_ids = diff_ids,
    };
    
    try std.testing.expectError(image.ConfigError.InvalidRootFS, image.createConfig(
        std.testing.allocator,
        "amd64",
        "linux",
        null,
        invalid_rootfs,
        null,
    ));
}

test "Port and volume parsing" {
    const allocator = testing.allocator;
    
    // Test exposed ports parsing
    const ports = try allocator.alloc([]const u8, 2);
    defer allocator.free(ports);
    ports[0] = "8080/tcp";
    ports[1] = "9000/udp";
    
    var ports_map = try image.parseExposedPortsFromArray(allocator, ports);
    defer ports_map.deinit();
    
    try testing.expectEqual(@as(usize, 2), ports_map.count());
    try testing.expect(ports_map.contains("8080/tcp"));
    try testing.expect(ports_map.contains("9000/udp"));
    
    // Test volumes parsing
    const volumes = try allocator.alloc([]const u8, 2);
    defer allocator.free(volumes);
    volumes[0] = "/data";
    volumes[1] = "/config";
    
    var volumes_map = try image.parseVolumesFromArray(allocator, volumes);
    defer volumes_map.deinit();
    
    try testing.expectEqual(@as(usize, 2), volumes_map.count());
    try testing.expect(volumes_map.contains("/data"));
    try testing.expect(volumes_map.contains("/config"));
}

test "Configuration serialization" {
    const allocator = testing.allocator;
    
    // Create a simple configuration
    const diff_ids = try allocator.alloc([]const u8, 1);
    defer allocator.free(diff_ids);
    diff_ids[0] = "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
    
    var rootfs = image.types.Rootfs{
        .type = "layers",
        .diff_ids = diff_ids,
    };
    
    var image_config = try image.createConfig(
        allocator,
        "amd64",
        "linux",
        null,
        rootfs,
        null,
    );
    
    // Serialize configuration
    var serialized = try image.serializeConfig(allocator, image_config);
    defer allocator.free(serialized);
    
    // Test that serialized is not empty
    try testing.expect(serialized.len > 0);
    
    // Test that serialized contains expected content
    try testing.expect(std.mem.indexOf(u8, serialized, "architecture") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "amd64") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "linux") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "layers") != null);
}
