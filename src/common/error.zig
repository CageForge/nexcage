const std = @import("std");
const logger = @import("logger");
const types = @import("types");

pub const Error = error{
    // Configuration errors
    ConfigNotFound,
    ConfigInvalid,
    InvalidConfig,
    InvalidToken,

    // Proxmox API errors
    ProxmoxAPIError,
    ProxmoxConnectionError,
    ProxmoxAuthError,
    ProxmoxResourceNotFound,
    ProxmoxOperationFailed,
    ProxmoxInvalidResponse,
    ProxmoxInvalidConfig,
    ProxmoxInvalidNode,
    ProxmoxInvalidVMID,
    ProxmoxInvalidToken,
    ProxmoxConnectionFailed,
    ProxmoxTimeout,
    ProxmoxResourceExists,
    ProxmoxInvalidState,
    ProxmoxInvalidParameter,
    ProxmoxPermissionDenied,
    ProxmoxInternalError,

    // CRI errors
    PodNotFound,
    ContainerNotFound,
    InvalidPodSpec,
    InvalidContainerSpec,
    PodCreationFailed,
    ContainerCreationFailed,
    PodDeletionFailed,
    ContainerDeletionFailed,

    // Runtime errors
    GRPCInitFailed,
    GRPCBindFailed,
    SocketError,
    ResourceLimitExceeded,

    // System errors
    FileSystemError,
    PermissionDenied,
    NetworkError,

    // New error type
    ClusterUnhealthy,

    ContainerAlreadyExists,
    InvalidContainerID,
    InvalidContainerName,
    InvalidContainerConfig,
    ContainerStartFailed,
    ContainerStopFailed,
    ContainerDeleteFailed,
    ContainerStateError,
    StorageError,
    OCIError,
    OutOfMemory,
    InvalidArgument,
    SystemError,
    UnknownError,

    InvalidArguments,
    UnknownCommand,
    UnexpectedArgument,
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
    WriterError,
    AllocationError,
    NotInitialized,
};

pub fn handleError(allocator: std.mem.Allocator, err: anyerror, context: []const u8) !void {
    const error_context = try types.ErrorContext.init(allocator, @errorName(err), err, context, null);
    defer error_context.deinit(allocator);

    try logger.err("{any}", .{error_context});
    return err;
}

pub fn handleErrorWithDetails(allocator: std.mem.Allocator, err: anyerror, context: []const u8, details: []const u8) !void {
    const error_context = try types.ErrorContext.init(allocator, @errorName(err), err, context, details);
    defer error_context.deinit(allocator);

    try logger.err("{any}", .{error_context});
    return err;
}

pub fn wrapError(comptime T: type, comptime func: fn () T!void) fn () Error!void {
    return struct {
        fn wrapped() Error!void {
            return func() catch |err| {
                return switch (err) {
                    error.OutOfMemory => Error.AllocationError,
                    error.AccessDenied => Error.FileSystemError,
                    error.FileNotFound => Error.FileSystemError,
                    error.InvalidArgument => Error.InvalidArguments,
                    error.NetworkError => Error.NetworkError,
                    error.ContainerError => Error.ContainerError,
                    error.RuntimeError => Error.RuntimeError,
                    error.ConfigNotFound => Error.ConfigNotFound,
                    error.UnknownCommand => Error.UnknownCommand,
                    error.UnexpectedArgument => Error.UnexpectedArgument,
                    error.InvalidConfigFormat => Error.InvalidConfigFormat,
                    error.InvalidLogPath => Error.InvalidLogPath,
                    error.FailedToCreateLogFile => Error.FailedToCreateLogFile,
                    error.FailedToParseConfig => Error.FailedToParseConfig,
                    error.WriterError => Error.WriterError,
                    error.AllocationError => Error.AllocationError,
                    error.NotInitialized => Error.NotInitialized,
                    else => Error.RuntimeError,
                };
            };
        }
    }.wrapped;
}

pub fn logError(logger_ctx: anytype, err: Error) void {
    const writer = logger_ctx.writer;
    writer.print("Error: {s}\n", .{@errorName(err)}) catch {};
}

pub fn formatError(err: Error) []const u8 {
    return switch (err) {
        Error.ProxmoxOperationFailed => "Proxmox operation failed",
        Error.ProxmoxAPIError => "Proxmox API error",
        Error.ProxmoxInvalidResponse => "Invalid response from Proxmox API",
        Error.ProxmoxInvalidConfig => "Invalid Proxmox configuration",
        Error.ProxmoxInvalidNode => "Invalid Proxmox node",
        Error.ProxmoxInvalidVMID => "Invalid VM ID",
        Error.ProxmoxInvalidToken => "Invalid Proxmox API token",
        Error.ProxmoxConnectionFailed => "Failed to connect to Proxmox",
        Error.ProxmoxTimeout => "Proxmox operation timed out",
        Error.ProxmoxResourceNotFound => "Resource not found in Proxmox",
        Error.ProxmoxResourceExists => "Resource already exists in Proxmox",
        Error.ProxmoxInvalidState => "Invalid state for Proxmox operation",
        Error.ProxmoxInvalidParameter => "Invalid parameter for Proxmox operation",
        Error.ProxmoxPermissionDenied => "Permission denied for Proxmox operation",
        Error.ProxmoxInternalError => "Internal Proxmox error",
    };
}
