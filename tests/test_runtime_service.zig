const std = @import("std");
const testing = std.testing;
const types = @import("types");
const logger = @import("logger");
const error_lib = @import("error");
const config = @import("config");
const proxmox = @import("proxmox");
const RuntimeService = @import("runtime_service").RuntimeService;
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