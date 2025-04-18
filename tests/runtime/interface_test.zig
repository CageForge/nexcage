const std = @import("std");
const testing = std.testing;
const runtime = @import("runtime");
const types = @import("types");

fn mockCreate(self: *runtime.RuntimeInterface, config: types.ContainerConfig) runtime.RuntimeError!void {
    _ = self;
    _ = config;
}

fn mockStart(self: *runtime.RuntimeInterface, id: []const u8) runtime.RuntimeError!void {
    _ = self;
    _ = id;
}

fn mockStop(self: *runtime.RuntimeInterface, id: []const u8) runtime.RuntimeError!void {
    _ = self;
    _ = id;
}

fn mockDelete(self: *runtime.RuntimeInterface, id: []const u8) runtime.RuntimeError!void {
    _ = self;
    _ = id;
}

fn mockState(self: *runtime.RuntimeInterface, id: []const u8) runtime.RuntimeError!runtime.RuntimeInterface.State {
    _ = self;
    _ = id;
    return .created;
}

fn mockUpdateResources(self: *runtime.RuntimeInterface, id: []const u8, resources: types.Resources) runtime.RuntimeError!void {
    _ = self;
    _ = id;
    _ = resources;
}

fn mockStats(self: *runtime.RuntimeInterface, id: []const u8) runtime.RuntimeError!types.ResourceStats {
    _ = self;
    _ = id;
    return types.ResourceStats{};
}

test "RuntimeInterface basic functionality" {
    const allocator = testing.allocator;

    const config = runtime.RuntimeInterface.Config{
        .runtime_type = .oci,
        .root_dir = "/tmp/test-root",
        .state_dir = "/tmp/test-state",
    };

    const lifecycle = runtime.RuntimeInterface.Lifecycle{
        .createFn = mockCreate,
        .startFn = mockStart,
        .stopFn = mockStop,
        .deleteFn = mockDelete,
        .stateFn = mockState,
    };

    const resources = runtime.RuntimeInterface.Resources{
        .updateFn = mockUpdateResources,
        .statsFn = mockStats,
    };

    var rt = runtime.RuntimeInterface.init(allocator, config, lifecycle, resources);

    // Test container creation
    try rt.create(.{});

    // Test container lifecycle
    try rt.start("test-container");
    try rt.stop("test-container");
    const state = try rt.state("test-container");
    try testing.expectEqual(runtime.RuntimeInterface.State.created, state);
    try rt.delete("test-container");

    // Test resources
    try rt.updateResources("test-container", .{});
    _ = try rt.stats("test-container");
}

test "RuntimeInterface metadata" {
    const allocator = testing.allocator;

    var metadata = try runtime.RuntimeInterface.Metadata.init(allocator, "test-id", "test-name");
    defer metadata.deinit(allocator);

    try testing.expectEqualStrings("test-id", metadata.id);
    try testing.expectEqualStrings("test-name", metadata.name);
    
    // Test labels
    try metadata.labels.put("key1", "value1");
    try metadata.labels.put("key2", "value2");
    try testing.expectEqual(@as(usize, 2), metadata.labels.count());
    
    // Test annotations
    try metadata.annotations.put("anno1", "value1");
    try metadata.annotations.put("anno2", "value2");
    try testing.expectEqual(@as(usize, 2), metadata.annotations.count());
}

test "RuntimeInterface error handling" {
    const allocator = testing.allocator;

    const config = runtime.RuntimeInterface.Config{
        .runtime_type = .oci,
        .root_dir = "/tmp/test-root",
        .state_dir = "/tmp/test-state",
    };

    const failingCreate = struct {
        fn create(self: *runtime.RuntimeInterface, config: types.ContainerConfig) runtime.RuntimeError!void {
            _ = self;
            _ = config;
            return error.CreationError;
        }
    }.create;

    const lifecycle = runtime.RuntimeInterface.Lifecycle{
        .createFn = failingCreate,
        .startFn = mockStart,
        .stopFn = mockStop,
        .deleteFn = mockDelete,
        .stateFn = mockState,
    };

    const resources = runtime.RuntimeInterface.Resources{
        .updateFn = mockUpdateResources,
        .statsFn = mockStats,
    };

    var rt = runtime.RuntimeInterface.init(allocator, config, lifecycle, resources);

    // Test error handling
    try testing.expectError(error.CreationError, rt.create(.{}));
} 