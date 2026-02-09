/// NexCage Plugin System - Main Module
/// 
/// This module provides the complete plugin system for NexCage, including
/// plugin management, backend plugin loading, and system integration.

// Re-export core plugin system
pub const plugin = @import("../plugin/mod.zig");
pub const backends = @import("backends/mod.zig");

// Re-export main types for convenience
pub const Plugin = plugin.Plugin;
pub const PluginManager = plugin.PluginManager;
pub const HookSystem = plugin.HookSystem;
pub const PluginContext = plugin.PluginContext;
pub const SecuritySandbox = @import("../plugin/sandbox.zig").SecuritySandbox;

// Plugin API version
pub const PLUGIN_API_VERSION: u32 = 1;

// Plugin system initialization
pub const PluginSystem = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugin_manager: *plugin.PluginManager,
    backend_registry: backends.BackendPluginRegistry,
    backend_loader: backends.BackendPluginLoader,
    initialized: bool = false,
    
    pub fn init(allocator: std.mem.Allocator, config: plugin.PluginManagerConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        // Initialize plugin manager
        const manager = try plugin.PluginManager.init(allocator, config);
        errdefer manager.deinit();
        
        // Initialize backend registry
        var backend_registry = backends.BackendPluginRegistry.init(allocator);
        errdefer backend_registry.deinit();
        
        // Register default backend plugins
        try backends.initializeDefaultBackendPlugins(&backend_registry);
        
        // Initialize backend loader
        const backend_loader = backends.BackendPluginLoader.init(allocator, manager, &backend_registry);
        
        self.* = Self{
            .allocator = allocator,
            .plugin_manager = manager,
            .backend_registry = backend_registry,
            .backend_loader = backend_loader,
            .initialized = false,
        };
        
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.initialized) {
            self.shutdown();
        }
        
        self.backend_registry.deinit();
        self.plugin_manager.deinit();
        self.allocator.destroy(self);
    }
    
    /// Initialize the plugin system
    pub fn initialize(self: *Self) !void {
        if (self.initialized) {
            return;
        }
        
        std.log.info("Initializing NexCage plugin system...", .{});
        
        // Discover and load core plugins
        try self.plugin_manager.discoverAndLoadPlugins();
        
        // Load backend plugins
        try self.backend_loader.loadBackendPlugins();
        
        self.initialized = true;
        std.log.info("Plugin system initialized successfully", .{});
    }
    
    /// Shutdown the plugin system
    pub fn shutdown(self: *Self) void {
        if (!self.initialized) {
            return;
        }
        
        std.log.info("Shutting down plugin system...", .{});
        
        // Shutdown all plugins gracefully
        self.plugin_manager.shutdownAllPlugins();
        
        self.initialized = false;
        std.log.info("Plugin system shutdown complete", .{});
    }
    
    /// Get available container runtime backends
    pub fn getAvailableBackends(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        return self.backend_loader.getAvailableBackends(allocator);
    }
    
    /// Get plugin manager for direct access
    pub fn getPluginManager(self: *Self) *plugin.PluginManager {
        return self.plugin_manager;
    }
    
    /// Get backend registry for direct access
    pub fn getBackendRegistry(self: *Self) *backends.BackendPluginRegistry {
        return &self.backend_registry;
    }
    
    /// Load a specific plugin by name
    pub fn loadPlugin(self: *Self, plugin_name: []const u8) !void {
        try self.plugin_manager.loadPlugin(plugin_name);
    }
    
    /// Unload a specific plugin by name
    pub fn unloadPlugin(self: *Self, plugin_name: []const u8) !void {
        try self.plugin_manager.unloadPlugin(plugin_name);
    }
    
    /// Reload a specific plugin
    pub fn reloadPlugin(self: *Self, plugin_name: []const u8) !void {
        try self.plugin_manager.reloadPlugin(plugin_name);
    }
    
    /// List all loaded plugins
    pub fn listPlugins(self: *Self, allocator: std.mem.Allocator) ![]plugin.PluginInfo {
        return self.plugin_manager.listPlugins(allocator);
    }
    
    /// Perform health check on all plugins
    pub fn performHealthCheck(self: *Self) !std.StringHashMap(plugin.HealthStatus) {
        return self.plugin_manager.performHealthCheck();
    }
    
    /// Enable/disable a backend plugin
    pub fn setBackendEnabled(self: *Self, backend_name: []const u8, enabled: bool) bool {
        return self.backend_registry.setPluginEnabled(backend_name, enabled);
    }
    
    /// Execute a container operation using the best available backend
    pub fn executeContainerOperation(
        self: *Self,
        operation: ContainerOperation,
        container_id: []const u8,
        allocator: std.mem.Allocator
    ) !plugin.CommandResult {
        // Get the first available backend plugin
        const backends_list = try self.getAvailableBackends(allocator);
        defer {
            for (backends_list) |backend| {
                allocator.free(backend);
            }
            allocator.free(backends_list);
        }
        
        if (backends_list.len == 0) {
            return error.NoBackendsAvailable;
        }
        
        const backend_name = backends_list[0];
        const backend_plugin = self.plugin_manager.getPlugin(backend_name) orelse {
            return error.BackendPluginNotLoaded;
        };
        
        // Execute operation based on type
        switch (operation) {
            .create => {
                if (backend_plugin.extensions.backend) |backend| {
                    try backend.create(backend_plugin.context.?, container_id);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = try allocator.dupe(u8, ""),
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
            .start => {
                if (backend_plugin.extensions.backend) |backend| {
                    try backend.start(backend_plugin.context.?, container_id);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = try allocator.dupe(u8, ""),
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
            .stop => {
                if (backend_plugin.extensions.backend) |backend| {
                    try backend.stop(backend_plugin.context.?, container_id);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = try allocator.dupe(u8, ""),
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
            .delete => {
                if (backend_plugin.extensions.backend) |backend| {
                    try backend.delete(backend_plugin.context.?, container_id);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = try allocator.dupe(u8, ""),
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
            .list => {
                if (backend_plugin.extensions.backend) |backend| {
                    const result = try backend.list(backend_plugin.context.?, allocator);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = result,
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
            .info => {
                if (backend_plugin.extensions.backend) |backend| {
                    const result = try backend.info(backend_plugin.context.?, container_id, allocator);
                    return plugin.CommandResult{
                        .exit_code = 0,
                        .stdout = result,
                        .stderr = try allocator.dupe(u8, ""),
                        .duration_ms = 0,
                    };
                }
            },
        }
        
        return error.OperationNotSupported;
    }
};

/// Container operations supported by backend plugins
pub const ContainerOperation = enum {
    create,
    start,
    stop,
    delete,
    list,
    info,
};

const std = @import("std");

/// Test suite
const testing = std.testing;

test "plugin system initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create temporary directories for testing
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const plugin_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(plugin_dir_path);
    
    const config = plugin.PluginManagerConfig{
        .plugin_dir = plugin_dir_path,
        .cache_dir = plugin_dir_path,
        .auto_load_plugins = false,
        .sandbox_enabled = false,
    };
    
    // Test plugin system initialization
    const plugin_system = try PluginSystem.init(allocator, config);
    defer plugin_system.deinit();
    
    try testing.expect(!plugin_system.initialized);
    
    // Test getting available backends before initialization
    const available_backends = try plugin_system.getAvailableBackends(allocator);
    defer {
        for (available_backends) |backend| {
            allocator.free(backend);
        }
        allocator.free(available_backends);
    }
    
    // Should have our registered backend plugins
    try testing.expect(available_backends.len >= 2); // crun and runc
    
    // Test that plugin manager is accessible
    const manager = plugin_system.getPluginManager();
    try testing.expect(manager != null);
    
    // Test that backend registry is accessible
    const registry = plugin_system.getBackendRegistry();
    try testing.expect(registry != null);
}

test "backend plugin registry integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const plugin_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(plugin_dir_path);
    
    const config = plugin.PluginManagerConfig{
        .plugin_dir = plugin_dir_path,
        .cache_dir = plugin_dir_path,
        .auto_load_plugins = false,
        .sandbox_enabled = false,
    };
    
    const plugin_system = try PluginSystem.init(allocator, config);
    defer plugin_system.deinit();
    
    // Test enabling/disabling backends
    try testing.expect(plugin_system.setBackendEnabled("crun-backend", false));
    try testing.expect(plugin_system.setBackendEnabled("runc-backend", true));
    
    // Test non-existent backend
    try testing.expect(!plugin_system.setBackendEnabled("non-existent-backend", false));
}

test "container operation enumeration" {
    // Test that all container operations are properly defined
    const operations = [_]ContainerOperation{
        .create, .start, .stop, .delete, .list, .info
    };
    
    try testing.expect(operations.len == 6);
    
    // Test that operations can be used in switch statements
    for (operations) |op| {
        const name = switch (op) {
            .create => "create",
            .start => "start", 
            .stop => "stop",
            .delete => "delete",
            .list => "list",
            .info => "info",
        };
        try testing.expect(name.len > 0);
    }
}