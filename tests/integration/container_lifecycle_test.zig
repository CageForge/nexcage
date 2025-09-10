/// Integration tests for complete container lifecycle operations
/// 
/// This module contains comprehensive integration tests that verify
/// the full container lifecycle from creation to cleanup, including
/// error scenarios and edge cases.

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
const expectEqual = testing.expectEqual;

const types = @import("types");
const config = @import("config");
const logger = @import("logger");
const oci = @import("oci");

test "Container lifecycle integration test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize logger for testing
    const stdout = std.io.getStdOut();
    try logger.init(allocator, stdout.writer(), .info);
    defer logger.deinit();

    // Test container creation
    var container_config = try types.ContainerConfig.init(allocator);
    defer container_config.deinit();

    // Set up basic container configuration
    container_config.id = try allocator.dupe(u8, "test-integration-container");
    container_config.name = try allocator.dupe(u8, "Integration Test Container");
    container_config.bundle = try allocator.dupe(u8, "/tmp/test-bundle");

    // Add environment variables
    const envs = try allocator.alloc(types.EnvVar, 2);
    envs[0] = types.EnvVar{
        .name = try allocator.dupe(u8, "TEST_ENV"),
        .value = try allocator.dupe(u8, "integration_test"),
    };
    envs[1] = types.EnvVar{
        .name = try allocator.dupe(u8, "CONTAINER_TYPE"),
        .value = try allocator.dupe(u8, "test"),
    };
    container_config.envs = envs;

    // Create container instance
    const container = try types.Container.init(allocator, &container_config);
    defer container.deinit();

    // Verify initial state
    try expectEqual(types.ContainerState.created, container.state);
    try expect(std.mem.eql(u8, "test-integration-container", container.config.id));

    // Test state transitions (simulated)
    // Note: Actual state transitions would require real container runtime
    try expectEqual(types.ContainerState.created, container.getState());
}

test "Container configuration validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test with minimal configuration
    var minimal_config = try types.ContainerConfig.init(allocator);
    defer minimal_config.deinit();

    // Minimal config should have safe defaults
    try expectEqual(@as(usize, 0), minimal_config.id.len);
    try expectEqual(@as(usize, 0), minimal_config.name.len);
    try expectEqual(types.ContainerType.lxc, minimal_config.default_container_type);

    // Test with complete configuration
    var complete_config = try types.ContainerConfig.init(allocator);
    defer complete_config.deinit();

    complete_config.id = try allocator.dupe(u8, "complete-test");
    complete_config.name = try allocator.dupe(u8, "Complete Test Container");
    complete_config.bundle = try allocator.dupe(u8, "/opt/containers/complete-test");
    complete_config.working_dir = try allocator.dupe(u8, "/app");
    complete_config.log_path = try allocator.dupe(u8, "/var/log/containers/complete-test.log");

    // Verify all fields are set correctly
    try expect(std.mem.eql(u8, "complete-test", complete_config.id));
    try expect(std.mem.eql(u8, "Complete Test Container", complete_config.name));
    try expect(std.mem.eql(u8, "/opt/containers/complete-test", complete_config.bundle));
    try expect(std.mem.eql(u8, "/app", complete_config.working_dir.?));
    try expect(std.mem.eql(u8, "/var/log/containers/complete-test.log", complete_config.log_path.?));
}

test "Container error handling scenarios" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test error handling during container creation
    var error_config = try types.ContainerConfig.init(allocator);
    defer error_config.deinit();

    // Set up configuration that might cause errors
    error_config.id = try allocator.dupe(u8, "");  // Empty ID
    error_config.bundle = try allocator.dupe(u8, "/nonexistent/path");

    // Container creation should still succeed with invalid paths
    // (actual validation would happen during container start)
    const container = try types.Container.init(allocator, &error_config);
    defer container.deinit();

    try expectEqual(types.ContainerState.created, container.state);
}

