const std = @import("std");
const testing = std.testing;
const network = @import("network");
const proxmox = @import("proxmox");

test "CNI configuration for LXC container" {
    const allocator = testing.allocator;

    // Create test annotations
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    try annotations.put("k8s.v1.cni.cncf.io/networks", "default");
    try annotations.put("k8s.v1.cni.cncf.io/network-status", "");

    // Create test LXC configuration
    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    try config.put("vmid", "100");
    try config.put("hostname", "test-container");

    // Test network configuration
    try proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations);

    // Check results
    const net_config = config.get("net0") orelse {
        try testing.expect(false);
        return;
    };

    // Basic network configuration checks
    try testing.expect(std.mem.indexOf(u8, net_config, "name=eth0") != null);
    try testing.expect(std.mem.indexOf(u8, net_config, "type=veth") != null);
    try testing.expect(std.mem.indexOf(u8, net_config, "bridge=") != null);

    // Check DNS configuration
    if (config.get("nameserver")) |ns| {
        try testing.expect(ns.len > 0);
    }

    if (config.get("searchdomain")) |sd| {
        try testing.expect(sd.len > 0);
    }
}

test "CNI error handling" {
    const allocator = testing.allocator;

    // Create incorrect annotations
    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();

    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    // Expect error when required annotations are missing
    try testing.expectError(
        network.NetworkError.CNIConfigError,
        proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations)
    );
}

test "CNI cleanup on error" {
    const allocator = testing.allocator;

    var annotations = std.StringHashMap([]const u8).init(allocator);
    defer annotations.deinit();
    try annotations.put("k8s.v1.cni.cncf.io/networks", "invalid-network");

    var config = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = config.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        config.deinit();
    }

    try config.put("vmid", "100");

    // Expect all resources to be cleaned up correctly on error
    _ = proxmox.lxc.create.configureKubeOVNNetwork(allocator, &config, annotations) catch |err| {
        try testing.expect(err == network.NetworkError.CNIError);
        return;
    };

    try testing.expect(false);
} 