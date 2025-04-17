const std = @import("std");
const testing = std.testing;
const types = @import("types");
const logger = @import("logger");
const error_lib = @import("error");
const config = @import("config");
const proxmox = @import("proxmox");
const GrpcRuntimeService = @import("runtime_service").GrpcRuntimeService;
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
    @cInclude("runtime_service.grpc.pb.h");
});
const cri = @import("../src/cri.zig");

/// Тестовий менеджер подів
const TestPodManager = struct {
    allocator: std.mem.Allocator,
    pods: std.ArrayList(types.Pod),

    pub fn init(allocator: std.mem.Allocator) TestPodManager {
        return .{
            .allocator = allocator,
            .pods = std.ArrayList(types.Pod).init(allocator),
        };
    }

    pub fn deinit(self: *TestPodManager) void {
        for (self.pods.items) |pod| {
            pod.deinit(self.allocator);
        }
        self.pods.deinit();
    }

    pub fn createPod(self: *TestPodManager, spec: types.PodSpec) !types.Pod {
        const pod = types.Pod{
            .id = try std.fmt.allocPrint(self.allocator, "pod-{d}", .{self.pods.items.len}),
            .metadata = spec.metadata,
            .state = .Created,
            .created_at = std.time.timestamp(),
            .labels = spec.labels,
            .annotations = spec.annotations,
        };
        try self.pods.append(pod);
        return pod;
    }

    pub fn deletePod(self: *TestPodManager, id: []const u8) !void {
        const index = for (self.pods.items, 0..) |pod, i| {
            if (std.mem.eql(u8, pod.id, id)) break i;
        } else return error_lib.PodNotFound;
        
        _ = self.pods.orderedRemove(index);
    }

    pub fn getPod(self: *TestPodManager, id: []const u8) !?types.Pod {
        for (self.pods.items) |pod| {
            if (std.mem.eql(u8, pod.id, id)) return pod;
        }
        return null;
    }

    pub fn listPods(self: *TestPodManager) ![]types.Pod {
        return try self.pods.toOwnedSlice();
    }
};

/// Тестовий менеджер контейнерів
const TestContainerManager = struct {
    allocator: std.mem.Allocator,
    containers: std.ArrayList(types.Container),

    pub fn init(allocator: std.mem.Allocator) TestContainerManager {
        return .{
            .allocator = allocator,
            .containers = std.ArrayList(types.Container).init(allocator),
        };
    }

    pub fn deinit(self: *TestContainerManager) void {
        for (self.containers.items) |container| {
            container.deinit(self.allocator);
        }
        self.containers.deinit();
    }

    pub fn createContainer(self: *TestContainerManager, spec: types.ContainerSpec) !types.Container {
        const container = types.Container{
            .id = try std.fmt.allocPrint(self.allocator, "container-{d}", .{self.containers.items.len}),
            .pod_id = "test-pod",
            .metadata = spec.metadata,
            .image = spec.image,
            .state = .Created,
            .created_at = std.time.timestamp(),
            .labels = spec.labels,
            .annotations = spec.annotations,
        };
        try self.containers.append(container);
        return container;
    }

    pub fn deleteContainer(self: *TestContainerManager, id: []const u8) !void {
        const index = for (self.containers.items, 0..) |container, i| {
            if (std.mem.eql(u8, container.id, id)) break i;
        } else return error_lib.ContainerNotFound;
        
        _ = self.containers.orderedRemove(index);
    }

    pub fn getContainer(self: *TestContainerManager, id: []const u8) !?types.Container {
        for (self.containers.items) |container| {
            if (std.mem.eql(u8, container.id, id)) return container;
        }
        return null;
    }

    pub fn listContainers(self: *TestContainerManager) ![]types.Container {
        return try self.containers.toOwnedSlice();
    }
};

/// Тестовий CRI сервіс
const TestService = struct {
    allocator: std.mem.Allocator,
    pod_manager: TestPodManager,
    container_manager: TestContainerManager,

    pub fn init(allocator: std.mem.Allocator) TestService {
        return .{
            .allocator = allocator,
            .pod_manager = TestPodManager.init(allocator),
            .container_manager = TestContainerManager.init(allocator),
        };
    }

    pub fn deinit(self: *TestService) void {
        self.pod_manager.deinit();
        self.container_manager.deinit();
    }
};

