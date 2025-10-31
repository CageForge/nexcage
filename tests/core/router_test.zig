const std = @import("std");
const testing = std.testing;
const core = @import("core");
const types = core.types;

test "BackendRouter initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = core.router.BackendRouter.init(allocator, null);
    try testing.expect(router.allocator == allocator);
    try testing.expect(router.logger == null);
}

test "BackendRouter initWithDebug" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer = std.ArrayList(u8).init(allocator);
    defer stdout_buffer.deinit();
    const logger = core.LogContext.init(allocator, stdout_buffer.writer(), .info, "test");
    defer logger.deinit();

    var router = core.router.BackendRouter.initWithDebug(allocator, &logger, false);
    try testing.expect(router.allocator == allocator);
    try testing.expect(router.logger != null);
}

test "BackendRouter createSandboxConfig for create operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = core.router.BackendRouter.init(allocator, null);
    
    const create_op = core.router.Operation{ .create = .{ .image = "ubuntu:latest" } };
    
    const sandbox_config = try router.createSandboxConfig(create_op, "test-container", .proxmox_lxc, null);
    defer router.cleanupSandboxConfig(create_op, &sandbox_config);
    
    try testing.expectEqualStrings("test-container", sandbox_config.name);
    try testing.expect(sandbox_config.runtime_type == .proxmox_lxc);
    try testing.expect(sandbox_config.image != null);
    if (sandbox_config.image) |img| {
        try testing.expectEqualStrings("ubuntu:latest", img);
    }
}

test "BackendRouter createSandboxConfig for run operation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = core.router.BackendRouter.init(allocator, null);
    
    const run_op = core.router.Operation{ .run = .{ .image = "alpine:latest" } };
    
    const sandbox_config = try router.createSandboxConfig(run_op, "run-container", .crun, null);
    defer router.cleanupSandboxConfig(run_op, &sandbox_config);
    
    try testing.expectEqualStrings("run-container", sandbox_config.name);
    try testing.expect(sandbox_config.runtime_type == .crun);
    try testing.expect(sandbox_config.image != null);
    if (sandbox_config.image) |img| {
        try testing.expectEqualStrings("alpine:latest", img);
    }
}

test "BackendRouter createSandboxConfig with network config" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = core.router.BackendRouter.init(allocator, null);
    
    // Create a config with network settings
    var config = try core.Config.init(allocator, .lxc);
    defer config.deinit();
    
    const network = types.NetworkConfig{
        .bridge = try allocator.dupe(u8, "test-bridge"),
        .ip = try allocator.dupe(u8, "10.0.0.1"),
        .gateway = try allocator.dupe(u8, "10.0.0.254"),
        .dns = null,
        .port_mappings = null,
    };
    errdefer {
        allocator.free(network.bridge);
        if (network.ip) |ip| allocator.free(ip);
        if (network.gateway) |gw| allocator.free(gw);
    }
    config.network = network;
    
    const create_op = core.router.Operation{ .create = .{ .image = "ubuntu:latest" } };
    
    const sandbox_config = try router.createSandboxConfig(create_op, "net-container", .lxc, config);
    defer router.cleanupSandboxConfig(create_op, &sandbox_config);
    
    try testing.expect(sandbox_config.network != null);
    if (sandbox_config.network) |net| {
        try testing.expectEqualStrings("test-bridge", net.bridge);
        if (net.ip) |ip| {
            try testing.expectEqualStrings("10.0.0.1", ip);
        }
    }
}

test "BackendRouter cleanupSandboxConfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var router = core.router.BackendRouter.init(allocator, null);
    
    const create_op = core.router.Operation{ .create = .{ .image = "ubuntu:latest" } };
    
    var sandbox_config = try router.createSandboxConfig(create_op, "cleanup-test", .proxmox_lxc, null);
    
    // Cleanup should free allocated memory
    router.cleanupSandboxConfig(create_op, &sandbox_config);
    
    // If we got here without crashing, cleanup worked
    try testing.expect(true);
}

