const std = @import("std");
const testing = std.testing;
const json = @import("json");
const Config = @import("config").Config;
const JsonConfig = @import("config").JsonConfig;
const LogLevel = @import("../src/common/types").LogLevel;
const deinitJsonConfig = @import("config").deinitJsonConfig;
const LogContext = @import("../src/common/types").LogContext;

test "Config initialization" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_file = try std.fs.cwd().createFile("test_log.txt", .{ .truncate = true, .read = true });
    defer tmp_file.close();
    var logger_ctx = try allocator.create(LogContext);
    logger_ctx.* = try LogContext.init(allocator, tmp_file.writer(), .info, "test");
    defer {
        logger_ctx.deinit();
        allocator.destroy(logger_ctx);
    }

    const config = try Config.init(allocator, logger_ctx);
    defer @constCast(&config).deinit();

    // try testing.expectEqual(@import("oci").runtime.RuntimeType.runc, config.runtime_type);
    try testing.expectEqual(@as(?[]const u8, null), config.runtime_path);
    try testing.expectEqualStrings("/var/run/proxmox-lxcri", config.root_path);
    try testing.expectEqualStrings("/var/lib/proxmox-lxcri", config.bundle_path);
    try testing.expectEqual(@as(?[]const u8, null), config.log_path);
    try testing.expectEqual(@as(?[]const u8, null), config.pid_file);
    try testing.expectEqual(@as(?[]const u8, null), config.console_socket);
    try testing.expectEqual(false, config.systemd_cgroup);
    try testing.expectEqual(false, config.debug);
}

test "Config from JSON" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_file = try std.fs.cwd().createFile("test_log.txt", .{ .truncate = true, .read = true });
    defer tmp_file.close();
    var logger_ctx = try allocator.create(LogContext);
    logger_ctx.* = try LogContext.init(allocator, tmp_file.writer(), .info, "test");
    defer {
        logger_ctx.deinit();
        allocator.destroy(logger_ctx);
    }

    const json_str =
        \\{
        \\  "runtime": {
        \\    "root_path": "/custom/root",
        \\    "log_path": "/custom/log",
        \\    "log_level": "debug"
        \\  },
        \\  "proxmox": {
        \\    "hosts": ["host1", "host2"],
        \\    "port": 8006,
        \\    "token": "test-token",
        \\    "node": "test-node"
        \\  },
        \\  "storage": {
        \\    "zfs_dataset": "rpool/data",
        \\    "image_path": "/var/lib/images"
        \\  },
        \\  "network": {
        \\    "bridge": "vmbr0",
        \\    "dns_servers": ["8.8.8.8", "8.8.4.4"]
        \\  }
        \\}
    ;

    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(json_str);
    defer tree.deinit();

    const json_config = try JsonConfig.jsonParse(allocator, tree.root, .{});
    defer deinitJsonConfig(&json_config, allocator);

    const config = try Config.fromJson(allocator, json_config, logger_ctx);
    defer @constCast(&config).deinit();

    // Check runtime configuration
    try testing.expectEqualStrings("/custom/root", config.runtime_path.?);
    try testing.expectEqualStrings("/custom/log", config.log_path.?);
    try testing.expectEqual(LogLevel.debug, config.runtime_type);

    // Check proxmox configuration
    try testing.expectEqual(@as(usize, 2), config.proxmox.hosts.len);
    try testing.expectEqualStrings("host1", config.proxmox.hosts[0]);
    try testing.expectEqualStrings("host2", config.proxmox.hosts[1]);
    try testing.expectEqual(@as(u16, 8006), config.proxmox.port);
    try testing.expectEqualStrings("test-token", config.proxmox.token.?);
    try testing.expectEqualStrings("test-node", config.proxmox.node.?);

    // Check storage configuration
    try testing.expectEqualStrings("rpool/data", config.storage.zfs_dataset.?);
    try testing.expectEqualStrings("/var/lib/images", config.storage.image_path.?);

    // Check network configuration
    try testing.expectEqualStrings("vmbr0", config.network.bridge.?);
    try testing.expectEqual(@as(usize, 2), config.network.dns_servers.len);
    try testing.expectEqualStrings("8.8.8.8", config.network.dns_servers[0]);
    try testing.expectEqualStrings("8.8.4.4", config.network.dns_servers[1]);
}

