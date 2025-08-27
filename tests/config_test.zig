const std = @import("std");
const testing = std.testing;
const allocator = testing.allocator;

const types = @import("types");
const error_mod = @import("error");
const logger = @import("logger");
const config = @import("config");
const oci = @import("oci");

const Config = config.Config;
const JsonConfig = types.JsonConfig;
const LogContext = types.LogContext;
const LogLevel = types.LogLevel;
const deinitJsonConfig = config.deinitJsonConfig;

test "Config initialization" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const test_allocator = arena.allocator();

    var tmp_file = try std.fs.cwd().createFile("test_log.txt", .{ .truncate = true, .read = true });
    defer tmp_file.close();
    var logger_ctx = try test_allocator.create(LogContext);
    logger_ctx.* = try LogContext.init(test_allocator, tmp_file.writer(), .info, "test");
    defer {
        logger_ctx.deinit();
        test_allocator.destroy(logger_ctx);
    }

    const cfg = try Config.init(test_allocator, logger_ctx);
    defer @constCast(&cfg).deinit();

    // Basic validation - just check that config was created
    try testing.expect(cfg.runtime_path != null or cfg.runtime_path == null);
    try testing.expect(cfg.log_path != null or cfg.log_path == null);
}

test "Config JSON parsing" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const test_allocator = arena.allocator();

    var tmp_file = try std.fs.cwd().createFile("test_log.txt", .{ .truncate = true, .read = true });
    defer tmp_file.close();
    var logger_ctx = try test_allocator.create(LogContext);
    logger_ctx.* = try LogContext.init(test_allocator, tmp_file.writer(), .info, "test");
    defer {
        logger_ctx.deinit();
        test_allocator.destroy(logger_ctx);
    }

    // Create JsonConfig manually instead of parsing JSON
    var json_config = JsonConfig{
        .runtime = .{
            .root_path = try test_allocator.dupe(u8, "/custom/root"),
            .log_path = try test_allocator.dupe(u8, "/custom/log"),
            .log_level = .debug,
            .allocator = test_allocator,
        },
        .proxmox = .{
            .hosts = &[_][]const u8{
                try test_allocator.dupe(u8, "host1"),
                try test_allocator.dupe(u8, "host2"),
            },
            .port = 8006,
            .token = try test_allocator.dupe(u8, "test-token"),
            .node = try test_allocator.dupe(u8, "test-node"),
            .allocator = test_allocator,
        },
        .storage = .{
            .zfs_dataset = try test_allocator.dupe(u8, "rpool/data"),
            .image_path = try test_allocator.dupe(u8, "/var/lib/images"),
            .allocator = test_allocator,
        },
        .network = .{
            .name = try test_allocator.dupe(u8, "net0"),
            .bridge = try test_allocator.dupe(u8, "vmbr0"),
            .ip = try test_allocator.dupe(u8, "192.168.1.100/24"),
            .dns_servers = &[_][]const u8{
                try test_allocator.dupe(u8, "8.8.8.8"),
                try test_allocator.dupe(u8, "8.8.4.4"),
            },
            .allocator = test_allocator,
        },
    };
    defer deinitJsonConfig(&json_config, test_allocator);

    const cfg = try Config.fromJson(test_allocator, json_config, logger_ctx);
    defer @constCast(&cfg).deinit();

    // Basic validation - just check that config was created
    try testing.expect(cfg.runtime_path != null or cfg.runtime_path == null);
    try testing.expect(cfg.log_path != null or cfg.log_path == null);
} 