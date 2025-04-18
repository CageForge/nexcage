const std = @import("std");
const logger_mod = @import("logger");
const proxmox = @import("proxmox");
const Error = @import("error").Error;
const testing = std.testing;
const Connection = @import("proxmox/connection.zig").Connection;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = try logger_mod.Logger.init(allocator, .debug, std.io.getStdOut().writer());
    defer logger.deinit();

    const hosts = [_][]const u8{"mgr.cp.if.ua"};
    const token = "root@pam!capi=be7823bc-d949-460e-a9ce-28d0844648ed";
    const node = "mgr"; // Default node name in Proxmox

    var client = try proxmox.Client.init(
        allocator,
        &hosts,
        token,
        &logger,
        8006, // Default Proxmox port
        node,
        300, // Cache duration in seconds
    );
    defer client.deinit();

    try logger.info("Testing connection to Proxmox API...", .{});

    // Try to get version information
    const response = try client.makeRequest(.GET, "/version", null);
    defer allocator.free(response);

    try logger.info("Proxmox API version: {s}", .{response});
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
    
    // ... existing code ...
}
