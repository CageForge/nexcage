const std = @import("std");
const testing = std.testing;
const api = @import("proxmox/api.zig");

test "API client operations" {
    const allocator = testing.allocator;
    
    // Get API configuration from environment
    const base_url = std.os.getenv("PROXMOX_API_URL") orelse "https://localhost:8006/api2/json";
    const token = std.os.getenv("PROXMOX_TOKEN") orelse "root@pam!token=test-token-12345";
    const verify_ssl = if (std.os.getenv("PROXMOX_VERIFY_SSL")) |verify| {
        std.mem.eql(u8, verify, "true");
    } else {
        false;
    };
    
    var client = try api.Client.init(
        allocator,
        base_url,
        token,
        .{
            .verify_ssl = verify_ssl,
            .timeout = 30,
        },
    );
    defer client.deinit();
    
    // Test API version endpoint
    const version = try client.getVersion();
    try testing.expect(version.len > 0);
    
    // Test node list endpoint
    var nodes = try client.getNodes();
    defer nodes.deinit();
    try testing.expect(nodes.items.len > 0);
    
    // Test specific node info
    if (nodes.items.len > 0) {
        const node_name = nodes.items[0].name;
        const node_info = try client.getNodeInfo(node_name);
        try testing.expect(node_info.status.len > 0);
    }
} 