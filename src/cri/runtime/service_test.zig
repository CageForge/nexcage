const std = @import("std");
const testing = std.testing;
const types = @import("../../types.zig");
const RuntimeService = @import("service.zig").RuntimeService;
const RuntimeError = @import("service.zig").RuntimeError;
const grpc = @import("grpc.zig");

test "RuntimeService - error handling - invalid container ID" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Тестуємо видалення неіснуючого контейнера
    const delete_request = try allocator.create(grpc.DeleteContainerRequest);
    defer allocator.destroy(delete_request);
    delete_request.* = .{
        .container_id = "non-existent-container",
    };
    try testing.expectError(error.ContainerNotFound, runtime_service.deleteContainerHandler(delete_request));

    // Тестуємо запуск неіснуючого контейнера
    const start_request = try allocator.create(grpc.StartContainerRequest);
    defer allocator.destroy(start_request);
    start_request.* = .{
        .container_id = "non-existent-container",
    };
    try testing.expectError(error.ContainerNotFound, runtime_service.startContainerHandler(start_request));

    // Тестуємо зупинку неіснуючого контейнера
    const stop_request = try allocator.create(grpc.StopContainerRequest);
    defer allocator.destroy(stop_request);
    stop_request.* = .{
        .container_id = "non-existent-container",
        .timeout = 0,
    };
    try testing.expectError(error.ContainerNotFound, runtime_service.stopContainerHandler(stop_request));
}

test "RuntimeService - error handling - invalid container state" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестовий контейнер
    const container_spec = types.ContainerSpec{
        .metadata = .{
            .name = "test-container",
            .namespace = "default",
            .uid = "test-uid",
            .attempt = 0,
        },
        .image = .{
            .name = "test-image",
            .tag = "latest",
        },
        .command = &[_][]const u8{},
        .args = &[_][]const u8{},
        .working_dir = null,
        .env = &[_]types.EnvVar{},
        .mounts = &[_]types.Mount{},
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    const container = try test_service.container_manager.createContainer(container_spec);

    // Тестуємо зупинку зупиненого контейнера
    const stop_request = try allocator.create(grpc.StopContainerRequest);
    defer allocator.destroy(stop_request);
    stop_request.* = .{
        .container_id = container.id,
        .timeout = 0,
    };
    try testing.expectError(error.InvalidContainerState, runtime_service.stopContainerHandler(stop_request));

    // Запускаємо контейнер
    try test_service.container_manager.startContainer(container.id);

    // Тестуємо запуск запущеного контейнера
    const start_request = try allocator.create(grpc.StartContainerRequest);
    defer allocator.destroy(start_request);
    start_request.* = .{
        .container_id = container.id,
    };
    try testing.expectError(error.InvalidContainerState, runtime_service.startContainerHandler(start_request));

    // Тестуємо видалення запущеного контейнера
    const delete_request = try allocator.create(grpc.DeleteContainerRequest);
    defer allocator.destroy(delete_request);
    delete_request.* = .{
        .container_id = container.id,
    };
    try testing.expectError(error.InvalidContainerState, runtime_service.deleteContainerHandler(delete_request));
}

test "RuntimeService - error handling - invalid configuration" {
    var service = try TestRuntimeService.init(testing.allocator);
    defer service.deinit();

    // Спроба створити контейнер з невалідною конфігурацією
    var invalid_config = types.ContainerConfig{
        .metadata = .{
            .name = "",  // Пусте ім'я
            .attempt = 0,
        },
        .image = .{
            .image = "",  // Пустий образ
        },
        .command = &[_][]const u8{},
        .args = &[_][]const u8{},
        .working_dir = null,
        .envs = &[_]types.KeyValue{},
        .mounts = &[_]types.Mount{},
        .labels = std.StringHashMap([]const u8).init(testing.allocator),
        .annotations = std.StringHashMap([]const u8).init(testing.allocator),
        .linux = .{
            .resources = null,
            .security_context = null,
        },
    };

    try testing.expectError(
        RuntimeError.ConfigurationError,
        service.CreateContainer("test-pod", invalid_config)
    );
}

const TestRuntimeService = struct {
    service: RuntimeService,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !TestRuntimeService {
        var client = try TestProxmoxClient.init(allocator);
        var service = RuntimeService.init(allocator, &client);
        return TestRuntimeService{
            .service = service,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestRuntimeService) void {
        self.service.deinit();
    }
};

const TestProxmoxClient = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !TestProxmoxClient {
        return TestProxmoxClient{
            .allocator = allocator,
        };
    }
};

fn createTestContainerConfig() !types.ContainerConfig {
    return types.ContainerConfig{
        .metadata = .{
            .name = "test-container",
            .attempt = 0,
        },
        .image = .{
            .image = "ubuntu:22.04",
        },
        .command = &[_][]const u8{"echo", "hello"},
        .args = &[_][]const u8{},
        .working_dir = null,
        .envs = &[_]types.KeyValue{},
        .mounts = &[_]types.Mount{},
        .labels = std.StringHashMap([]const u8).init(testing.allocator),
        .annotations = std.StringHashMap([]const u8).init(testing.allocator),
        .linux = .{
            .resources = null,
            .security_context = null,
        },
    };
} 