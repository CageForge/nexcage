const std = @import("std");
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
    @cInclude("grpc/grpc_security.h");
    @cInclude("grpc/slice.h");
    @cInclude("grpc/support/alloc.h");
    @cInclude("grpc/support/log.h");
    @cInclude("runtime_service.grpc.pb.h");
    @cInclude("runtime_service.pb.h");
});
const types = @import("types");
const cri = @import("cri");
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.grpc_runtime);

/// Структура сервісу Runtime
pub const GrpcRuntimeService = struct {
    allocator: Allocator,
    server: ?*grpc.grpc_server,
    type_converter: TypeConverter,
    pod_manager: *cri.PodManager,
    container_manager: *cri.ContainerManager,

    const Self = @This();

    pub fn init(allocator: Allocator, pod_manager: *cri.PodManager, container_manager: *cri.ContainerManager) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .server = null,
            .type_converter = .{ .allocator = allocator },
            .pod_manager = pod_manager,
            .container_manager = container_manager,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.server) |server| {
            grpc.grpc_server_destroy(server);
        }
        self.allocator.destroy(self);
    }

    /// Запускає gRPC сервер на вказаній адресі та порту
    pub fn startServer(self: *Self, address: []const u8, port: u16) !void {
        if (self.server != null) {
            return error.ServerAlreadyStarted;
        }

        // Створюємо сервер
        const server = grpc.grpc_server_create(null, null) orelse {
            logger.err("Failed to create gRPC server", .{});
            return error.ServerCreationFailed;
        };
        errdefer grpc.grpc_server_destroy(server);

        // Створюємо незахищені облікові дані
        const credentials = grpc.grpc_server_credentials_create_insecure() orelse {
            logger.err("Failed to create server credentials", .{});
            return error.CredentialsCreationFailed;
        };
        errdefer grpc.grpc_server_credentials_release(credentials);

        // Додаємо порт прослуховування
        const bind_address = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ address, port });
        defer self.allocator.free(bind_address);

        const bound_port = grpc.grpc_server_add_http2_port(server, bind_address.ptr, credentials);
        if (bound_port <= 0) {
            logger.err("Failed to bind to port {d}", .{port});
            return error.PortBindingFailed;
        }

        // Запускаємо сервер
        grpc.grpc_server_start(server);
        self.server = server;

        logger.info("gRPC server started on {s}:{d}", .{ address, port });
    }

    /// Зупиняє gRPC сервер
    pub fn stopServer(self: *Self) void {
        if (self.server) |server| {
            grpc.grpc_server_shutdown_and_notify(server, null, null);
            grpc.grpc_server_destroy(server);
            self.server = null;
            logger.info("gRPC server stopped", .{});
        }
    }

    /// Реєструє метод на сервері
    pub fn registerMethod(self: *Self, method_name: []const u8, handler: GrpcHandler) !void {
        if (self.server == null) {
            return error.ServerNotInitialized;
        }

        if (method_name.len == 0) {
            return error.InvalidMethodName;
        }

        const result = grpc.grpc_server_register_method(
            self.server.?,
            method_name.ptr,
            null,
            grpc.GRPC_SRM_PAYLOAD_READ_INITIAL_BYTEBUFFER,
            0
        );

        if (result == 0) {
            logger.err("Failed to register method: {s}", .{method_name});
            return error.MethodRegistrationFailed;
        }

        logger.info("Registered method: {s}", .{method_name});
    }
};

pub const GrpcError = error{
    MethodRegistrationFailed,
    InvalidMethodName,
    ServerNotInitialized,
    HandlerNotFound,
    DeserializationError,
    SerializationError,
    InvalidPayload,
    ConversionError,
    InvalidPodConfig,
    InvalidContainerConfig,
    ResourceNotFound,
    InvalidMetadata,
    MemoryAllocationError,
    ContainerNotFound,
    ContainerAlreadyExists,
    InvalidContainerState,
    PodNotFound,
    ServerAlreadyStarted,
    ServerCreationFailed,
    CredentialsCreationFailed,
    PortBindingFailed,
};

/// Тип для обробника gRPC методу
pub const GrpcHandler = *const fn (*GrpcRuntimeService, []const u8) callconv(.C) grpc.grpc_status_code;

/// Структура для зберігання інформації про метод
pub const MethodInfo = struct {
    handler: GrpcHandler,
    request_type: type,
    response_type: type,
};

