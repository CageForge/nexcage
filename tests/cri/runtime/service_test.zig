const std = @import("std");
const testing = std.testing;
const RuntimeService = @import("../../../src/cri/runtime/service.zig").RuntimeService;
const MockClient = @import("../mocks/client.zig").MockClient;
const types = @import("../../../src/types.zig");

fn setupTestClient() !*MockClient {
    return MockClient.init(testing.allocator);
}

test "RuntimeService - basic lifecycle operations" {
    const test_allocator = testing.allocator;
    var client = try setupTestClient();
    defer client.deinit();

    var runtime = RuntimeService.init(test_allocator, client);
    defer runtime.deinit();

    // Test Version
    const version = try runtime.Version("v1alpha2");
    defer {
        test_allocator.free(version.version);
        test_allocator.free(version.runtime_name);
        test_allocator.free(version.runtime_version);
        test_allocator.free(version.runtime_api_version);
    }

    try testing.expectEqualStrings("0.1.0", version.version);
    try testing.expectEqualStrings("nexcage", version.runtime_name);
    try testing.expectEqualStrings("v1alpha2", version.runtime_api_version);

    // Create container config
    const container_config = types.ContainerConfig{
        .metadata = .{
            .name = "test-container",
            .attempt = 1,
        },
        .image = .{
            .image = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst",
        },
        .linux = .{
            .resources = .{
                .memory_limit_bytes = 512 * 1024 * 1024, // 512MB
                .cpu_shares = 1024,
            },
            .security_context = .{
                .privileged = false,
            },
        },
        .mounts = &[_]types.Mount{},
    };

    // Test CreateContainer
    const container = try runtime.CreateContainer("test-pod", container_config);
    defer {
        test_allocator.free(container.id);
        test_allocator.free(container.name);
    }

    try testing.expect(container.status == .created);

    // Test ListContainers
    const containers = try runtime.ListContainers(null);
    defer {
        for (containers) |c| {
            test_allocator.free(c.id);
            test_allocator.free(c.name);
            if (c.image_ref) |img| {
                test_allocator.free(img);
            }
            c.labels.deinit();
            c.annotations.deinit();
        }
        test_allocator.free(containers);
    }

    try testing.expect(containers.len > 0);

    // Test ContainerStatus
    const status = try runtime.ContainerStatus(container.id);
    defer {
        test_allocator.free(status.id);
        if (status.image.image) |img| {
            test_allocator.free(img);
        }
        status.labels.deinit();
        status.annotations.deinit();
        for (status.mounts) |mount| {
            test_allocator.free(mount.container_path);
            test_allocator.free(mount.host_path);
        }
        test_allocator.free(status.mounts);
        status.network.ip_addresses.deinit();
        status.network.interfaces.deinit();
    }

    try testing.expectEqualStrings(container.id, status.id);
    try testing.expect(status.status == .created);

    // Test StartContainer
    try runtime.StartContainer(container.id);
    const running_status = try runtime.ContainerStatus(container.id);
    defer {
        test_allocator.free(running_status.id);
        if (running_status.image.image) |img| {
            test_allocator.free(img);
        }
        running_status.labels.deinit();
        running_status.annotations.deinit();
        for (running_status.mounts) |mount| {
            test_allocator.free(mount.container_path);
            test_allocator.free(mount.host_path);
        }
        test_allocator.free(running_status.mounts);
        running_status.network.ip_addresses.deinit();
        running_status.network.interfaces.deinit();
    }
    try testing.expect(running_status.status == .running);

    // Test UpdateContainerResources
    try runtime.UpdateContainerResources(container.id, .{
        .memory_limit_bytes = 1024 * 1024 * 1024, // 1GB
        .cpu_shares = 2048,
    });

    // Test ExecSync
    const exec_result = try runtime.ExecSync(container.id, &[_][]const u8{ "echo", "test" }, 10);
    defer {
        test_allocator.free(exec_result.stdout);
        test_allocator.free(exec_result.stderr);
    }

    try testing.expectEqualStrings("test\n", exec_result.stdout);
    try testing.expect(exec_result.exit_code == 0);

    // Test StopContainer
    try runtime.StopContainer(container.id, 30);
    const stopped_status = try runtime.ContainerStatus(container.id);
    defer {
        test_allocator.free(stopped_status.id);
        if (stopped_status.image.image) |img| {
            test_allocator.free(img);
        }
        stopped_status.labels.deinit();
        stopped_status.annotations.deinit();
        for (stopped_status.mounts) |mount| {
            test_allocator.free(mount.container_path);
            test_allocator.free(mount.host_path);
        }
        test_allocator.free(stopped_status.mounts);
        stopped_status.network.ip_addresses.deinit();
        stopped_status.network.interfaces.deinit();
    }
    try testing.expect(stopped_status.status == .exited);

    // Test RemoveContainer
    try runtime.RemoveContainer(container.id);
    try testing.expectError(error.ContainerNotFound, runtime.ContainerStatus(container.id));
}

test "RuntimeService - error handling" {
    const test_allocator = testing.allocator;
    var client = try setupTestClient();
    defer client.deinit();

    var runtime = RuntimeService.init(test_allocator, client);
    defer runtime.deinit();

    // Test invalid container ID
    try testing.expectError(error.InvalidContainerId, runtime.ContainerStatus("invalid-id"));
    try testing.expectError(error.InvalidContainerId, runtime.StartContainer("invalid-id"));
    try testing.expectError(error.InvalidContainerId, runtime.StopContainer("invalid-id", 30));
    try testing.expectError(error.InvalidContainerId, runtime.RemoveContainer("invalid-id"));

    // Test non-existent container
    try testing.expectError(error.ContainerNotFound, runtime.ContainerStatus("999999"));
    try testing.expectError(error.ContainerNotFound, runtime.StartContainer("999999"));
    try testing.expectError(error.ContainerNotFound, runtime.StopContainer("999999", 30));
    try testing.expectError(error.ContainerNotFound, runtime.RemoveContainer("999999"));
}