test "RuntimeService - create pod" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестовий запит
    const request = try allocator.create(grpc.CreatePodRequest);
    defer allocator.destroy(request);

    request.* = .{
        .config = .{
            .metadata = .{
                .name = "test-pod",
                .namespace = "default",
                .uid = "test-uid",
                .attempt = 0,
            },
            .labels = null,
            .annotations = null,
        },
    };

    // Викликаємо обробник
    const response = try runtime_service.createPodHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо результат
    try testing.expect(response.pod_sandbox_id != null);
    try testing.expect(response.pod_sandbox_id.len > 0);

    // Перевіряємо, що под був створений
    const pod = try test_service.pod_manager.getPod(response.pod_sandbox_id);
    try testing.expect(pod != null);
    try testing.expectEqualStrings("test-pod", pod.?.metadata.name);
}

test "RuntimeService - delete pod" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестовий под
    const pod_spec = types.PodSpec{
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
            .uid = "test-uid",
            .attempt = 0,
        },
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    const pod = try test_service.pod_manager.createPod(pod_spec);

    // Створюємо тестовий запит на видалення
    const request = try allocator.create(grpc.DeletePodRequest);
    defer allocator.destroy(request);

    request.* = .{
        .pod_sandbox_id = pod.id,
    };

    // Викликаємо обробник
    const response = try runtime_service.deletePodHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо, що под був видалений
    const deleted_pod = try test_service.pod_manager.getPod(pod.id);
    try testing.expect(deleted_pod == null);
}

test "RuntimeService - list pods" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестові поди
    const pod_specs = [_]types.PodSpec{
        .{
            .metadata = .{
                .name = "test-pod-1",
                .namespace = "default",
                .uid = "test-uid-1",
                .attempt = 0,
            },
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
        .{
            .metadata = .{
                .name = "test-pod-2",
                .namespace = "default",
                .uid = "test-uid-2",
                .attempt = 0,
            },
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
    };

    for (pod_specs) |spec| {
        _ = try test_service.pod_manager.createPod(spec);
    }

    // Створюємо тестовий запит
    const request = try allocator.create(grpc.ListPodRequest);
    defer allocator.destroy(request);

    request.* = .{
        .filter = null,
    };

    // Викликаємо обробник
    const response = try runtime_service.listPodsHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо результат
    try testing.expectEqual(@as(usize, 2), response.items.len);
}

test "RuntimeService - create container" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестовий запит
    const request = try allocator.create(grpc.CreateContainerRequest);
    defer allocator.destroy(request);

    request.* = .{
        .pod_sandbox_id = "test-pod",
        .config = .{
            .metadata = .{
                .name = "test-container",
                .attempt = 0,
            },
            .image = .{
                .image = "test-image",
            },
            .command = null,
            .args = null,
            .working_dir = null,
            .envs = null,
            .mounts = null,
            .labels = null,
            .annotations = null,
        },
        .sandbox_config = null,
    };

    // Викликаємо обробник
    const response = try runtime_service.createContainerHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо результат
    try testing.expect(response.container_id != null);
    try testing.expect(response.container_id.len > 0);

    // Перевіряємо, що контейнер був створений
    const container = try test_service.container_manager.getContainer(response.container_id);
    try testing.expect(container != null);
    try testing.expectEqualStrings("test-container", container.?.metadata.name);
}

test "RuntimeService - delete container" {
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

    // Створюємо тестовий запит на видалення
    const request = try allocator.create(grpc.DeleteContainerRequest);
    defer allocator.destroy(request);

    request.* = .{
        .container_id = container.id,
    };

    // Викликаємо обробник
    const response = try runtime_service.deleteContainerHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо, що контейнер був видалений
    const deleted_container = try test_service.container_manager.getContainer(container.id);
    try testing.expect(deleted_container == null);
}