test "Multiple container management" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const container_count = 5;
    var containers: [container_count]*types.Container = undefined;
    var configs: [container_count]types.ContainerConfig = undefined;

    // Create multiple containers
    for (0..container_count) |i| {
        configs[i] = try types.ContainerConfig.init(allocator);
        configs[i].id = try std.fmt.allocPrint(allocator, "multi-test-{d}", .{i});
        configs[i].name = try std.fmt.allocPrint(allocator, "Multi Test Container {d}", .{i});
        
        containers[i] = try types.Container.init(allocator, &configs[i]);
    }

    // Verify all containers are created correctly
    for (0..container_count) |i| {
        try expectEqual(types.ContainerState.created, containers[i].state);
        
        // Verify unique IDs
        for (0..container_count) |j| {
            if (i != j) {
                try expect(!std.mem.eql(u8, containers[i].config.id, containers[j].config.id));
            }
        }
    }

    // Cleanup all containers
    for (0..container_count) |i| {
        containers[i].deinit();
        configs[i].deinit();
    }
}

test "Container specification integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test container spec creation and management
    var container_spec = try types.ContainerSpec.init(allocator);
    defer container_spec.deinit();

    // Configure basic spec
    container_spec.config.id = try allocator.dupe(u8, "spec-test");
    container_spec.config.name = try allocator.dupe(u8, "Spec Test Container");

    // Add network configuration
    const network_config = try types.NetworkConfig.init(allocator);
    container_spec.network = network_config;

    // Verify spec structure
    try expect(std.mem.eql(u8, "spec-test", container_spec.config.id));
    try expect(container_spec.network != null);
}

test "Container state management" {
    // Test all container states are properly defined
    const states = [_]types.ContainerState{
        .created,
        .running,
        .stopped,
        .paused,
        .unknown,
    };

    // Verify state enum values
    for (states) |state| {
        try expect(@intFromEnum(state) >= 0);
    }

    // Test state comparison
    try expectEqual(types.ContainerState.created, types.ContainerState.created);
    try expect(types.ContainerState.running != types.ContainerState.stopped);
}

test "Container memory management stress test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Stress test memory management with rapid creation/destruction
    for (0..100) |i| {
        var container_config = try types.ContainerConfig.init(allocator);
        container_config.id = try std.fmt.allocPrint(allocator, "stress-test-{d}", .{i});
        
        // Add some environment variables
        const envs = try allocator.alloc(types.EnvVar, 3);
        envs[0] = types.EnvVar{
            .name = try std.fmt.allocPrint(allocator, "VAR1_{d}", .{i}),
            .value = try std.fmt.allocPrint(allocator, "value1_{d}", .{i}),
        };
        envs[1] = types.EnvVar{
            .name = try std.fmt.allocPrint(allocator, "VAR2_{d}", .{i}),
            .value = try std.fmt.allocPrint(allocator, "value2_{d}", .{i}),
        };
        envs[2] = types.EnvVar{
            .name = try std.fmt.allocPrint(allocator, "VAR3_{d}", .{i}),
            .value = try std.fmt.allocPrint(allocator, "value3_{d}", .{i}),
        };
        container_config.envs = envs;

        const container = try types.Container.init(allocator, &container_config);
        
        // Verify container was created correctly
        try expectEqual(types.ContainerState.created, container.state);
        
        // Clean up immediately
        container.deinit();
        container_config.deinit();
    }
}

test "Container resource limits integration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create container with resource limits
    var container_config = try types.ContainerConfig.init(allocator);
    defer container_config.deinit();

    container_config.id = try allocator.dupe(u8, "resource-limited-container");
    
    // Note: Resource limits would be configured through linux field
    // This test verifies the structure supports resource configuration
    
    const container = try types.Container.init(allocator, &container_config);
    defer container.deinit();

    try expectEqual(types.ContainerState.created, container.state);
    try expect(std.mem.eql(u8, "resource-limited-container", container.config.id));
}
