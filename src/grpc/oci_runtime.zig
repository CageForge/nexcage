const std = @import("std");
const grpc = @cImport({
    @cInclude("grpc/grpc.h");
    @cInclude("grpc/status.h");
    @cInclude("grpc/grpc_security.h");
    @cInclude("grpc/slice.h");
    @cInclude("grpc/support/alloc.h");
    @cInclude("grpc/support/log.h");
    @cInclude("oci_runtime.pb-c.h");
    @cInclude("oci_runtime.grpc-c.h");
});

const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.grpc_oci);

/// Структура сервісу OCI Runtime
pub const OciRuntimeService = struct {
    allocator: Allocator,
    server: ?*grpc.grpc_server,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
            .server = null,
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

        logger.info("OCI Runtime gRPC server started on {s}:{d}", .{ address, port });
    }

    /// Зупиняє gRPC сервер
    pub fn stopServer(self: *Self) void {
        if (self.server) |server| {
            grpc.grpc_server_shutdown_and_notify(server, null, null);
            grpc.grpc_server_destroy(server);
            self.server = null;
            logger.info("OCI Runtime gRPC server stopped", .{});
        }
    }

    /// Реалізація CreateContainer
    pub fn createContainer(self: *Self, request: *const grpc.Oci__CreateContainerRequest) !grpc.Oci__CreateContainerResponse {
        logger.info("Creating container", .{});

        if (request.config == null) {
            logger.err("Container config is null", .{});
            return error.InvalidContainerConfig;
        }

        // TODO: Реалізувати створення контейнера через OCI runtime

        const response = grpc.Oci__CreateContainerResponse{
            .container_id = try self.allocator.dupe(u8, "container-id"),
        };

        return response;
    }

    /// Реалізація DeleteContainer
    pub fn deleteContainer(self: *Self, request: *const grpc.Oci__DeleteContainerRequest) !grpc.Oci__DeleteContainerResponse {
        _ = self;
        if (request.container_id.len == 0) {
            logger.err("Container ID is empty", .{});
            return error.InvalidContainerId;
        }

        // TODO: Реалізувати видалення контейнера через OCI runtime

        return grpc.Oci__DeleteContainerResponse{};
    }

    /// Реалізація StartContainer
    pub fn startContainer(self: *Self, request: *const grpc.Oci__StartContainerRequest) !grpc.Oci__StartContainerResponse {
        _ = self;
        if (request.container_id.len == 0) {
            logger.err("Container ID is empty", .{});
            return error.InvalidContainerId;
        }

        // TODO: Реалізувати запуск контейнера через OCI runtime

        return grpc.Oci__StartContainerResponse{};
    }

    /// Реалізація StopContainer
    pub fn stopContainer(self: *Self, request: *const grpc.Oci__StopContainerRequest) !grpc.Oci__StopContainerResponse {
        _ = self;
        if (request.container_id.len == 0) {
            logger.err("Container ID is empty", .{});
            return error.InvalidContainerId;
        }

        // TODO: Реалізувати зупинку контейнера через OCI runtime

        return grpc.Oci__StopContainerResponse{};
    }
};

pub const GrpcError = error{
    ServerAlreadyStarted,
    ServerCreationFailed,
    CredentialsCreationFailed,
    PortBindingFailed,
    InvalidContainerConfig,
    InvalidContainerId,
}; 