/// Структура для конвертації типів
const TypeConverter = struct {
    allocator: Allocator,

    const Self = @This();

    /// Конвертує CRI Pod конфігурацію в нашу внутрішню
    pub fn podConfigToPodSpec(self: *Self, config: *const grpc.PodSandboxConfig) !types.PodSpec {
        if (config.metadata == null) {
            logger.err("Pod config missing metadata", .{});
            return error.InvalidPodConfig;
        }

        // Конвертуємо метадані
        const metadata = try self.metadataToInternal(config.metadata.?);
        errdefer metadata.deinit(self.allocator);

        // Конвертуємо налаштування мережі
        var network_config: ?types.NetworkConfig = null;
        if (config.network != null) {
            network_config = try self.networkConfigToInternal(config.network.?);
        }
        errdefer if (network_config) |nc| nc.deinit(self.allocator);

        // Конвертуємо налаштування Linux
        var linux_config: ?types.LinuxConfig = null;
        if (config.linux != null) {
            linux_config = try self.linuxConfigToInternal(config.linux.?);
        }
        errdefer if (linux_config) |lc| lc.deinit(self.allocator);

        return types.PodSpec{
            .metadata = metadata,
            .network = network_config,
            .linux = linux_config,
            .annotations = try self.mapToInternal(config.annotations),
            .labels = try self.mapToInternal(config.labels),
        };
    }

    /// Конвертує CRI Container конфігурацію в нашу внутрішню
    pub fn containerConfigToContainerSpec(self: *Self, config: *const grpc.ContainerConfig) !types.ContainerSpec {
        if (config.metadata == null) {
            logger.err("Container config missing metadata", .{});
            return error.InvalidContainerConfig;
        }

        // Конвертуємо метадані
        const metadata = try self.metadataToInternal(config.metadata.?);
        errdefer metadata.deinit(self.allocator);

        // Конвертуємо налаштування образу
        const image = try self.imageConfigToInternal(config.image.?);
        errdefer image.deinit(self.allocator);

        // Конвертуємо змінні середовища
        var env_vars = std.ArrayList(types.EnvVar).init(self.allocator);
        errdefer {
            for (env_vars.items) |env| env.deinit(self.allocator);
            env_vars.deinit();
        }

        if (config.envs) |envs| {
            for (envs) |env| {
                try env_vars.append(try self.envVarToInternal(env));
            }
        }

        // Конвертуємо точки монтування
        var mounts = std.ArrayList(types.Mount).init(self.allocator);
        errdefer {
            for (mounts.items) |mount| mount.deinit(self.allocator);
            mounts.deinit();
        }

        if (config.mounts) |mount_list| {
            for (mount_list) |mount| {
                try mounts.append(try self.mountToInternal(mount));
            }
        }

        return types.ContainerSpec{
            .metadata = metadata,
            .image = image,
            .command = try self.stringArrayToInternal(config.command),
            .args = try self.stringArrayToInternal(config.args),
            .working_dir = if (config.working_dir) |dir| try self.allocator.dupe(u8, dir) else null,
            .env = env_vars.toOwnedSlice(),
            .mounts = mounts.toOwnedSlice(),
            .labels = try self.mapToInternal(config.labels),
            .annotations = try self.mapToInternal(config.annotations),
        };
    }

    /// Конвертує внутрішній Pod в CRI Pod
    pub fn podToGrpc(self: *Self, pod: types.Pod) !*grpc.Pod {
        const result = try self.allocator.create(grpc.Pod);
        errdefer self.allocator.destroy(result);

        result.* = .{
            .id = try self.allocator.dupe(u8, pod.id),
            .metadata = try self.metadataToGrpc(pod.metadata),
            .state = try self.podStateToGrpc(pod.state),
            .created_at = pod.created_at,
            .labels = try self.mapToGrpc(pod.labels),
            .annotations = try self.mapToGrpc(pod.annotations),
        };

        return result;
    }

    /// Конвертує внутрішній Container в CRI Container
    pub fn containerToGrpc(self: *Self, container: types.Container) !*grpc.Container {
        const result = try self.allocator.create(grpc.Container);
        errdefer self.allocator.destroy(result);

        result.* = .{
            .id = try self.allocator.dupe(u8, container.id),
            .pod_id = try self.allocator.dupe(u8, container.pod_id),
            .metadata = try self.metadataToGrpc(container.metadata),
            .image = try self.imageToGrpc(container.image),
            .image_ref = try self.allocator.dupe(u8, container.image_ref),
            .state = try self.containerStateToGrpc(container.state),
            .created_at = container.created_at,
            .labels = try self.mapToGrpc(container.labels),
            .annotations = try self.mapToGrpc(container.annotations),
        };

        return result;
    }

    /// Допоміжні функції конвертації
    fn metadataToInternal(self: *Self, metadata: *const grpc.Metadata) !types.Metadata {
        return types.Metadata{
            .name = try self.allocator.dupe(u8, metadata.name orelse ""),
            .uid = try self.allocator.dupe(u8, metadata.uid orelse ""),
            .namespace = try self.allocator.dupe(u8, metadata.namespace orelse "default"),
            .attempt = metadata.attempt orelse 0,
        };
    }

    fn metadataToGrpc(self: *Self, metadata: types.Metadata) !*grpc.Metadata {
        const result = try self.allocator.create(grpc.Metadata);
        errdefer self.allocator.destroy(result);

        result.* = .{
            .name = try self.allocator.dupe(u8, metadata.name),
            .uid = try self.allocator.dupe(u8, metadata.uid),
            .namespace = try self.allocator.dupe(u8, metadata.namespace),
            .attempt = metadata.attempt,
        };

        return result;
    }

    fn mapToInternal(self: *Self, map: ?*const grpc.StringMap) !std.StringHashMap([]const u8) {
        var result = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var it = result.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            result.deinit();
        }

        if (map) |m| {
            for (m.items) |item| {
                const key = try self.allocator.dupe(u8, item.key);
                errdefer self.allocator.free(key);
                const value = try self.allocator.dupe(u8, item.value);
                try result.put(key, value);
            }
        }

        return result;
    }

    fn mapToGrpc(self: *Self, map: std.StringHashMap([]const u8)) !*grpc.StringMap {
        const result = try self.allocator.create(grpc.StringMap);
        errdefer self.allocator.destroy(result);

        var items = std.ArrayList(grpc.StringMapItem).init(self.allocator);
        errdefer items.deinit();

        var it = map.iterator();
        while (it.next()) |entry| {
            try items.append(.{
                .key = try self.allocator.dupe(u8, entry.key_ptr.*),
                .value = try self.allocator.dupe(u8, entry.value_ptr.*),
            });
        }

        result.* = .{
            .items = items.toOwnedSlice(),
        };

        return result;
    }

    fn stringArrayToInternal(self: *Self, arr: ?[]const [*:0]const u8) ![][]const u8 {
        if (arr == null) return &[_][]const u8{};

        var result = try std.ArrayList([]const u8).initCapacity(self.allocator, arr.?.len);
        errdefer {
            for (result.items) |item| self.allocator.free(item);
            result.deinit();
        }

        for (arr.?) |str| {
            const dup = try self.allocator.dupe(u8, std.mem.span(str));
            try result.append(dup);
        }

        return result.toOwnedSlice();
    }
};