test "RuntimeService - list containers" {
    var allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    var runtime_service = try grpc.RuntimeService.init(allocator, &test_service);
    defer runtime_service.deinit();

    // Створюємо тестові контейнери
    const container_specs = [_]types.ContainerSpec{
        .{
            .metadata = .{
                .name = "test-container-1",
                .namespace = "default",
                .uid = "test-uid-1",
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
        },
        .{
            .metadata = .{
                .name = "test-container-2",
                .namespace = "default",
                .uid = "test-uid-2",
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
        },
    };

    for (container_specs) |spec| {
        _ = try test_service.container_manager.createContainer(spec);
    }

    // Створюємо тестовий запит
    const request = try allocator.create(grpc.ListContainersRequest);
    defer allocator.destroy(request);

    request.* = .{
        .filter = null,
    };

    // Викликаємо обробник
    const response = try runtime_service.listContainersHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо результат
    try testing.expectEqual(@as(usize, 2), response.containers.len);
}

test "RuntimeService - start container" {
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

    // Створюємо тестовий запит на запуск
    const request = try allocator.create(grpc.StartContainerRequest);
    defer allocator.destroy(request);

    request.* = .{
        .container_id = container.id,
    };

    // Викликаємо обробник
    const response = try runtime_service.startContainerHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо, що контейнер був запущений
    const started_container = try test_service.container_manager.getContainer(container.id);
    try testing.expect(started_container != null);
    try testing.expectEqual(types.ContainerState.Running, started_container.?.state);
}

test "RuntimeService - stop container" {
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

    // Запускаємо контейнер
    try test_service.container_manager.startContainer(container.id);

    // Створюємо тестовий запит на зупинку
    const request = try allocator.create(grpc.StopContainerRequest);
    defer allocator.destroy(request);

    request.* = .{
        .container_id = container.id,
        .timeout = 0,
    };

    // Викликаємо обробник
    const response = try runtime_service.stopContainerHandler(request);
    defer allocator.destroy(response);

    // Перевіряємо, що контейнер був зупинений
    const stopped_container = try test_service.container_manager.getContainer(container.id);
    try testing.expect(stopped_container != null);
    try testing.expectEqual(types.ContainerState.Stopped, stopped_container.?.state);
}

test "gRPC - create container" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер на тестовому порту
    const address = "localhost:50051";
    try server.start(address);
    defer server.shutdown();

    // Створюємо gRPC клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестовий запит
    var request = grpc.CreateContainerRequest{
        .pod_sandbox_id = "test-pod",
        .config = .{
            .metadata = .{
                .name = "test-container",
                .attempt = 0,
            },
            .image = .{
                .image = "ubuntu:latest",
            },
            .command = &[_][]const u8{"echo", "hello"},
            .args = null,
            .working_dir = "/",
            .env_vars = null,
            .mounts = null,
            .devices = null,
            .labels = null,
            .annotations = null,
            .log_path = "",
            .stdin = false,
            .stdin_once = false,
            .tty = false,
        },
        .sandbox_config = null,
    };

    // Викликаємо gRPC метод
    var response = try client.CreateContainer(&request);
    defer response.deinit();

    // Перевіряємо результат
    try testing.expect(response.containerId.len > 0);
}

test "gRPC - start container" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50052";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестовий контейнер
    const container_spec = types.ContainerSpec{
        .metadata = .{
            .name = "test-container",
            .attempt = 0,
        },
        .image = "ubuntu:latest",
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    const container = try test_service.container_manager.createContainer(container_spec);

    // Створюємо запит на старт
    var request = grpc.StartContainerRequest{
        .container_id = container.id,
    };

    // Викликаємо gRPC метод
    var response = try client.StartContainer(&request);
    defer response.deinit();

    // Перевіряємо стан контейнера
    const started_container = try test_service.container_manager.getContainer(container.id);
    try testing.expect(started_container.?.state == .Running);
}

test "gRPC - stop container" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50053";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо та запускаємо тестовий контейнер
    const container_spec = types.ContainerSpec{
        .metadata = .{
            .name = "test-container",
            .attempt = 0,
        },
        .image = "ubuntu:latest",
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    var container = try test_service.container_manager.createContainer(container_spec);
    container.state = .Running;

    // Створюємо запит на зупинку
    var request = grpc.StopContainerRequest{
        .container_id = container.id,
        .timeout = 30,
    };

    // Викликаємо gRPC метод
    var response = try client.StopContainer(&request);
    defer response.deinit();

    // Перевіряємо стан контейнера
    const stopped_container = try test_service.container_manager.getContainer(container.id);
    try testing.expect(stopped_container.?.state == .Stopped);
}

test "gRPC - list containers" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50054";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестові контейнери
    const container_specs = [_]types.ContainerSpec{
        .{
            .metadata = .{
                .name = "test-container-1",
                .attempt = 0,
            },
            .image = "ubuntu:latest",
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
        .{
            .metadata = .{
                .name = "test-container-2",
                .attempt = 0,
            },
            .image = "nginx:latest",
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
    };

    for (container_specs) |spec| {
        _ = try test_service.container_manager.createContainer(spec);
    }

    // Створюємо запит на список контейнерів
    var request = grpc.ListContainersRequest{
        .filter = null,
    };

    // Викликаємо gRPC метод
    var response = try client.ListContainers(&request);
    defer response.deinit();

    // Перевіряємо результат
    try testing.expectEqual(response.containers.len, container_specs.len);
}

test "gRPC - create pod" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер на тестовому порту
    const address = "localhost:50055";
    try server.start(address);
    defer server.shutdown();

    // Створюємо gRPC клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестовий запит
    var request = grpc.CreatePodRequest{
        .config = .{
            .metadata = .{
                .name = "test-pod",
                .namespace = "default",
                .uid = "test-uid",
                .attempt = 0,
            },
            .labels = null,
            .annotations = null,
        },
    };

    // Викликаємо gRPC метод
    var response = try client.CreatePod(&request);
    defer response.deinit();

    // Перевіряємо результат
    try testing.expect(response.pod_sandbox_id.len > 0);

    // Перевіряємо, що под був створений
    const pod = try test_service.pod_manager.getPod(response.pod_sandbox_id);
    try testing.expect(pod != null);
    try testing.expectEqualStrings("test-pod", pod.?.metadata.name);
}

test "gRPC - delete pod" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50056";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестовий под
    const pod_spec = types.PodSpec{
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
            .uid = "test-uid",
            .attempt = 0,
        },
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    const pod = try test_service.pod_manager.createPod(pod_spec);

    // Створюємо запит на видалення
    var request = grpc.DeletePodRequest{
        .pod_sandbox_id = pod.id,
    };

    // Викликаємо gRPC метод
    var response = try client.DeletePod(&request);
    defer response.deinit();

    // Перевіряємо, що под був видалений
    const deleted_pod = try test_service.pod_manager.getPod(pod.id);
    try testing.expect(deleted_pod == null);
}

