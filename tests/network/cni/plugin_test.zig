const std = @import("std");
const testing = std.testing;
const types = @import("../../../src/network/cni/types.zig");
const plugin = @import("../../../src/network/cni/plugin.zig");

test "CNI Plugin - initialization and version check" {
    const allocator = testing.allocator;
    
    // Test valid version
    {
        var config = try types.NetworkConfig.init(allocator, "test-net", "bridge");
        defer config.deinit(allocator);
        
        var cni = try plugin.Plugin.init(allocator, "0.4.0", config);
        defer cni.deinit();
        
        try testing.expect(cni.isVersionSupported());
    }
    
    // Test invalid version
    {
        var config = try types.NetworkConfig.init(allocator, "test-net", "bridge");
        defer config.deinit(allocator);
        
        var cni = try plugin.Plugin.init(allocator, "0.1.0", config);
        defer cni.deinit();
        
        try testing.expect(!cni.isVersionSupported());
    }
}

test "CNI Plugin - network configuration" {
    const allocator = testing.allocator;
    
    var config = try types.NetworkConfig.init(allocator, "test-net", "bridge");
    defer config.deinit(allocator);
    
    // Set bridge configuration
    config.bridge = try allocator.dupe(u8, "cni0");
    config.isGateway = true;
    config.ipMasq = true;
    
    // Add IPAM configuration
    var ipam = try types.IPAM.init(allocator, "host-local");
    ipam.subnet = try allocator.dupe(u8, "10.10.0.0/16");
    config.ipam = ipam;
    
    // Add DNS configuration
    var dns = types.DNS.init();
    const nameservers = try allocator.alloc([]const u8, 2);
    nameservers[0] = try allocator.dupe(u8, "8.8.8.8");
    nameservers[1] = try allocator.dupe(u8, "8.8.4.4");
    dns.nameservers = nameservers;
    config.dns = dns;
    
    var cni = try plugin.Plugin.init(allocator, "0.4.0", config);
    defer cni.deinit();
    
    // Verify configuration
    try testing.expectEqualStrings("test-net", cni.config.name);
    try testing.expectEqualStrings("bridge", cni.config.type);
    try testing.expectEqualStrings("cni0", cni.config.bridge.?);
    try testing.expect(cni.config.isGateway);
    try testing.expect(cni.config.ipMasq);
    
    if (cni.config.ipam) |ipam_config| {
        try testing.expectEqualStrings("host-local", ipam_config.type);
        try testing.expectEqualStrings("10.10.0.0/16", ipam_config.subnet.?);
    } else {
        try testing.expect(false);
    }
    
    if (cni.config.dns) |dns_config| {
        try testing.expectEqualStrings("8.8.8.8", dns_config.nameservers.?[0]);
        try testing.expectEqualStrings("8.8.4.4", dns_config.nameservers.?[1]);
    } else {
        try testing.expect(false);
    }
}

test "CNI Plugin - basic operations" {
    const allocator = testing.allocator;
    
    var config = try types.NetworkConfig.init(allocator, "test-net", "bridge");
    defer config.deinit(allocator);
    
    var cni = try plugin.Plugin.init(allocator, "0.4.0", config);
    defer cni.deinit();
    
    const container_id = "test-container";
    const netns_path = "/var/run/netns/test";
    
    // Test add operation
    try testing.expectError(error.NetworkSetupFailed, cni.add(container_id, netns_path));
    
    // Test check operation
    try testing.expectError(error.NetworkSetupFailed, cni.check(container_id));
    
    // Test delete operation
    try testing.expectError(error.NetworkCleanupFailed, cni.del(container_id, netns_path));
}; 