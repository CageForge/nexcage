const std = @import("std");
const testing = std.testing;
const config = @import("config.zig");
const proxmox = @import("proxmox.zig");
const logger = @import("logger.zig");
const types = @import("types.zig");

test "config initialization" {
    var cfg = try config.Config.init(testing.allocator);
    defer cfg.deinit();

    try testing.expectEqualStrings("localhost", cfg.proxmox.hosts[0]);
    try testing.expectEqual(@as(usize, 0), cfg.proxmox.current_host_index);
    try testing.expectEqual(@as(u16, 8006), cfg.proxmox.port);
    try testing.expectEqualStrings("", cfg.proxmox.token);
    try testing.expectEqualStrings("localhost", cfg.proxmox.node);
    try testing.expectEqual(@as(u64, 60), cfg.proxmox.node_cache_duration);
    try testing.expectEqual(types.LogLevel.info, cfg.runtime.log_level);
    try testing.expectEqualStrings("/var/run/proxmox-lxcri.sock", cfg.runtime.socket_path);
}

test "logger initialization" {
    var log_writer = std.ArrayList(u8).init(testing.allocator);
    defer log_writer.deinit();

    var logger_instance = try logger.Logger.init(testing.allocator, .info, log_writer.writer());
    defer logger_instance.deinit();

    try logger_instance.info("Test message", .{});
    try testing.expectEqualStrings("[INFO] Test message\n", log_writer.items);
}

test "proxmox client initialization" {
    var client = try proxmox.Client.init(.{
        .allocator = testing.allocator,
        .hosts = &[_][]const u8{"test-host"},
        .port = 8006,
        .token = "test-token",
        .node = "test-node",
        .node_cache_duration = 60,
    });
    defer client.deinit();

    try testing.expectEqualStrings("test-host", client.hosts[0]);
    try testing.expectEqual(@as(usize, 0), client.current_host_index);
    try testing.expectEqual(@as(u16, 8006), client.port);
    try testing.expectEqualStrings("test-token", client.token);
    try testing.expectEqualStrings("test-node", client.node);
    try testing.expectEqual(@as(u64, 60), client.node_cache.duration);
}
