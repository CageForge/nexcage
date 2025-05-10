const std = @import("std");
const testing = std.testing;
const types = @import("types");
const container = @import("container");
const logger = @import("logger");

test "ContainerConfig initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try types.ContainerConfig.init(allocator);
    defer config.deinit();

    try testing.expectEqualStrings("", config.id);
    try testing.expectEqualStrings("", config.name);
    try testing.expectEqual(types.ContainerState.unknown, config.state);
    try testing.expect(config.pid == null);
    try testing.expectEqualStrings("", config.bundle);
    try testing.expect(config.annotations == null);
    try testing.expect(config.metadata == null);
    try testing.expect(config.image == null);
    try testing.expect(config.command == null);
    try testing.expect(config.args == null);
    try testing.expect(config.working_dir == null);
    try testing.expect(config.envs == null);
    try testing.expect(config.mounts == null);
    try testing.expect(config.devices == null);
    try testing.expect(config.labels == null);
    try testing.expect(config.linux == null);
    try testing.expect(config.log_path == null);
}

test "ContainerManager creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger_ctx = try logger.LogContext.init(allocator, std.io.getStdErr().writer(), .debug, "test");
    defer logger_ctx.deinit();

    var manager = try container.ContainerManager.init(allocator, &logger_ctx);
    defer manager.deinit();

    try testing.expect(manager.config.config.id.len == 0);
    try testing.expect(manager.config.config.state == .unknown);
}

test "ContainerFactory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger_ctx = try logger.LogContext.init(allocator, std.io.getStdErr().writer(), .debug, "test");
    defer logger_ctx.deinit();

    var factory = try container.ContainerFactory.init(allocator, &logger_ctx);
    var spec = try types.ContainerSpec.init(allocator);
    defer spec.deinit();

    spec.config.id = try allocator.dupe(u8, "test-container");
    spec.config.name = try allocator.dupe(u8, "Test Container");

    var manager = try factory.createManager(spec);
    defer manager.deinit();

    try testing.expectEqualStrings("test-container", manager.config.config.id);
    try testing.expectEqualStrings("Test Container", manager.config.config.name);
}

test "NetworkConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try types.NetworkConfig.init(allocator);
    defer config.deinit();

    try testing.expectEqualStrings("", config.name);
    try testing.expectEqualStrings("", config.bridge);
    try testing.expectEqualStrings("", config.ip);
    try testing.expect(config.gateway == null);
    try testing.expect(config.dns_servers == null);
}

test "StorageConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try types.StorageConfig.init(allocator);
    defer config.deinit();

    try testing.expectEqual(types.StorageType.bind, config.type);
    try testing.expectEqualStrings("", config.source);
    try testing.expectEqualStrings("", config.destination);
    try testing.expect(config.options == null);
}

test "ResourceLimits" {
    const limits = types.ResourceLimits{
        .memory = 1024 * 1024 * 1024, // 1GB
        .cpu_shares = 1024,
        .cpu_quota = 100000,
        .cpu_period = 100000,
        .pids = 100,
    };

    try testing.expect(limits.memory.? == 1024 * 1024 * 1024);
    try testing.expect(limits.cpu_shares.? == 1024);
    try testing.expect(limits.cpu_quota.? == 100000);
    try testing.expect(limits.cpu_period.? == 100000);
    try testing.expect(limits.pids.? == 100);
}

test "ContainerSpec initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var spec = try types.ContainerSpec.init(allocator);
    defer spec.deinit();

    try testing.expectEqualStrings("", spec.config.id);
    try testing.expectEqualStrings("", spec.config.name);
    try testing.expect(spec.network == null);
    try testing.expect(spec.storage == null);
    try testing.expect(spec.resources == null);
}
