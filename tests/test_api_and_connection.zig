const std = @import("std");
const testing = std.testing;
const api = @import("proxmox/api.zig");
const logger_mod = @import("logger");
const proxmox = @import("proxmox");
const Error = @import("error").Error;
const Connection = @import("proxmox/connection.zig").Connection;

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

test "Connection initialization and basic operations" {
    const allocator = testing.allocator;
    
    // Get connection details from environment or use defaults
    const host = std.os.getenv("PROXMOX_HOST") orelse "localhost";
    const port = if (std.os.getenv("PROXMOX_PORT")) |port_str| {
        try std.fmt.parseInt(u16, port_str, 10);
    } else {
        8006;
    };
    const token = std.os.getenv("PROXMOX_TOKEN") orelse "root@pam!token=test-token-12345";
    const verify_ssl = if (std.os.getenv("PROXMOX_VERIFY_SSL")) |verify| {
        std.mem.eql(u8, verify, "true");
    } else {
        false;
    };
    
    var conn = try Connection.init(
        allocator,
        host,
        port,
        token,
        verify_ssl,
    );
    defer conn.deinit();
    
    // Test basic connection operations
    try testing.expect(conn.isConnected());
    
    // Test request sending
    const response = try conn.sendRequest(.GET, "/version", null);
    defer allocator.free(response);
    try testing.expect(response.len > 0);
}

test "Proxmox client initialization and operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logger_mod.Logger.init(allocator, .debug, std.io.getStdOut().writer());
    defer logger.deinit();

    const hosts = [_][]const u8{"mgr.cp.if.ua"};
    const token = "root@pam!capi=be7823bc-d949-460e-a9ce-28d0844648ed";
    const node = "mgr";

    var client = try proxmox.Client.init(
        allocator,
        &hosts,
        token,
        &logger,
        8006,
        node,
        300,
    );
    defer client.deinit();

    // Test version endpoint
    const response = try client.makeRequest(.GET, "/version", null);
    defer allocator.free(response);
    try testing.expect(response.len > 0);
} 