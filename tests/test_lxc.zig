const std = @import("std");
const testing = std.testing;
const proxmox = @import("proxmox");
const logger = @import("logger");
const types = @import("types");
const Connection = @import("proxmox/connection.zig").Connection;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var log = try logger.Logger.init(allocator, std.io.getStdOut().writer(), types.LogLevel.info);
    defer log.deinit();

    const hosts = [_][]const u8{"mgr.cp.if.ua"};
    const token = std.os.getenv("PROXMOX_TOKEN") orelse "root@pam!token=test-token-12345";
    const node = "mgr";

    var conn = try Connection.init(
        allocator,
        "localhost",
        8006,
        token,
        false,
    );
    defer conn.deinit();

    var client = try proxmox.Client.init(
        allocator,
        &hosts,
        token,
        &log,
        8006,
        node,
        3600,
    );
    defer client.deinit();

    try log.info("Listing LXC containers...", .{});
    const containers = try client.listLXCs();
    defer {
        for (containers) |container| {
            allocator.free(container.name);
        }
        allocator.free(containers);
    }

    try log.info("Found {d} containers:", .{containers.len});
    for (containers) |container| {
        try log.info("Container {d}: {s} (status: {s})", .{
            container.vmid,
            container.name,
            @tagName(container.status),
        });
    }
}

test "LXC container operations" {
    const allocator = testing.allocator;
    
    // Get token from environment variable or use test token
    const token = std.os.getenv("PROXMOX_TOKEN") orelse "root@pam!token=test-token-12345";
    
    var conn = try Connection.init(
        allocator,
        "localhost",
        8006,
        token,
        false,
    );
    defer conn.deinit();
    
    // ... existing code ...
} 