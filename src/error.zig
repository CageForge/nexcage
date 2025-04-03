const std = @import("std");

pub const Error = error{
    // Configuration errors
    ConfigNotFound,
    InvalidConfig,
    InvalidToken,

    // Proxmox API errors
    ProxmoxAPIError,
    ProxmoxConnectionError,
    ProxmoxAuthError,
    ProxmoxResourceNotFound,
    ProxmoxOperationFailed,

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
};

pub fn handleError(err: Error, logger: *Logger) void {
    switch (err) {
        // Configuration errors
        error.ConfigNotFound => logger.err("Configuration file not found", .{}),
        error.InvalidConfig => logger.err("Invalid configuration", .{}),
        error.InvalidToken => logger.err("Invalid Proxmox API token", .{}),

        // Proxmox API errors
        error.ProxmoxAPIError => logger.err("Proxmox API error", .{}),
        error.ProxmoxConnectionError => logger.err("Failed to connect to Proxmox", .{}),
        error.ProxmoxAuthError => logger.err("Proxmox authentication failed", .{}),
        error.ProxmoxResourceNotFound => logger.err("Proxmox resource not found", .{}),
        error.ProxmoxOperationFailed => logger.err("Proxmox operation failed", .{}),

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
    }
} 