pub const RuntimeService = struct {
    allocator: Allocator,
    service: *grpc.RuntimeService,
    cri_service: *cri.Service,
    server: ?*grpc.grpc_server,
    server_credentials: *grpc.grpc_server_credentials_t,
    method_handlers: std.StringHashMap(MethodInfo),

    const Self = @This();

    pub fn init(allocator: Allocator, cri_service: *cri.Service) !Self {
        var self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.service = undefined;
        self.cri_service = cri_service;
        self.server = null;
        self.server_credentials = grpc.grpc_insecure_server_credentials_create();
        self.method_handlers = std.StringHashMap(MethodInfo).init(allocator);
        
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.server) |server| {
            grpc.grpc_server_destroy(server);
        }
        grpc.grpc_server_credentials_release(self.server_credentials);
        self.method_handlers.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *Self) !void {
        // Створюємо gRPC сервер
        self.server = grpc.grpc_server_create(null, null);
        if (self.server == null) {
            logger.err("Failed to create gRPC server", .{});
            return error.ServerCreationFailed;
        }

        // Налаштовуємо обробник запитів
        _ = grpc.grpc_server_register_completion_queue(self.server.?, null, null);

        // Реєструємо методи сервісу
        try self.registerMethods();
        
        // Запускаємо сервер
        const port = try self.startServer();
        logger.info("gRPC server started on port {}", .{port});

        // Запускаємо цикл обробки запитів
        try self.startRequestProcessing();
    }

    fn startServer(self: *Self) !u16 {
        if (self.server == null) return error.ServerNotInitialized;

        const address = "0.0.0.0:0";
        const bound_port = grpc.grpc_server_add_insecure_http2_port(self.server.?, address.ptr);
        if (bound_port <= 0) {
            logger.err("Failed to bind server port", .{});
            return error.ServerBindFailed;
        }

        grpc.grpc_server_start(self.server.?);
        return @intCast(bound_port);
    }

    fn registerMethods(self: *Self) !void {
        // Pod management
        try self.registerMethod("CreatePod", createPodHandler, grpc.CreatePodRequest, grpc.CreatePodResponse);
        try self.registerMethod("DeletePod", deletePodHandler, grpc.DeletePodRequest, grpc.DeletePodResponse);
        try self.registerMethod("ListPods", listPodsHandler, grpc.ListPodsRequest, grpc.ListPodsResponse);
        try self.registerMethod("StartPod", startPodHandler, grpc.StartPodRequest, grpc.StartPodResponse);
        try self.registerMethod("StopPod", stopPodHandler, grpc.StopPodRequest, grpc.StopPodResponse);

        // Container management
        try self.registerMethod("CreateContainer", createContainerHandler, grpc.CreateContainerRequest, grpc.CreateContainerResponse);
        try self.registerMethod("DeleteContainer", deleteContainerHandler, grpc.DeleteContainerRequest, grpc.DeleteContainerResponse);
        try self.registerMethod("ListContainers", listContainersHandler, grpc.ListContainersRequest, grpc.ListContainersResponse);
        try self.registerMethod("StartContainer", startContainerHandler, grpc.StartContainerRequest, grpc.StartContainerResponse);
        try self.registerMethod("StopContainer", stopContainerHandler, grpc.StopContainerRequest, grpc.StopContainerResponse);
    }

    fn registerMethod(self: *Self, name: []const u8, handler: GrpcHandler, comptime RequestType: type, comptime ResponseType: type) !void {
        if (self.server == null) return error.ServerNotInitialized;

        // Створюємо інформацію про метод
        const method_info = MethodInfo{
            .handler = handler,
            .request_type = RequestType,
            .response_type = ResponseType,
        };

        // Реєструємо метод в gRPC сервері
        const result = grpc.grpc_server_register_method(
            self.server.?,
            name.ptr,
            "runtime.v1alpha2.RuntimeService",
            grpc.GRPC_SRM_PAYLOAD_READ_INITIAL_BYTEBUFFER,
            0
        );

        if (result == null) {
            logger.err("Failed to register method: {s}", .{name});
            return error.MethodRegistrationFailed;
        }

        // Зберігаємо інформацію про метод
        try self.method_handlers.put(name, method_info);
        logger.debug("Registered method: {s}", .{name});
    }

    /// Знаходить обробник для вказаного методу
    pub fn findHandler(self: *Self, method_name: []const u8) !MethodInfo {
        return self.method_handlers.get(method_name) orelse {
            logger.err("Handler not found for method: {s}", .{method_name});
            return error.HandlerNotFound;
        };
    }

    /// Обробники для управління подами
    fn createPodHandler(self: *Self, request: *grpc.CreatePodRequest) !*grpc.CreatePodResponse {
        logger.info("Creating pod with name: {s}", .{request.config.?.metadata.?.name orelse "unknown"});

        // Конвертуємо конфігурацію в наш формат
        const pod_spec = try self.requestToPodSpec(request);
        errdefer pod_spec.deinit(self.allocator);

        // Створюємо под
        const pod = try self.cri_service.pod_manager.createPod(pod_spec);
        errdefer pod.deinit(self.allocator);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.CreatePodResponse);
        errdefer self.allocator.destroy(response);

        response.* = .{
            .pod_sandbox_id = try self.allocator.dupe(u8, pod.id),
        };

        logger.info("Successfully created pod with ID: {s}", .{pod.id});
        return response;
    }

    fn deletePodHandler(self: *Self, request: *grpc.DeletePodRequest) !*grpc.DeletePodResponse {
        logger.info("Deleting pod with ID: {s}", .{request.pod_sandbox_id});

        // Перевіряємо наявність пода
        const pod = try self.cri_service.pod_manager.getPod(request.pod_sandbox_id);
        if (pod == null) {
            logger.err("Pod not found: {s}", .{request.pod_sandbox_id});
            return error.PodNotFound;
        }

        // Видаляємо под
        try self.cri_service.pod_manager.deletePod(request.pod_sandbox_id);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.DeletePodResponse);
        response.* = .{};

        logger.info("Successfully deleted pod with ID: {s}", .{request.pod_sandbox_id});
        return response;
    }

    fn startPodHandler(self: *Self, request: *grpc.StartPodRequest) !*grpc.StartPodResponse {
        logger.info("Starting pod with ID: {s}", .{request.pod_sandbox_id});

        // Перевіряємо наявність пода
        const pod = try self.cri_service.pod_manager.getPod(request.pod_sandbox_id);
        if (pod == null) {
            logger.err("Pod not found: {s}", .{request.pod_sandbox_id});
            return error.PodNotFound;
        }

        // Запускаємо под
        try self.cri_service.pod_manager.startPod(request.pod_sandbox_id);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.StartPodResponse);
        response.* = .{};

        logger.info("Successfully started pod with ID: {s}", .{request.pod_sandbox_id});
        return response;
    }

    fn stopPodHandler(self: *Self, request: *grpc.StopPodRequest) !*grpc.StopPodResponse {
        logger.info("Stopping pod with ID: {s}", .{request.pod_sandbox_id});

        // Перевіряємо наявність пода
        const pod = try self.cri_service.pod_manager.getPod(request.pod_sandbox_id);
        if (pod == null) {
            logger.err("Pod not found: {s}", .{request.pod_sandbox_id});
            return error.PodNotFound;
        }

        // Зупиняємо под
        try self.cri_service.pod_manager.stopPod(request.pod_sandbox_id);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.StopPodResponse);
        response.* = .{};

        logger.info("Successfully stopped pod with ID: {s}", .{request.pod_sandbox_id});
        return response;
    }

    fn listPodsHandler(self: *Self, request: *grpc.ListPodRequest) !*grpc.ListPodResponse {
        logger.info("Listing pods with filter: {?}", .{request.filter});

        // Отримуємо список подів
        var pods = try self.cri_service.pod_manager.listPods();
        defer {
            for (pods) |pod| pod.deinit(self.allocator);
            self.allocator.free(pods);
        }

        // Фільтруємо поди якщо є фільтр
        if (request.filter != null) {
            pods = try self.filterPods(pods, request.filter.?);
        }

        // Конвертуємо поди в формат CRI
        const grpc_pods = try self.podsToGRPC(pods);
        errdefer {
            for (grpc_pods) |pod| pod.deinit();
            self.allocator.free(grpc_pods);
        }

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.ListPodResponse);
        errdefer self.allocator.destroy(response);

        response.* = .{
            .items = grpc_pods,
        };

        logger.info("Successfully listed {} pods", .{grpc_pods.len});
        return response;
    }

    /// Допоміжна функція для фільтрації подів
    fn filterPods(self: *Self, pods: []types.Pod, filter: *const grpc.PodFilter) ![]types.Pod {
        var filtered = std.ArrayList(types.Pod).init(self.allocator);
        errdefer filtered.deinit();

        for (pods) |pod| {
            // Фільтруємо по ID
            if (filter.id != null and !std.mem.eql(u8, pod.id, filter.id.?)) {
                continue;
            }

            // Фільтруємо по стану
            if (filter.state != null and pod.state != filter.state.?) {
                continue;
            }

            // Фільтруємо по лейблах
            if (filter.label_selector != null) {
                var matches = true;
                var it = filter.label_selector.?.iterator();
                while (it.next()) |entry| {
                    if (!pod.labels.contains(entry.key_ptr.*) or
                        !std.mem.eql(u8, pod.labels.get(entry.key_ptr.*).?, entry.value_ptr.*)) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
            }

            try filtered.append(pod);
        }

        return filtered.toOwnedSlice();
    }

    /// Обробники для управління контейнерами
    fn createContainerHandler(self: *Self, request: *grpc.CreateContainerRequest) !*grpc.CreateContainerResponse {
        logger.info("Creating container in pod: {s}", .{request.pod_sandbox_id});

        // Перевіряємо наявність пода
        const pod = try self.cri_service.pod_manager.getPod(request.pod_sandbox_id);
        if (pod == null) {
            logger.err("Pod not found: {s}", .{request.pod_sandbox_id});
            return error.PodNotFound;
        }

        // Конвертуємо конфігурацію в наш формат
        const container_spec = try self.requestToContainerSpec(request);
        errdefer container_spec.deinit(self.allocator);

        // Створюємо контейнер
        const container = try self.cri_service.container_manager.createContainer(container_spec);
        errdefer container.deinit(self.allocator);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.CreateContainerResponse);
        errdefer self.allocator.destroy(response);

        response.* = .{
            .container_id = try self.allocator.dupe(u8, container.id),
        };

        logger.info("Successfully created container with ID: {s}", .{container.id});
        return response;
    }

    fn deleteContainerHandler(self: *Self, request: *grpc.DeleteContainerRequest) !*grpc.DeleteContainerResponse {
        logger.info("Deleting container with ID: {s}", .{request.container_id});

        // Перевіряємо наявність контейнера
        const container = try self.cri_service.container_manager.getContainer(request.container_id);
        if (container == null) {
            logger.err("Container not found: {s}", .{request.container_id});
            return error.ContainerNotFound;
        }

        // Перевіряємо стан контейнера
        if (container.?.state == .Running) {
            logger.err("Cannot delete running container: {s}", .{request.container_id});
            return error.InvalidContainerState;
        }

        // Видаляємо контейнер
        try self.cri_service.container_manager.deleteContainer(request.container_id);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.DeleteContainerResponse);
        response.* = .{};

        logger.info("Successfully deleted container with ID: {s}", .{request.container_id});
        return response;
    }

    fn startContainerHandler(self: *Self, request: *grpc.StartContainerRequest) !*grpc.StartContainerResponse {
        logger.info("Starting container with ID: {s}", .{request.container_id});

        // Перевіряємо наявність контейнера
        const container = try self.cri_service.container_manager.getContainer(request.container_id);
        if (container == null) {
            logger.err("Container not found: {s}", .{request.container_id});
            return error.ContainerNotFound;
        }

        // Перевіряємо стан контейнера
        if (container.?.state == .Running) {
            logger.warn("Container already running: {s}", .{request.container_id});
            return error.ContainerAlreadyExists;
        }

        // Запускаємо контейнер
        try self.cri_service.container_manager.startContainer(request.container_id);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.StartContainerResponse);
        response.* = .{};

        logger.info("Successfully started container with ID: {s}", .{request.container_id});
        return response;
    }

    fn stopContainerHandler(self: *Self, request: *grpc.StopContainerRequest) !*grpc.StopContainerResponse {
        logger.info("Stopping container with ID: {s}", .{request.container_id});

        // Перевіряємо наявність контейнера
        const container = try self.cri_service.container_manager.getContainer(request.container_id);
        if (container == null) {
            logger.err("Container not found: {s}", .{request.container_id});
            return error.ContainerNotFound;
        }

        // Перевіряємо стан контейнера
        if (container.?.state != .Running) {
            logger.warn("Container not running: {s}", .{request.container_id});
            return error.InvalidContainerState;
        }

        // Зупиняємо контейнер
        try self.cri_service.container_manager.stopContainer(request.container_id, request.timeout);

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.StopContainerResponse);
        response.* = .{};

        logger.info("Successfully stopped container with ID: {s}", .{request.container_id});
        return response;
    }

    fn listContainersHandler(self: *Self, request: *grpc.ListContainersRequest) !*grpc.ListContainersResponse {
        logger.info("Listing containers with filter: {?}", .{request.filter});

        // Отримуємо список контейнерів
        var containers = try self.cri_service.container_manager.listContainers();
        defer {
            for (containers) |container| container.deinit(self.allocator);
            self.allocator.free(containers);
        }

        // Фільтруємо контейнери якщо є фільтр
        if (request.filter != null) {
            containers = try self.filterContainers(containers, request.filter.?);
        }

        // Конвертуємо контейнери в формат CRI
        const grpc_containers = try self.containersToGRPC(containers);
        errdefer {
            for (grpc_containers) |container| container.deinit();
            self.allocator.free(grpc_containers);
        }

        // Формуємо відповідь
        const response = try self.allocator.create(grpc.ListContainersResponse);
        errdefer self.allocator.destroy(response);

        response.* = .{
            .containers = grpc_containers,
        };

        logger.info("Successfully listed {} containers", .{grpc_containers.len});
        return response;
    }

    /// Допоміжна функція для фільтрації контейнерів
    fn filterContainers(self: *Self, containers: []types.Container, filter: *const grpc.ContainerFilter) ![]types.Container {
        var filtered = std.ArrayList(types.Container).init(self.allocator);
        errdefer filtered.deinit();

        for (containers) |container| {
            // Фільтруємо по ID
            if (filter.id != null and !std.mem.eql(u8, container.id, filter.id.?)) {
                continue;
            }

            // Фільтруємо по ID пода
            if (filter.pod_sandbox_id != null and !std.mem.eql(u8, container.pod_id, filter.pod_sandbox_id.?)) {
                continue;
            }

            // Фільтруємо по стану
            if (filter.state != null and container.state != filter.state.?) {
                continue;
            }

            // Фільтруємо по лейблах
            if (filter.label_selector != null) {
                var matches = true;
                var it = filter.label_selector.?.iterator();
                while (it.next()) |entry| {
                    if (!container.labels.contains(entry.key_ptr.*) or
                        !std.mem.eql(u8, container.labels.get(entry.key_ptr.*).?, entry.value_ptr.*)) {
                        matches = false;
                        break;
                    }
                }
                if (!matches) continue;
            }

            try filtered.append(container);
        }

        return filtered.toOwnedSlice();
    }

    // Helper functions for converting between CRI and internal types
    fn requestToPodSpec(self: *Self, request: *grpc.CreatePodRequest) !types.PodSpec {
        var converter = TypeConverter{ .allocator = self.allocator };
        return try converter.podConfigToPodSpec(request.config);
    }

    fn requestToContainerSpec(self: *Self, request: *grpc.CreateContainerRequest) !types.ContainerSpec {
        var converter = TypeConverter{ .allocator = self.allocator };
        return try converter.containerConfigToContainerSpec(request.config);
    }

    fn podsToGRPC(self: *Self, pods: []types.Pod) ![]grpc.Pod {
        var converter = TypeConverter{ .allocator = self.allocator };
        var result = try std.ArrayList(grpc.Pod).initCapacity(self.allocator, pods.len);
        errdefer result.deinit();

        for (pods) |pod| {
            const grpc_pod = try converter.podToGrpc(pod);
            try result.append(grpc_pod.*);
            self.allocator.destroy(grpc_pod);
        }

        return result.toOwnedSlice();
    }

    fn containersToGRPC(self: *Self, containers: []types.Container) ![]grpc.Container {
        var converter = TypeConverter{ .allocator = self.allocator };
        var result = try std.ArrayList(grpc.Container).initCapacity(self.allocator, containers.len);
        errdefer result.deinit();

        for (containers) |container| {
            const grpc_container = try converter.containerToGrpc(container);
            try result.append(grpc_container.*);
            self.allocator.destroy(grpc_container);
        }

        return result.toOwnedSlice();
    }

    /// Обробляє вхідний gRPC запит
    pub fn handleRequest(self: *Self, method_name: []const u8, payload: []const u8) ![]const u8 {
        // Знаходимо обробник для методу
        const method_info = try self.findHandler(method_name);
        
        // Десеріалізуємо запит
        const request = try self.deserializeRequest(method_info.request_type, payload);
        defer request.deinit();

        // Викликаємо обробник
        const response = try self.callHandler(method_info.handler, request);
        defer response.deinit();

        // Серіалізуємо відповідь
        return try self.serializeResponse(method_info.response_type, response);
    }

    /// Десеріалізує запит з байтів у відповідний тип
    fn deserializeRequest(self: *Self, comptime T: type, payload: []const u8) !*T {
        if (payload.len == 0) {
            logger.err("Empty payload received", .{});
            return error.InvalidPayload;
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();

        const request = try arena.allocator.create(T);
        errdefer arena.allocator.destroy(request);

        // Використовуємо protobuf для десеріалізації
        if (!grpc.pb_decode(payload.ptr, payload.len, request)) {
            logger.err("Failed to deserialize request of type {s}", .{@typeName(T)});
            return error.DeserializationError;
        }

        return request;
    }

    /// Серіалізує відповідь у байти
    fn serializeResponse(self: *Self, comptime T: type, response: *T) ![]const u8 {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();

        // Визначаємо розмір буфера для серіалізації
        const buffer_size = grpc.pb_get_encoded_size(response);
        var buffer = try arena.allocator.alloc(u8, buffer_size);
        errdefer arena.allocator.free(buffer);

        // Серіалізуємо відповідь
        const encoded_size = grpc.pb_encode(response, buffer.ptr, buffer.len);
        if (encoded_size <= 0) {
            logger.err("Failed to serialize response of type {s}", .{@typeName(T)});
            return error.SerializationError;
        }

        return buffer[0..@intCast(encoded_size)];
    }

    /// Викликає обробник методу
    fn callHandler(self: *Self, handler: GrpcHandler, request: anytype) !@TypeOf(request).ResponseType {
        const status = handler(self, request);
        
        if (status != grpc.GRPC_STATUS_OK) {
            logger.err("Handler failed with status: {}", .{status});
            return switch (status) {
                grpc.GRPC_STATUS_INVALID_ARGUMENT => error.InvalidArgument,
                grpc.GRPC_STATUS_NOT_FOUND => error.NotFound,
                grpc.GRPC_STATUS_ALREADY_EXISTS => error.AlreadyExists,
                grpc.GRPC_STATUS_PERMISSION_DENIED => error.PermissionDenied,
                grpc.GRPC_STATUS_INTERNAL => error.Internal,
                else => error.Unknown,
            };
        }

        return request.response;
    }

    /// Запускає цикл обробки запитів
    fn startRequestProcessing(self: *Self) !void {
        while (true) {
            const next_event = grpc.grpc_completion_queue_next(
                self.server.?.completion_queue,
                grpc.gpr_inf_future(grpc.GPR_CLOCK_MONOTONIC),
                null
            );

            if (next_event.type == grpc.GRPC_OP_COMPLETE) {
                const call = @as(*grpc.grpc_call_t, @ptrCast(next_event.tag));
                const method_name = grpc.grpc_call_get_method(call);
                
                // Отримуємо payload
                var payload_buffer: ?*grpc.grpc_byte_buffer = null;
                const status = grpc.grpc_call_recv_message(call, &payload_buffer);
                
                if (status == grpc.GRPC_STATUS_OK and payload_buffer != null) {
                    // Конвертуємо буфер у слайс
                    const payload = try self.bufferToSlice(payload_buffer.?);
                    defer self.allocator.free(payload);

                    // Обробляємо запит
                    const response = try self.handleRequest(method_name, payload);
                    defer self.allocator.free(response);

                    // Відправляємо відповідь
                    try self.sendResponse(call, response);
                }

                grpc.grpc_call_unref(call);
            }
        }
    }

    /// Конвертує gRPC буфер у слайс байтів
    fn bufferToSlice(self: *Self, buffer: *grpc.grpc_byte_buffer) ![]const u8 {
        var reader = grpc.grpc_byte_buffer_reader{
            .buffer = buffer,
            .current_slice = null,
            .current_index = 0,
        };
        if (!grpc.grpc_byte_buffer_reader_init(&reader, buffer)) {
            return error.BufferReadError;
        }
        defer grpc.grpc_byte_buffer_reader_destroy(&reader);

        const slice = grpc.grpc_byte_buffer_reader_readall(&reader);
        defer grpc.grpc_slice_unref(slice);

        const data = grpc.grpc_slice_start_ptr(slice);
        const len = grpc.grpc_slice_length(slice);

        const result = try self.allocator.alloc(u8, len);
        @memcpy(result, data[0..len]);
        return result;
    }

    /// Відправляє відповідь клієнту
    pub fn sendResponse(self: *Self, call: *grpc.grpc_call_t, message: []const u8) !void {
        const metadata = grpc.grpc_metadata_array_create();
        defer grpc.grpc_metadata_array_destroy(metadata);

        const details = if (message.len > 0) 
            @as([*c]const u8, @ptrCast(message.ptr))
        else 
            null;

        const status = grpc.grpc_call_send_status_from_server(
            call,
            grpc.GRPC_STATUS_OK,
            details,
            metadata,
            grpc.GRPC_STATUS_OK_DETAILS_SIZE
        );

        if (status != grpc.GRPC_STATUS_OK) {
            return error.SendResponseError;
        }
    }
}; 