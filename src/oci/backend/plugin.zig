// Backend plugin system for OCI commands
// This module defines the interface and base structures for backend plugins

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");

/// Backend type enumeration
pub const BackendType = enum {
    crun,
    proxmox_lxc,
    proxmox_vm,
    bfc,
};

/// Container state for backend operations
pub const ContainerState = enum {
    created,
    running,
    stopped,
    paused,
    deleted,
    unknown,
};

/// Container information structure
pub const ContainerInfo = struct {
    id: []const u8,
    name: []const u8,
    state: ContainerState,
    pid: ?u32,
    bundle: []const u8,
    created_at: ?[]const u8,
    started_at: ?[]const u8,
    finished_at: ?[]const u8,
    allocator: Allocator,

    pub fn deinit(self: *ContainerInfo) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.bundle);
        if (self.created_at) |time| self.allocator.free(time);
        if (self.started_at) |time| self.allocator.free(time);
        if (self.finished_at) |time| self.allocator.free(time);
    }
};

/// Backend plugin interface
pub const BackendPlugin = struct {
    const Self = @This();
    
    /// Backend type
    backend_type: BackendType,
    /// Plugin name
    name: []const u8,
    /// Plugin version
    version: []const u8,
    /// Plugin description
    description: []const u8,
    /// Allocator for memory management
    allocator: Allocator,
    /// Logger instance
    logger: *logger_mod.Logger,

    /// Initialize the backend plugin
    init: *const fn (allocator: Allocator, logger: *logger_mod.Logger) anyerror!Self,
    
    /// Cleanup resources
    deinit: *const fn (self: *Self) void,
    
    /// Check if backend is available
    isAvailable: *const fn (self: *const Self) bool,
    
    /// Create a container
    createContainer: *const fn (self: *Self, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void,
    
    /// Start a container
    startContainer: *const fn (self: *Self, container_id: []const u8) !void,
    
    /// Stop a container
    stopContainer: *const fn (self: *Self, container_id: []const u8) !void,
    
    /// Delete a container
    deleteContainer: *const fn (self: *Self, container_id: []const u8) !void,
    
    /// Get container state
    getContainerState: *const fn (self: *const Self, container_id: []const u8) !ContainerState,
    
    /// Get container information
    getContainerInfo: *const fn (self: *const Self, container_id: []const u8) !ContainerInfo,
    
    /// List all containers
    listContainers: *const fn (self: *const Self) ![]ContainerInfo,
    
    /// Pause a container
    pauseContainer: *const fn (self: *Self, container_id: []const u8) !void,
    
    /// Resume a container
    resumeContainer: *const fn (self: *Self, container_id: []const u8) !void,
    
    /// Kill a container
    killContainer: *const fn (self: *Self, container_id: []const u8, signal: ?i32) !void,
    
    /// Execute command in container
    execContainer: *const fn (self: *Self, container_id: []const u8, command: []const []const u8) !void,
    
    /// Get container logs
    getContainerLogs: *const fn (self: *const Self, container_id: []const u8) ![]const u8,
    
    /// Checkpoint a container
    checkpointContainer: *const fn (self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void,
    
    /// Restore a container from checkpoint
    restoreContainer: *const fn (self: *Self, container_id: []const u8, checkpoint_path: []const u8) !void,
};

/// Backend plugin registry
pub const BackendRegistry = struct {
    const Self = @This();
    
    allocator: Allocator,
    plugins: std.HashMap(BackendType, *BackendPlugin, std.hash_map.default_hash_fn(BackendType), std.hash_map.default_eql_fn(BackendType)),
    
    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .plugins = std.HashMap(BackendType, *BackendPlugin, std.hash_map.default_hash_fn(BackendType), std.hash_map.default_eql_fn(BackendType)).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit(entry.value_ptr.*);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.plugins.deinit();
    }
    
    /// Register a backend plugin
    pub fn register(self: *Self, plugin: *BackendPlugin) !void {
        try self.plugins.put(plugin.backend_type, plugin);
    }
    
    /// Get a backend plugin by type
    pub fn get(self: *const Self, backend_type: BackendType) ?*BackendPlugin {
        return self.plugins.get(backend_type);
    }
    
    /// List all registered backend types
    pub fn listBackends(self: *const Self) ![]BackendType {
        const backends = try self.allocator.alloc(BackendType, self.plugins.count());
        var i: usize = 0;
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            backends[i] = entry.key_ptr.*;
            i += 1;
        }
        return backends;
    }
    
    /// Check if a backend is available
    pub fn isBackendAvailable(self: *const Self, backend_type: BackendType) bool {
        if (self.get(backend_type)) |plugin| {
            return plugin.isAvailable(plugin);
        }
        return false;
    }
};