test "gRPC - list pods" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50057";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестові поди
    const pod_specs = [_]types.PodSpec{
        .{
            .metadata = .{
                .name = "test-pod-1",
                .namespace = "default",
                .uid = "test-uid-1",
                .attempt = 0,
            },
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
        .{
            .metadata = .{
                .name = "test-pod-2",
                .namespace = "default",
                .uid = "test-uid-2",
                .attempt = 0,
            },
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        },
    };

    for (pod_specs) |spec| {
        _ = try test_service.pod_manager.createPod(spec);
    }

    // Створюємо запит на список подів
    var request = grpc.ListPodRequest{
        .filter = null,
    };

    // Викликаємо gRPC метод
    var response = try client.ListPods(&request);
    defer response.deinit();

    // Перевіряємо результат
    try testing.expectEqual(response.items.len, pod_specs.len);
}

test "gRPC - start pod" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50058";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо тестовий под
    const pod_spec = types.PodSpec{
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
            .uid = "test-uid",
            .attempt = 0,
        },
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    const pod = try test_service.pod_manager.createPod(pod_spec);

    // Створюємо запит на запуск
    var request = grpc.StartPodRequest{
        .pod_sandbox_id = pod.id,
    };

    // Викликаємо gRPC метод
    var response = try client.StartPod(&request);
    defer response.deinit();

    // Перевіряємо стан пода
    const started_pod = try test_service.pod_manager.getPod(pod.id);
    try testing.expect(started_pod.?.state == .Running);
}

