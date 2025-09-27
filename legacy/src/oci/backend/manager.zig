// Backend manager for handling plugin operations
// This module provides the main interface for managing backend plugins

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const plugin = @import("plugin.zig");
const crun_backend = @import("crun.zig");
const proxmox_lxc_backend = @import("proxmox_lxc.zig");
const proxmox_vm_backend = @import("proxmox_vm.zig");

/// Backend manager for handling plugin operations
pub const BackendManager = struct {
    const Self = @This();

    allocator: Allocator,
    registry: plugin.BackendRegistry,
    default_backend: plugin.BackendType,
    logger: *logger_mod.Logger,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !Self {
        const registry = try plugin.BackendRegistry.init(allocator);

        return Self{
            .allocator = allocator,
            .registry = registry,
            .default_backend = .crun, // Default to crun
            .logger = logger,
        };
    }

    pub fn deinit(self: *Self) void {
        self.registry.deinit();
    }

    /// Initialize all available backend plugins
    pub fn initializePlugins(self: *Self) !void {
        try self.logger.info("Initializing backend plugins...", .{});

        // Register Crun backend
        var crun_plugin = try crun_backend.createCrunPlugin(self.allocator, self.logger);
        try self.registry.register(&crun_plugin);
        try self.logger.info("Registered Crun backend plugin", .{});

        // Register Proxmox LXC backend
        var proxmox_lxc_plugin = try proxmox_lxc_backend.createProxmoxLXCPlugin(self.allocator, self.logger);
        try self.registry.register(&proxmox_lxc_plugin);
        try self.logger.info("Registered Proxmox LXC backend plugin", .{});

        // Register Proxmox VM backend
        var proxmox_vm_plugin = try proxmox_vm_backend.createProxmoxVMPlugin(self.allocator, self.logger);
        try self.registry.register(&proxmox_vm_plugin);
        try self.logger.info("Registered Proxmox VM backend plugin", .{});

        // Set default backend based on availability
        if (self.registry.isBackendAvailable(.crun)) {
            self.default_backend = .crun;
        } else if (self.registry.isBackendAvailable(.proxmox_lxc)) {
            self.default_backend = .proxmox_lxc;
        } else if (self.registry.isBackendAvailable(.proxmox_vm)) {
            self.default_backend = .proxmox_vm;
        } else {
            return error.NoBackendAvailable;
        }

        try self.logger.info("Backend plugins initialized. Default backend: {s}", .{@tagName(self.default_backend)});
    }

    /// Register a backend plugin
    pub fn registerBackend(self: *Self, backend_plugin: *plugin.BackendPlugin) !void {
        try self.registry.register(backend_plugin);
        try self.logger.info("Registered backend plugin: {s} ({s})", .{ backend_plugin.name, @tagName(backend_plugin.backend_type) });
    }

    /// Get a backend plugin by type
    pub fn getBackend(self: *Self, backend_type: plugin.BackendType) ?*plugin.BackendPlugin {
        return self.registry.get(backend_type);
    }

    /// Get the default backend
    pub fn getDefaultBackend(self: *Self) ?*plugin.BackendPlugin {
        return self.registry.get(self.default_backend);
    }

    /// Set the default backend
    pub fn setDefaultBackend(self: *Self, backend_type: plugin.BackendType) !void {
        if (self.registry.get(backend_type)) |_| {
            self.default_backend = backend_type;
            try self.logger.info("Set default backend to: {s}", .{@tagName(backend_type)});
        } else {
            return error.BackendNotRegistered;
        }
    }

    /// List all available backends
    pub fn listAvailableBackends(self: *Self) ![]plugin.BackendType {
        var available = std.ArrayList(plugin.BackendType).init(self.allocator);
        defer available.deinit();

        const backends = try self.registry.listBackends();
        defer self.allocator.free(backends);

        for (backends) |backend_type| {
            if (self.registry.isBackendAvailable(backend_type)) {
                try available.append(backend_type);
            }
        }

        return available.toOwnedSlice();
    }

    /// Create a container using the specified backend
    pub fn createContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.createContainer(backend, container_id, bundle_path, options);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Start a container using the specified backend
    pub fn startContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.startContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Stop a container using the specified backend
    pub fn stopContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.stopContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Delete a container using the specified backend
    pub fn deleteContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.deleteContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Get container state using the specified backend
    pub fn getContainerState(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !plugin.ContainerState {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.getContainerState(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Get container info using the specified backend
    pub fn getContainerInfo(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !plugin.ContainerInfo {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.getContainerInfo(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// List containers using the specified backend
    pub fn listContainers(self: *Self, backend_type: plugin.BackendType) ![]plugin.ContainerInfo {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.listContainers(backend);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Pause a container using the specified backend
    pub fn pauseContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.pauseContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Resume a container using the specified backend
    pub fn resumeContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.resumeContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Kill a container using the specified backend
    pub fn killContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8, signal: ?i32) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.killContainer(backend, container_id, signal);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Execute command in container using the specified backend
    pub fn execContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8, command: []const []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.execContainer(backend, container_id, command);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Get container logs using the specified backend
    pub fn getContainerLogs(self: *Self, backend_type: plugin.BackendType, container_id: []const u8) ![]const u8 {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.getContainerLogs(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Checkpoint a container using the specified backend
    pub fn checkpointContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8, checkpoint_path: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.checkpointContainer(backend, container_id, checkpoint_path);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Restore a container from checkpoint using the specified backend
    pub fn restoreContainer(self: *Self, backend_type: plugin.BackendType, container_id: []const u8, checkpoint_path: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.restoreContainer(backend, container_id, checkpoint_path);
        } else {
            return error.BackendNotAvailable;
        }
    }

    /// Create a container using the default backend
    pub fn createContainerDefault(self: *Self, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        try self.createContainer(self.default_backend, container_id, bundle_path, options);
    }

    /// Start a container using the default backend
    pub fn startContainerDefault(self: *Self, container_id: []const u8) !void {
        try self.startContainer(self.default_backend, container_id);
    }

    /// Stop a container using the default backend
    pub fn stopContainerDefault(self: *Self, container_id: []const u8) !void {
        try self.stopContainer(self.default_backend, container_id);
    }

    /// Delete a container using the default backend
    pub fn deleteContainerDefault(self: *Self, container_id: []const u8) !void {
        try self.deleteContainer(self.default_backend, container_id);
    }

    /// Get container state using the default backend
    pub fn getContainerStateDefault(self: *Self, container_id: []const u8) !plugin.ContainerState {
        return try self.getContainerState(self.default_backend, container_id);
    }

    /// Get container info using the default backend
    pub fn getContainerInfoDefault(self: *Self, container_id: []const u8) !plugin.ContainerInfo {
        return try self.getContainerInfo(self.default_backend, container_id);
    }

    /// List containers using the default backend
    pub fn listContainersDefault(self: *Self) ![]plugin.ContainerInfo {
        return try self.listContainers(self.default_backend);
    }

    /// Pause a container using the default backend
    pub fn pauseContainerDefault(self: *Self, container_id: []const u8) !void {
        try self.pauseContainer(self.default_backend, container_id);
    }

    /// Resume a container using the default backend
    pub fn resumeContainerDefault(self: *Self, container_id: []const u8) !void {
        try self.resumeContainer(self.default_backend, container_id);
    }

    /// Kill a container using the default backend
    pub fn killContainerDefault(self: *Self, container_id: []const u8, signal: ?i32) !void {
        try self.killContainer(self.default_backend, container_id, signal);
    }

    /// Execute command in container using the default backend
    pub fn execContainerDefault(self: *Self, container_id: []const u8, command: []const []const u8) !void {
        try self.execContainer(self.default_backend, container_id, command);
    }

    /// Get container logs using the default backend
    pub fn getContainerLogsDefault(self: *Self, container_id: []const u8) ![]const u8 {
        return try self.getContainerLogs(self.default_backend, container_id);
    }

    /// Checkpoint a container using the default backend
    pub fn checkpointContainerDefault(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.checkpointContainer(self.default_backend, container_id, checkpoint_path);
    }

    /// Restore a container from checkpoint using the default backend
    pub fn restoreContainerDefault(self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void {
        try self.restoreContainer(self.default_backend, container_id, checkpoint_path);
    }
};

/// Backend manager errors
pub const BackendManagerError = error{
    BackendNotRegistered,
    BackendNotAvailable,
    BackendInitializationFailed,
    BackendOperationFailed,
    ContainerNotFound,
    ContainerAlreadyExists,
    InvalidBackendType,
    PluginLoadFailed,
    NoBackendAvailable,
};
