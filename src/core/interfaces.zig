const std = @import("std");
const types = @import("types.zig");

/// Core interfaces for backends and integrations
/// Backend interface for container runtimes
pub const BackendInterface = struct {
    const Self = @This();

    /// Initialize the backend
    init: *const fn (allocator: std.mem.Allocator, config: types.SandboxConfig) Error!*Self,

    /// Deinitialize the backend
    deinit: *const fn (self: *Self) void,

    /// Create a container
    create: *const fn (self: *Self, config: types.SandboxConfig) Error!void,

    /// Start a container
    start: *const fn (self: *Self, container_id: []const u8) Error!void,

    /// Stop a container
    stop: *const fn (self: *Self, container_id: []const u8) Error!void,

    /// Delete a container
    delete: *const fn (self: *Self, container_id: []const u8) Error!void,

    /// List containers
    list: *const fn (self: *Self, allocator: std.mem.Allocator) Error![]ContainerInfo,

    /// Get container info
    info: *const fn (self: *Self, container_id: []const u8, allocator: std.mem.Allocator) Error!ContainerInfo,

    /// Execute command in container
    exec: *const fn (self: *Self, container_id: []const u8, command: []const []const u8, allocator: std.mem.Allocator) Error!void,
};

/// Container information
pub const ContainerInfo = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    name: []const u8,
    state: ContainerState,
    runtime_type: types.RuntimeType,
    created_at: ?i64 = null,
    started_at: ?i64 = null,
    image: ?[]const u8 = null,
    pid: ?u32 = null,

    pub fn deinit(self: *ContainerInfo) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        if (self.image) |img| self.allocator.free(img);
    }
};

/// Container state
pub const ContainerState = enum {
    created,
    running,
    stopped,
    paused,
    unknown,
};

/// Network provider interface
pub const NetworkProvider = struct {
    const Self = @This();

    /// Initialize network provider
    init: *const fn (allocator: std.mem.Allocator, config: types.NetworkConfig) Error!*Self,

    /// Deinitialize network provider
    deinit: *const fn (self: *Self) void,

    /// Create network
    create: *const fn (self: *Self, name: []const u8, config: types.NetworkConfig) Error!void,

    /// Delete network
    delete: *const fn (self: *Self, name: []const u8) Error!void,

    /// List networks
    list: *const fn (self: *Self, allocator: std.mem.Allocator) Error![]NetworkInfo,

    /// Connect container to network
    connect: *const fn (self: *Self, container_id: []const u8, network_name: []const u8) Error!void,

    /// Disconnect container from network
    disconnect: *const fn (self: *Self, container_id: []const u8, network_name: []const u8) Error!void,
};

/// Network information
pub const NetworkInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    id: []const u8,
    driver: []const u8,
    scope: []const u8,
    ip_range: ?[]const u8 = null,
    gateway: ?[]const u8 = null,

    pub fn deinit(self: *NetworkInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.id);
        self.allocator.free(self.driver);
        self.allocator.free(self.scope);
        if (self.ip_range) |ip| self.allocator.free(ip);
        if (self.gateway) |gw| self.allocator.free(gw);
    }
};

/// Storage provider interface
pub const StorageProvider = struct {
    const Self = @This();

    /// Initialize storage provider
    init: *const fn (allocator: std.mem.Allocator, config: types.StorageConfig) Error!*Self,

    /// Deinitialize storage provider
    deinit: *const fn (self: *Self) void,

    /// Create storage
    create: *const fn (self: *Self, name: []const u8, config: types.StorageConfig) Error!void,

    /// Delete storage
    delete: *const fn (self: *Self, name: []const u8) Error!void,

    /// List storage
    list: *const fn (self: *Self, allocator: std.mem.Allocator) Error![]StorageInfo,

    /// Mount storage
    mount: *const fn (self: *Self, storage_name: []const u8, mount_point: []const u8) Error!void,

    /// Unmount storage
    unmount: *const fn (self: *Self, storage_name: []const u8) Error!void,
};

/// Storage information
pub const StorageInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    id: []const u8,
    driver: []const u8,
    size: ?u64 = null,
    used: ?u64 = null,
    available: ?u64 = null,
    mount_point: ?[]const u8 = null,

    pub fn deinit(self: *StorageInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.id);
        self.allocator.free(self.driver);
        if (self.mount_point) |mp| self.allocator.free(mp);
    }
};

/// Image provider interface
pub const ImageProvider = struct {
    const Self = @This();

    /// Initialize image provider
    init: *const fn (allocator: std.mem.Allocator) Error!*Self,

    /// Deinitialize image provider
    deinit: *const fn (self: *Self) void,

    /// Pull image
    pull: *const fn (self: *Self, image_name: []const u8) Error!void,

    /// Push image
    push: *const fn (self: *Self, image_name: []const u8) Error!void,

    /// List images
    list: *const fn (self: *Self, allocator: std.mem.Allocator) Error![]ImageInfo,

    /// Remove image
    remove: *const fn (self: *Self, image_name: []const u8) Error!void,

    /// Get image info
    info: *const fn (self: *Self, image_name: []const u8, allocator: std.mem.Allocator) Error!ImageInfo,
};

/// Image information
pub const ImageInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    id: []const u8,
    tag: ?[]const u8 = null,
    size: ?u64 = null,
    created_at: ?i64 = null,
    architecture: ?[]const u8 = null,
    os: ?[]const u8 = null,

    pub fn deinit(self: *ImageInfo) void {
        self.allocator.free(self.name);
        self.allocator.free(self.id);
        if (self.tag) |t| self.allocator.free(t);
        if (self.architecture) |arch| self.allocator.free(arch);
        if (self.os) |os_name| self.allocator.free(os_name);
    }
};

/// CLI command interface
pub const CommandInterface = struct {
    const Self = @This();

    /// Command name
    name: []const u8,

    /// Command description
    description: []const u8,

    /// Execute command
    execute: *const fn (self: *Self, options: types.RuntimeOptions, allocator: std.mem.Allocator) Error!void,

    /// Get command help
    help: *const fn (self: *Self, allocator: std.mem.Allocator) Error![]const u8,

    /// Validate command arguments
    validate: *const fn (self: *Self, args: []const []const u8) Error!void,
};

/// Error type for interfaces
pub const Error = types.Error;