test "gRPC - stop pod" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50059";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Створюємо та запускаємо тестовий под
    const pod_spec = types.PodSpec{
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
            .uid = "test-uid",
            .attempt = 0,
        },
        .labels = std.StringHashMap([]const u8).init(allocator),
        .annotations = std.StringHashMap([]const u8).init(allocator),
    };
    var pod = try test_service.pod_manager.createPod(pod_spec);
    try test_service.pod_manager.startPod(pod.id);

    // Створюємо запит на зупинку
    var request = grpc.StopPodRequest{
        .pod_sandbox_id = pod.id,
    };

    // Викликаємо gRPC метод
    var response = try client.StopPod(&request);
    defer response.deinit();

    // Перевіряємо стан пода
    const stopped_pod = try test_service.pod_manager.getPod(pod.id);
    try testing.expect(stopped_pod.?.state == .Stopped);
}

test "gRPC - error handling - invalid pod ID" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50060";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Тестуємо видалення неіснуючого пода
    var delete_request = grpc.DeletePodRequest{
        .pod_sandbox_id = "non-existent-pod",
    };
    try testing.expectError(error.PodNotFound, client.DeletePod(&delete_request));

    // Тестуємо запуск неіснуючого пода
    var start_request = grpc.StartPodRequest{
        .pod_sandbox_id = "non-existent-pod",
    };
    try testing.expectError(error.PodNotFound, client.StartPod(&start_request));

    // Тестуємо зупинку неіснуючого пода
    var stop_request = grpc.StopPodRequest{
        .pod_sandbox_id = "non-existent-pod",
    };
    try testing.expectError(error.PodNotFound, client.StopPod(&stop_request));
}

test "gRPC - error handling - invalid container ID" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50061";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

    // Тестуємо видалення неіснуючого контейнера
    var delete_request = grpc.DeleteContainerRequest{
        .container_id = "non-existent-container",
    };
    try testing.expectError(error.ContainerNotFound, client.DeleteContainer(&delete_request));

    // Тестуємо запуск неіснуючого контейнера
    var start_request = grpc.StartContainerRequest{
        .container_id = "non-existent-container",
    };
    try testing.expectError(error.ContainerNotFound, client.StartContainer(&start_request));

    // Тестуємо зупинку неіснуючого контейнера
    var stop_request = grpc.StopContainerRequest{
        .container_id = "non-existent-container",
        .timeout = 0,
    };
    try testing.expectError(error.ContainerNotFound, client.StopContainer(&stop_request));
}

test "gRPC - error handling - invalid container state" {
    const allocator = testing.allocator;
    var test_service = TestService.init(allocator);
    defer test_service.deinit();

    // Створюємо gRPC сервер
    var server = try grpc.Server.init(allocator);
    defer server.deinit();

    // Реєструємо GrpcRuntimeService
    var runtime_service = try GrpcRuntimeService.init(allocator, &test_service);
    try server.registerService(runtime_service.getService());

    // Запускаємо сервер
    const address = "localhost:50062";
    try server.start(address);
    defer server.shutdown();

    // Створюємо клієнт
    var channel = try grpc.Channel.init(address);
    defer channel.deinit();

    var client = try grpc.RuntimeServiceClient.init(&channel);
    defer client.deinit();

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
    var container = try test_service.container_manager.createContainer(container_spec);

    // Тестуємо видалення запущеного контейнера
    container.state = .Running;
    var delete_request = grpc.DeleteContainerRequest{
        .container_id = container.id,
    };
    try testing.expectError(error.InvalidContainerState, client.DeleteContainer(&delete_request));

    // Тестуємо повторний запуск запущеного контейнера
    var start_request = grpc.StartContainerRequest{
        .container_id = container.id,
    };
    try testing.expectError(error.ContainerAlreadyExists, client.StartContainer(&start_request));

    // Тестуємо зупинку зупиненого контейнера
    container.state = .Stopped;
    var stop_request = grpc.StopContainerRequest{
        .container_id = container.id,
        .timeout = 0,
    };
    try testing.expectError(error.InvalidContainerState, client.StopContainer(&stop_request));
} 