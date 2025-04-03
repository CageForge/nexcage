const std = @import("std");
const testing = std.testing;
const cri = @import("cri");
const proxmox = @import("proxmox");
const config = @import("config");
const logger = @import("logger");

test "configuration loading" {
    const allocator = testing.allocator;

    var cfg = try config.Config.init(allocator);
    defer cfg.deinit();

    try testing.expect(cfg.proxmox.host.len > 0);
    try testing.expect(cfg.proxmox.port > 0);
    try testing.expect(cfg.runtime.socket_path.len > 0);
}

test "logger initialization" {
    const allocator = testing.allocator;
    const test_file = "test.log";

    const file = try std.fs.cwd().createFile(test_file, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(test_file) catch {};
    }

    var log = try logger.Logger.init(allocator, .debug, file.writer());
    try log.info("Test log message", .{});
}

test "proxmox client" {
    const allocator = testing.allocator;

    var client = try proxmox.Client.init(.{
        .allocator = allocator,
        .host = "localhost",
        .port = 8006,
        .token = "test-token",
    });
    defer client.deinit();

    try testing.expect(client.host.len > 0);
    try testing.expect(client.port == 8006);
}

test "container manager" {
    const allocator = testing.allocator;

    var proxmox_client = try proxmox.Client.init(.{
        .allocator = allocator,
        .host = "localhost",
        .port = 8006,
        .token = "test-token",
    });
    defer proxmox_client.deinit();

    var container_manager = try cri.ContainerManager.init(allocator, &proxmox_client);
    defer container_manager.deinit();

    const container_spec = cri.ContainerSpec{
        .name = "test-container",
        .image = "ubuntu:20.04",
        .command = &[_][]const u8{"bash"},
        .args = &[_][]const u8{},
        .env = &[_]cri.EnvVar{},
    };

    const container = try container_manager.createContainer(container_spec);
    defer container.deinit();

    try testing.expect(container.id.len > 0);
    try testing.expect(container.name.len > 0);
    try testing.expect(container.status == .created);
}

test "pod manager" {
    const allocator = testing.allocator;

    var proxmox_client = try proxmox.Client.init(.{
        .allocator = allocator,
        .host = "localhost",
        .port = 8006,
        .token = "test-token",
    });
    defer proxmox_client.deinit();

    var container_manager = try cri.ContainerManager.init(allocator, &proxmox_client);
    defer container_manager.deinit();

    var pod_manager = try cri.PodManager.init(allocator, &container_manager);
    defer pod_manager.deinit();

    const container_spec = cri.ContainerSpec{
        .name = "test-container",
        .image = "ubuntu:20.04",
        .command = &[_][]const u8{"bash"},
        .args = &[_][]const u8{},
        .env = &[_]cri.EnvVar{},
    };

    const pod_spec = cri.PodSpec{
        .name = "test-pod",
        .namespace = "default",
        .containers = &[_]cri.ContainerSpec{container_spec},
    };

    const pod = try pod_manager.createPod(pod_spec);
    defer pod.deinit();

    try testing.expect(pod.id.len > 0);
    try testing.expect(pod.name.len > 0);
    try testing.expect(pod.status == .pending);
    try testing.expect(pod.containers.len == 1);
}

test "error handling" {
    const allocator = testing.allocator;
    const test_file = "error.log";

    const file = try std.fs.cwd().createFile(test_file, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(test_file) catch {};
    }

    var log = try logger.Logger.init(allocator, .debug, file.writer());

    // Test configuration error
    const err = error.ConfigNotFound;
    try testing.expectError(err, loadNonExistentConfig());
}

fn loadNonExistentConfig() !void {
    return error.ConfigNotFound;
} 