const std = @import("std");
const testing = std.testing;
const container = @import("proxmox/container.zig");
const Thread = std.Thread;

test "Parallel container creation" {
    const allocator = testing.allocator;
    const num_containers = 5;

    var containers = try allocator.alloc(container.Config, num_containers);
    defer allocator.free(containers);

    var threads = try allocator.alloc(Thread, num_containers);
    defer allocator.free(threads);

    // Create containers in parallel
    for (containers, 0..) |*c, i| {
        threads[i] = try Thread.spawn(.{}, struct {
            fn createContainer(alloc: std.mem.Allocator, config: *container.Config) !void {
                config.* = try container.Config.init(alloc);
                try config.setName(try std.fmt.allocPrint(alloc, "test-container-{d}", .{i}));
                try config.setMemoryLimit(1024 * 1024 * 1024); // 1GB
                try config.setCPUCount(1);
            }
        }.createContainer, .{ allocator, c });
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Verify all containers were created successfully
    for (containers) |c| {
        try testing.expect(c.getName().len > 0);
        try testing.expect(c.getMemoryLimit() == 1024 * 1024 * 1024);
        try testing.expect(c.getCPUCount() == 1);
    }
}

test "Resource contention" {
    const allocator = testing.allocator;
    const num_containers = 3;
    const total_memory = 2 * 1024 * 1024 * 1024; // 2GB

    var containers = try allocator.alloc(container.Config, num_containers);
    defer allocator.free(containers);

    // Try to allocate more memory than available
    for (containers) |*c| {
        c.* = try container.Config.init(allocator);
        try c.setMemoryLimit(total_memory / 2); // Each container tries to use 1GB
    }

    // Verify that resource allocation fails appropriately
    var success_count: usize = 0;
    for (containers) |c| {
        if (c.allocateResources()) {
            success_count += 1;
        }
    }

    // Only one container should be able to allocate resources
    try testing.expect(success_count <= 1);
}

test "Concurrent operations" {
    const allocator = testing.allocator;
    var container_config = try container.Config.init(allocator);
    defer container_config.deinit();

    const num_operations = 10;
    var operations = try allocator.alloc(Thread, num_operations);
    defer allocator.free(operations);

    // Perform multiple operations concurrently
    for (operations, 0..) |*op, i| {
        op.* = try Thread.spawn(.{}, struct {
            fn performOperation(config: *container.Config, op_type: usize) !void {
                switch (op_type % 3) {
                    0 => try config.setMemoryLimit(512 * 1024 * 1024),
                    1 => try config.setCPUCount(1),
                    2 => try config.setNetworkConfig("eth0", "dhcp"),
                    else => unreachable,
                }
            }
        }.performOperation, .{ &container_config, i });
    }

    // Wait for all operations to complete
    for (operations) |op| {
        op.join();
    }

    // Verify final state
    try testing.expect(container_config.getMemoryLimit() > 0);
    try testing.expect(container_config.getCPUCount() > 0);
    try testing.expect(container_config.getNetworkConfig("eth0").len > 0);
}