/// Backend manager for handling plugin operations
pub const BackendManager = struct {
    const Self = @This();
    
    allocator: Allocator,
    registry: BackendRegistry,
    default_backend: BackendType,
    logger: *logger_mod.Logger,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !Self {
        const registry = try BackendRegistry.init(allocator);
        
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
    
    /// Register a backend plugin
    pub fn registerBackend(self: *Self, plugin: *BackendPlugin) !void {
        try self.registry.register(plugin);
        try self.logger.info("Registered backend plugin: {s} ({s})", .{ plugin.name, @tagName(plugin.backend_type) });
    }
    
    /// Get a backend plugin by type
    pub fn getBackend(self: *Self, backend_type: BackendType) ?*BackendPlugin {
        return self.registry.get(backend_type);
    }
    
    /// Get the default backend
    pub fn getDefaultBackend(self: *Self) ?*BackendPlugin {
        return self.registry.get(self.default_backend);
    }
    
    /// Set the default backend
    pub fn setDefaultBackend(self: *Self, backend_type: BackendType) !void {
        if (self.registry.get(backend_type)) |_| {
            self.default_backend = backend_type;
            try self.logger.info("Set default backend to: {s}", .{@tagName(backend_type)});
        } else {
            return error.BackendNotRegistered;
        }
    }
    
    /// List all available backends
    pub fn listAvailableBackends(self: *Self) ![]BackendType {
        var available = std.ArrayList(BackendType).init(self.allocator);
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
    pub fn createContainer(self: *Self, backend_type: BackendType, container_id: []const u8, bundle_path: []const u8, options: ?[]const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.createContainer(backend, container_id, bundle_path, options);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// Start a container using the specified backend
    pub fn startContainer(self: *Self, backend_type: BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.startContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// Stop a container using the specified backend
    pub fn stopContainer(self: *Self, backend_type: BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.stopContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// Delete a container using the specified backend
    pub fn deleteContainer(self: *Self, backend_type: BackendType, container_id: []const u8) !void {
        if (self.getBackend(backend_type)) |backend| {
            try backend.deleteContainer(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// Get container state using the specified backend
    pub fn getContainerState(self: *Self, backend_type: BackendType, container_id: []const u8) !ContainerState {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.getContainerState(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// Get container info using the specified backend
    pub fn getContainerInfo(self: *Self, backend_type: BackendType, container_id: []const u8) !ContainerInfo {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.getContainerInfo(backend, container_id);
        } else {
            return error.BackendNotAvailable;
        }
    }
    
    /// List containers using the specified backend
    pub fn listContainers(self: *Self, backend_type: BackendType) ![]ContainerInfo {
        if (self.getBackend(backend_type)) |backend| {
            return try backend.listContainers(backend);
        } else {
            return error.BackendNotAvailable;
        }
    }
};

/// Backend plugin errors
pub const BackendError = error{
    BackendNotRegistered,
    BackendNotAvailable,
    BackendInitializationFailed,
    BackendOperationFailed,
    ContainerNotFound,
    ContainerAlreadyExists,
    InvalidBackendType,
    PluginLoadFailed,
};
