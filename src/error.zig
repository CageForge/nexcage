const std = @import("std");
const Logger = @import("logger").Logger;

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
};

pub fn handleError(err: Error, logger: *Logger) void {
    switch (err) {
        // Configuration errors
        error.ConfigNotFound => logger.err("Configuration file not found", .{}),
        error.ConfigInvalid => logger.err("Invalid configuration", .{}),
        error.InvalidConfig => logger.err("Invalid configuration", .{}),
        error.InvalidToken => logger.err("Invalid Proxmox API token", .{}),

        // Proxmox API errors
        error.ProxmoxAPIError => logger.err("Proxmox API error", .{}),
        error.ProxmoxConnectionError => logger.err("Failed to connect to Proxmox", .{}),
        error.ProxmoxAuthError => logger.err("Proxmox authentication failed", .{}),
        error.ProxmoxResourceNotFound => logger.err("Proxmox resource not found", .{}),
        error.ProxmoxOperationFailed => logger.err("Proxmox operation failed", .{}),
        error.ProxmoxInvalidResponse => logger.err("Invalid response from Proxmox API", .{}),
        error.ProxmoxInvalidConfig => logger.err("Invalid Proxmox configuration", .{}),
        error.ProxmoxInvalidNode => logger.err("Invalid Proxmox node", .{}),
        error.ProxmoxInvalidVMID => logger.err("Invalid VM ID", .{}),
        error.ProxmoxInvalidToken => logger.err("Invalid Proxmox API token", .{}),
        error.ProxmoxConnectionFailed => logger.err("Failed to connect to Proxmox", .{}),
        error.ProxmoxTimeout => logger.err("Proxmox operation timed out", .{}),
        error.ProxmoxResourceExists => logger.err("Resource already exists in Proxmox", .{}),
        error.ProxmoxInvalidState => logger.err("Invalid state for Proxmox operation", .{}),
        error.ProxmoxInvalidParameter => logger.err("Invalid parameter for Proxmox operation", .{}),
        error.ProxmoxPermissionDenied => logger.err("Permission denied for Proxmox operation", .{}),
        error.ProxmoxInternalError => logger.err("Internal Proxmox error", .{}),

        // CRI errors
        error.PodNotFound => logger.err("Pod not found", .{}),
        error.ContainerNotFound => logger.err("Container not found", .{}),
        error.InvalidPodSpec => logger.err("Invalid pod specification", .{}),
        error.InvalidContainerSpec => logger.err("Invalid container specification", .{}),
        error.PodCreationFailed => logger.err("Failed to create pod", .{}),
        error.ContainerCreationFailed => logger.err("Failed to create container", .{}),
        error.PodDeletionFailed => logger.err("Failed to delete pod", .{}),
        error.ContainerDeletionFailed => logger.err("Failed to delete container", .{}),

        // Runtime errors
        error.GRPCInitFailed => logger.err("Failed to initialize gRPC server", .{}),
        error.GRPCBindFailed => logger.err("Failed to bind gRPC server", .{}),
        error.SocketError => logger.err("Socket error", .{}),
        error.ResourceLimitExceeded => logger.err("Resource limit exceeded", .{}),

        // System errors
        error.FileSystemError => logger.err("File system error", .{}),
        error.PermissionDenied => logger.err("Permission denied", .{}),
        error.NetworkError => logger.err("Network error", .{}),

        // New error type
        error.ClusterUnhealthy => logger.err("Cluster unhealthy", .{}),
    }
}

pub fn logError(logger: anytype, err: Error) void {
    switch (err) {
        error.ConfigNotFound => logger.err("Configuration file not found", .{}),
        error.ConfigInvalid => logger.err("Invalid configuration", .{}),
        error.ProxmoxOperationFailed => logger.err("Proxmox operation failed", .{}),
        error.ClusterUnhealthy => logger.err("Cluster unhealthy", .{}),
    }
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