test "Config JSON serialization" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tmp_file = try std.fs.cwd().createFile("test_log.txt", .{ .truncate = true, .read = true });
    defer tmp_file.close();
    var logger_ctx = try allocator.create(LogContext);
    logger_ctx.* = try LogContext.init(allocator, tmp_file.writer(), .info, "test");
    defer {
        logger_ctx.deinit();
        allocator.destroy(logger_ctx);
    }

    const config = try Config.init(allocator, logger_ctx);
    defer @constCast(&config).deinit();

    // Create JsonConfig from Config
    var json_config = JsonConfig{
        .runtime = .{
            .root_path = try allocator.dupe(u8, "/custom/root"),
            .log_path = try allocator.dupe(u8, "/custom/log"),
            .log_level = .debug,
        },
        .proxmox = .{
            .hosts = &[_][]const u8{
                try allocator.dupe(u8, "host1"),
                try allocator.dupe(u8, "host2"),
            },
            .port = 8006,
            .token = try allocator.dupe(u8, "test-token"),
            .node = try allocator.dupe(u8, "test-node"),
        },
        .storage = .{
            .zfs_dataset = try allocator.dupe(u8, "rpool/data"),
            .image_path = try allocator.dupe(u8, "/var/lib/images"),
        },
        .network = .{
            .bridge = try allocator.dupe(u8, "vmbr0"),
            .dns_servers = &[_][]const u8{
                try allocator.dupe(u8, "8.8.8.8"),
                try allocator.dupe(u8, "8.8.4.4"),
            },
        },
    };
    defer deinitJsonConfig(&json_config, allocator);

    // Serialize JsonConfig to JSON
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try json.stringify(json_config, .{}, buffer.writer());

    // Parse JSON back to JsonConfig
    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(buffer.items);
    defer tree.deinit();

    const parsed_config = try JsonConfig.jsonParse(allocator, tree.root, .{});
    defer deinitJsonConfig(&parsed_config, allocator);

    // Verify that data is preserved
    try testing.expectEqualStrings("/custom/root", parsed_config.runtime.?.root_path.?);
    try testing.expectEqualStrings("/custom/log", parsed_config.runtime.?.log_path.?);
    try testing.expectEqual(LogLevel.debug, parsed_config.runtime.?.log_level.?);

    try testing.expectEqual(@as(usize, 2), parsed_config.proxmox.?.hosts.?.len);
    try testing.expectEqualStrings("host1", parsed_config.proxmox.?.hosts.?[0]);
    try testing.expectEqualStrings("host2", parsed_config.proxmox.?.hosts.?[1]);
    try testing.expectEqual(@as(u16, 8006), parsed_config.proxmox.?.port.?);
    try testing.expectEqualStrings("test-token", parsed_config.proxmox.?.token.?);
    try testing.expectEqualStrings("test-node", parsed_config.proxmox.?.node.?);

    try testing.expectEqualStrings("rpool/data", parsed_config.storage.?.zfs_dataset.?);
    try testing.expectEqualStrings("/var/lib/images", parsed_config.storage.?.image_path.?);

    try testing.expectEqualStrings("vmbr0", parsed_config.network.?.bridge.?);
    try testing.expectEqual(@as(usize, 2), parsed_config.network.?.dns_servers.?.len);
    try testing.expectEqualStrings("8.8.8.8", parsed_config.network.?.dns_servers.?[0]);
    try testing.expectEqualStrings("8.8.4.4", parsed_config.network.?.dns_servers.?[1]);
} 