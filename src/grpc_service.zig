const std = @import("std");
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
    @cInclude("runtime_service.grpc.pb.h");
});
const types = @import("types");
const Allocator = std.mem.Allocator;

pub const RuntimeService = struct {
    allocator: Allocator,
    service: *grpc.RuntimeService,
    pod_manager: *types.PodManager,
    container_manager: *types.ContainerManager,

    pub fn init(allocator: Allocator, pod_manager: *types.PodManager, container_manager: *types.ContainerManager) !RuntimeService {
        return RuntimeService{
            .allocator = allocator,
            .service = undefined,
            .pod_manager = pod_manager,
            .container_manager = container_manager,
        };
    }

    pub fn deinit(_: *RuntimeService) void {
        // Cleanup gRPC service
    }

    pub fn start(_: *RuntimeService) !void {
        // Initialize gRPC service
        // Register service methods
    }

    // CRI Service Methods
    pub fn createPod(self: *RuntimeService, request: *grpc.CreatePodRequest) !*grpc.CreatePodResponse {
        const spec = try self.requestToPodSpec(request);
        defer spec.deinit(self.allocator);

        const pod = try self.pod_manager.createPod(spec);
        defer pod.deinit(self.allocator);

        const response = try self.allocator.create(grpc.CreatePodResponse);
        response.* = .{
            .pod_id = try self.allocator.dupe(u8, pod.id),
        };

        return response;
    }

    pub fn deletePod(self: *RuntimeService, request: *grpc.DeletePodRequest) !*grpc.DeletePodResponse {
        try self.pod_manager.deletePod(request.pod_id);

        const response = try self.allocator.create(grpc.DeletePodResponse);
        response.* = .{};

        return response;
    }

    pub fn listPods(self: *RuntimeService, _: *grpc.ListPodsRequest) !*grpc.ListPodsResponse {
        const pods = try self.pod_manager.listPods();
        defer self.allocator.free(pods);

        const response = try self.allocator.create(grpc.ListPodsResponse);
        response.* = .{
            .pods = try self.podsToGRPC(pods),
        };

        return response;
    }

    pub fn createContainer(self: *RuntimeService, request: *grpc.CreateContainerRequest) !*grpc.CreateContainerResponse {
        const spec = try self.requestToContainerSpec(request);
        defer spec.deinit(self.allocator);

        const container = try self.container_manager.createContainer(spec);
        defer container.deinit(self.allocator);

        const response = try self.allocator.create(grpc.CreateContainerResponse);
        response.* = .{
            .container_id = try self.allocator.dupe(u8, container.id),
        };

        return response;
    }

    pub fn deleteContainer(self: *RuntimeService, request: *grpc.DeleteContainerRequest) !*grpc.DeleteContainerResponse {
        try self.container_manager.deleteContainer(request.container_id);

        const response = try self.allocator.create(grpc.DeleteContainerResponse);
        response.* = .{};

        return response;
    }

    pub fn listContainers(self: *RuntimeService, _: *grpc.ListContainersRequest) !*grpc.ListContainersResponse {
        const containers = try self.container_manager.listContainers();
        defer self.allocator.free(containers);

        const response = try self.allocator.create(grpc.ListContainersResponse);
        response.* = .{
            .containers = try self.containersToGRPC(containers),
        };

        return response;
    }

    // Helper functions
    fn requestToPodSpec(self: *RuntimeService, request: *grpc.CreatePodRequest) !types.PodSpec {
        const containers = try self.allocator.alloc(types.ContainerSpec, request.containers.len);
        errdefer self.allocator.free(containers);

        for (request.containers, 0..) |container, i| {
            containers[i] = try self.requestToContainerSpec(container);
        }

        return types.PodSpec{
            .name = try self.allocator.dupe(u8, request.name),
            .namespace = try self.allocator.dupe(u8, request.namespace),
            .containers = containers,
        };
    }

    fn requestToContainerSpec(self: *RuntimeService, request: *grpc.CreateContainerRequest) !types.ContainerSpec {
        const command = try self.allocator.alloc([]const u8, request.command.len);
        errdefer self.allocator.free(command);
        for (request.command, 0..) |cmd, i| {
            command[i] = try self.allocator.dupe(u8, cmd);
        }

        const args = try self.allocator.alloc([]const u8, request.args.len);
        errdefer self.allocator.free(args);
        for (request.args, 0..) |arg, i| {
            args[i] = try self.allocator.dupe(u8, arg);
        }

        const env = try self.allocator.alloc(types.EnvVar, request.env.len);
        errdefer self.allocator.free(env);
        for (request.env, 0..) |e, i| {
            env[i] = .{
                .name = try self.allocator.dupe(u8, e.name),
                .value = try self.allocator.dupe(u8, e.value),
            };
        }

        return types.ContainerSpec{
            .name = try self.allocator.dupe(u8, request.name),
            .image = try self.allocator.dupe(u8, request.image),
            .command = command,
            .args = args,
            .env = env,
        };
    }

    fn podsToGRPC(self: *RuntimeService, pods: []types.Pod) ![]grpc.Pod {
        const grpc_pods = try self.allocator.alloc(grpc.Pod, pods.len);
        errdefer self.allocator.free(grpc_pods);

        for (pods, 0..) |pod, i| {
            grpc_pods[i] = .{
                .id = try self.allocator.dupe(u8, pod.id),
                .name = try self.allocator.dupe(u8, pod.name),
                .namespace = try self.allocator.dupe(u8, pod.namespace),
                .status = @intFromEnum(pod.status),
                .containers = try self.containersToGRPC(pod.containers),
            };
        }

        return grpc_pods;
    }

    fn containersToGRPC(self: *RuntimeService, containers: []types.Container) ![]grpc.Container {
        const grpc_containers = try self.allocator.alloc(grpc.Container, containers.len);
        errdefer self.allocator.free(grpc_containers);

        for (containers, 0..) |container, i| {
            grpc_containers[i] = .{
                .id = try self.allocator.dupe(u8, container.id),
                .name = try self.allocator.dupe(u8, container.name),
                .status = @intFromEnum(container.status),
                .spec = try self.containerSpecToGRPC(container.spec),
            };
        }

        return grpc_containers;
    }

    fn containerSpecToGRPC(self: *RuntimeService, spec: types.ContainerSpec) !grpc.ContainerSpec {
        return grpc.ContainerSpec{
            .name = try self.allocator.dupe(u8, spec.name),
            .image = try self.allocator.dupe(u8, spec.image),
            .command = try self.allocator.dupe(u8, spec.command),
            .args = try self.allocator.dupe(u8, spec.args),
            .env = try self.envVarsToGRPC(spec.env),
        };
    }

    fn envVarsToGRPC(self: *RuntimeService, env_vars: []types.EnvVar) ![]grpc.EnvVar {
        const grpc_env_vars = try self.allocator.alloc(grpc.EnvVar, env_vars.len);
        errdefer self.allocator.free(grpc_env_vars);

        for (env_vars, 0..) |env_var, i| {
            grpc_env_vars[i] = .{
                .name = try self.allocator.dupe(u8, env_var.name),
                .value = try self.allocator.dupe(u8, env_var.value),
            };
        }

        return grpc_env_vars;
    }
};
