/// Plugin Manager - Core orchestrator for the NexCage plugin system
/// 
/// This module handles plugin lifecycle, dependency management, security,
/// resource allocation, and coordination between plugins and the core system.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const plugin = @import("plugin.zig");
const validation = @import("validation.zig");
const hooks = @import("hooks.zig");
const plugin_context = @import("context.zig");

/// Plugin manager configuration
pub const PluginManagerConfig = struct {
    plugin_dir: []const u8 = "/etc/nexcage/plugins",
    cache_dir: []const u8 = "/var/cache/nexcage/plugins",
    max_plugins: u32 = 100,
    enable_hot_reload: bool = true,
    require_signatures: bool = true,
    sandbox_enabled: bool = true,
    memory_limit_mb: u32 = 512,
    cpu_limit_percent: u32 = 10,
    plugin_timeout_seconds: u32 = 30,
    max_plugin_size_mb: u32 = 100,
    enable_plugin_metrics: bool = true,
    auto_load_plugins: bool = true,

    pub fn validate(self: *const PluginManagerConfig) bool {
        return self.max_plugins > 0 and self.max_plugins <= 1000 and
               self.memory_limit_mb > 0 and self.memory_limit_mb <= 4096 and
               self.cpu_limit_percent > 0 and self.cpu_limit_percent <= 100 and
               self.plugin_timeout_seconds > 0 and self.plugin_timeout_seconds <= 300 and
               self.max_plugin_size_mb > 0 and self.max_plugin_size_mb <= 1024;
    }
};

/// Plugin manager errors
pub const PluginManagerError = error{
    PluginNotFound,
    PluginAlreadyLoaded,
    IncompatibleVersion,
    InitializationFailed,
    SecurityViolation,
    DependencyMissing,
    ResourceExhausted,
    InvalidSignature,
    InvalidConfiguration,
    MaxPluginsReached,
    PluginDirectoryNotFound,
    HotReloadFailed,
} || Allocator.Error || validation.ValidationError;

/// Plugin dependency graph node
const PluginDependency = struct {
    name: []const u8,
    version_requirement: plugin.SemanticVersion,
    optional: bool = false,
};

/// Plugin load order information
const PluginLoadOrder = struct {
    plugin_name: []const u8,
    dependencies: []const PluginDependency,
    load_priority: u32 = 100, // Lower numbers load first
};

/// Plugin manager - central coordinator for all plugin operations
pub const PluginManager = struct {
    const Self = @This();

    allocator: Allocator,
    config: PluginManagerConfig,
    
    // Plugin storage and management
    plugins: std.StringHashMap(*plugin.Plugin),
    plugin_metadata: std.StringHashMap(plugin.PluginMetadata),
    plugin_load_order: ArrayList(PluginLoadOrder),
    
    // System integration
    hook_system: ?*hooks.HookSystem = null,
    security_sandbox: ?*SecuritySandbox = null,
    resource_manager: ?*ResourceManager = null,
    
    // State tracking
    shutdown_requested: bool = false,
    metrics_enabled: bool = true,
    
    pub fn init(allocator: Allocator, config: PluginManagerConfig) !*Self {
        if (!config.validate()) {
            return PluginManagerError.InvalidConfiguration;
        }

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .config = config,
            .plugins = std.StringHashMap(*plugin.Plugin).init(allocator),
            .plugin_metadata = std.StringHashMap(plugin.PluginMetadata).init(allocator),
            .plugin_load_order = ArrayList(PluginLoadOrder).empty,
        };

        // Initialize subsystems
        if (config.sandbox_enabled) {
            self.security_sandbox = try SecuritySandbox.init(allocator, config);
        }

        self.hook_system = try hooks.HookSystem.init(allocator);
        self.resource_manager = try ResourceManager.init(allocator, config);

        // Create required directories
        try self.createDirectories();

        std.log.info("Plugin manager initialized with {} max plugins", .{config.max_plugins});

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Graceful shutdown of all plugins
        self.shutdownAllPlugins();

        // Cleanup subsystems
        if (self.security_sandbox) |sandbox| {
            sandbox.deinit();
        }
        if (self.hook_system) |hook_sys| {
            hook_sys.deinit();
        }
        if (self.resource_manager) |rm| {
            rm.deinit();
        }

        // Cleanup data structures
        self.cleanupPlugins();
        
        // Cleanup plugins HashMap keys
        var plugins_iterator = self.plugins.iterator();
        while (plugins_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.plugins.deinit();
        
        // Cleanup plugin metadata HashMap keys and values
        var metadata_iterator = self.plugin_metadata.iterator();
        while (metadata_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            // Only deinit if the plugin was never loaded (metadata still exists)
            var metadata = entry.value_ptr.*;
            metadata.deinit(self.allocator);
        }
        self.plugin_metadata.deinit();
        
        self.plugin_load_order.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Discover and load all plugins in the plugin directory
    pub fn discoverAndLoadPlugins(self: *Self) !void {
        if (!self.config.auto_load_plugins) {
            std.log.debug("Auto-loading disabled, skipping plugin discovery", .{});
            return;
        }

        std.log.info("Discovering plugins in: {s}", .{self.config.plugin_dir});

        // First pass: discover all plugin metadata
        try self.discoverPluginMetadata();

        // Second pass: resolve dependencies and create load order
        try self.resolveDependencies();

        // Third pass: load plugins in dependency order
        try self.loadPluginsInOrder();

        std.log.info("Plugin discovery completed. Loaded {} plugins", .{self.plugins.count()});
    }

    /// Load a specific plugin by name
    pub fn loadPlugin(self: *Self, plugin_name: []const u8) !void {
        // Validate plugin name
        try validation.validateContainerId(plugin_name);

        if (self.plugins.contains(plugin_name)) {
            return PluginManagerError.PluginAlreadyLoaded;
        }

        if (self.plugins.count() >= self.config.max_plugins) {
            return PluginManagerError.MaxPluginsReached;
        }

        std.log.info("Loading plugin: {s}", .{plugin_name});

        const metadata = self.plugin_metadata.get(plugin_name) orelse {
            std.log.err("Plugin metadata not found: {s}", .{plugin_name});
            return PluginManagerError.PluginNotFound;
        };

        // Check dependencies
        try self.validateDependencies(metadata.dependencies);

        // Load the plugin
        const loaded_plugin = try self.loadPluginFromMetadata(metadata);
        errdefer loaded_plugin.deinit(self.allocator);

        // Initialize plugin context
        const plugin_ctx = try self.createPluginContext(loaded_plugin);
        loaded_plugin.context = plugin_ctx;

        // Call plugin initialization hook
        if (loaded_plugin.hooks.init) |init_hook| {
            init_hook(plugin_ctx) catch |err| {
                std.log.err("Plugin initialization failed for {s}: {}", .{ plugin_name, err });
                return PluginManagerError.InitializationFailed;
            };
        }

        // Register plugin with subsystems
        try self.registerPluginWithSubsystems(loaded_plugin);

        // Store in active plugins
        try self.plugins.put(try self.allocator.dupe(u8, plugin_name), loaded_plugin);
        loaded_plugin.setStatus(.loaded);

        std.log.info("Plugin loaded successfully: {s} v{any}", .{ plugin_name, metadata.version });
    }

    /// Unload a specific plugin
    pub fn unloadPlugin(self: *Self, plugin_name: []const u8) !void {
        const loaded_plugin = self.plugins.get(plugin_name) orelse {
            return PluginManagerError.PluginNotFound;
        };

        std.log.info("Unloading plugin: {s}", .{plugin_name});
        loaded_plugin.setStatus(.unloading);

        // Check if other plugins depend on this one
        if (try self.hasReverseDependencies(plugin_name)) {
            std.log.warn("Plugin {s} has dependent plugins, unloading anyway", .{plugin_name});
        }

        // Call plugin cleanup hook
        if (loaded_plugin.hooks.deinit) |deinit_hook| {
            deinit_hook(loaded_plugin.context.?);
        }

        // Cleanup plugin context
        if (loaded_plugin.context) |ctx| {
            ctx.deinit();
        }

        // Unregister from subsystems
        self.unregisterPluginFromSubsystems(loaded_plugin);

        // Remove from active plugins and free the key
        if (self.plugins.fetchRemove(plugin_name)) |kv| {
            self.allocator.free(kv.key);
        }
        loaded_plugin.deinit(self.allocator);

        std.log.info("Plugin unloaded: {s}", .{plugin_name});
    }

    /// Reload a plugin (unload and load again)
    pub fn reloadPlugin(self: *Self, plugin_name: []const u8) !void {
        if (!self.config.enable_hot_reload) {
            return PluginManagerError.HotReloadFailed;
        }

        std.log.info("Reloading plugin: {s}", .{plugin_name});

        // Save plugin state if supported
        const loaded_plugin = self.plugins.get(plugin_name);
        if (loaded_plugin) |p| {
            if (p.hooks.plugin_suspend) |suspend_hook| {
                suspend_hook(p.context.?) catch |err| {
                    std.log.warn("Plugin suspend hook failed for {s}: {}", .{ plugin_name, err });
                };
            }
        }

        // Unload plugin
        try self.unloadPlugin(plugin_name);

        // Rediscover metadata (in case plugin file changed)
        try self.discoverSinglePluginMetadata(plugin_name);

        // Load plugin again
        try self.loadPlugin(plugin_name);

        // Restore plugin state if supported
        const reloaded_plugin = self.plugins.get(plugin_name);
        if (reloaded_plugin) |p| {
            if (p.hooks.plugin_resume) |resume_hook| {
                resume_hook(p.context.?) catch |err| {
                    std.log.warn("Plugin resume hook failed for {s}: {}", .{ plugin_name, err });
                };
            }
        }

        std.log.info("Plugin reloaded successfully: {s}", .{plugin_name});
    }

    /// Get plugin by name
    pub fn getPlugin(self: *Self, plugin_name: []const u8) ?*plugin.Plugin {
        return self.plugins.get(plugin_name);
    }

    /// List all loaded plugins
    pub fn listPlugins(self: *Self, allocator: Allocator) ![]plugin.PluginInfo {
        var plugin_list: ArrayList(plugin.PluginInfo) = .empty;
        defer plugin_list.deinit(allocator);

        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const p = entry.value_ptr.*;
            const info = try p.getInfo(allocator);
            try plugin_list.append(allocator, info);
        }

        return plugin_list.toOwnedSlice(allocator);
    }

    /// Get plugin statistics
    pub fn getPluginStats(self: *Self, plugin_name: []const u8) ?plugin.PluginStats {
        const p = self.plugins.get(plugin_name) orelse return null;
        return p.stats;
    }

    /// Enable/disable a plugin
    pub fn setPluginEnabled(self: *Self, plugin_name: []const u8, enabled: bool) !void {
        if (enabled) {
            if (!self.plugins.contains(plugin_name)) {
                try self.loadPlugin(plugin_name);
            }
        } else {
            if (self.plugins.contains(plugin_name)) {
                try self.unloadPlugin(plugin_name);
            }
        }
    }

    /// Shutdown all plugins gracefully
    pub fn shutdownAllPlugins(self: *Self) void {
        self.shutdown_requested = true;
        std.log.info("Shutting down all plugins...", .{});

        // Call pre-shutdown hooks
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const p = entry.value_ptr.*;
            if (p.hooks.pre_shutdown) |hook| {
                hook(p.context.?) catch |err| {
                    std.log.warn("Pre-shutdown hook failed for {s}: {}", .{ p.metadata.name, err });
                };
            }
        }

        // Unload plugins in reverse dependency order
        var plugin_names: ArrayList([]const u8) = .empty;
        defer plugin_names.deinit(self.allocator);

        iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            plugin_names.append(self.allocator, entry.key_ptr.*) catch continue;
        }

        // Reverse order for safe unloading
        std.mem.reverse([]const u8, plugin_names.items);

        for (plugin_names.items) |name| {
            self.unloadPlugin(name) catch |err| {
                std.log.err("Failed to unload plugin {s}: {}", .{ name, err });
            };
        }

        std.log.info("All plugins shut down", .{});
    }

    /// Health check for all plugins
    pub fn performHealthCheck(self: *Self) !std.StringHashMap(plugin.HealthStatus) {
        var health_status = std.StringHashMap(plugin.HealthStatus).init(self.allocator);
        
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const plugin_name = entry.key_ptr.*;
            const p = entry.value_ptr.*;
            
            const status = if (p.hooks.health_check) |hook|
                hook(p.context.?) catch plugin.HealthStatus.unhealthy
            else
                plugin.HealthStatus.unknown;
            
            try health_status.put(try self.allocator.dupe(u8, plugin_name), status);
            p.health = status;
        }
        
        return health_status;
    }

    // Private implementation methods

    fn createDirectories(self: *Self) !void {
        std.fs.cwd().makePath(self.config.plugin_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        std.fs.cwd().makePath(self.config.cache_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    fn discoverPluginMetadata(self: *Self) !void {
        const plugin_dir = std.fs.openDirAbsolute(self.config.plugin_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("Plugin directory not found: {s}", .{self.config.plugin_dir});
                return;
            },
            else => return err,
        };
        defer plugin_dir.close();

        var iterator = plugin_dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".nexcage-plugin")) {
                self.discoverSinglePluginMetadata(entry.name) catch |err| {
                    std.log.err("Failed to discover plugin {s}: {}", .{ entry.name, err });
                };
            }
        }
    }

    fn discoverSinglePluginMetadata(self: *Self, filename: []const u8) !void {
        const plugin_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config.plugin_dir, filename });
        defer self.allocator.free(plugin_path);

        // Validate plugin file size
        const file = try std.fs.openFileAbsolute(plugin_path, .{});
        defer file.close();
        
        const file_size = try file.getEndPos();
        if (file_size > self.config.max_plugin_size_mb * 1024 * 1024) {
            std.log.err("Plugin file too large: {s} ({} MB)", .{ filename, file_size / (1024 * 1024) });
            return PluginManagerError.SecurityViolation;
        }

        // Validate plugin signature if required
        if (self.config.require_signatures) {
            try self.validatePluginSignature(plugin_path);
        }

        // Load plugin metadata
        const metadata = try self.loadPluginMetadata(plugin_path);
        errdefer metadata.deinit(self.allocator);

        // Validate metadata
        if (!metadata.validate()) {
            std.log.err("Invalid plugin metadata: {s}", .{filename});
            return PluginManagerError.InvalidConfiguration;
        }

        // Store metadata
        try self.plugin_metadata.put(try self.allocator.dupe(u8, metadata.name), metadata);

        std.log.debug("Discovered plugin: {s} v{any}", .{ metadata.name, metadata.version });
    }

    fn resolveDependencies(self: *Self) !void {
        // Build dependency graph and determine load order
        var metadata_iterator = self.plugin_metadata.iterator();
        while (metadata_iterator.next()) |entry| {
            const metadata = entry.value_ptr.*;
            
            var dependencies: ArrayList(PluginDependency) = .empty;
            defer dependencies.deinit(self.allocator);

            for (metadata.dependencies) |dep_name| {
                // For now, assume all dependencies require exact version match
                // In a real implementation, this would parse version requirements
                const dep_metadata = self.plugin_metadata.get(dep_name) orelse {
                    std.log.err("Missing dependency {s} for plugin {s}", .{ dep_name, metadata.name });
                    return PluginManagerError.DependencyMissing;
                };

                try dependencies.append(self.allocator, PluginDependency{
                    .name = try self.allocator.dupe(u8, dep_name),
                    .version_requirement = dep_metadata.version,
                });
            }

            try self.plugin_load_order.append(self.allocator, PluginLoadOrder{
                .plugin_name = try self.allocator.dupe(u8, metadata.name),
                .dependencies = try dependencies.toOwnedSlice(self.allocator),
            });
        }

        // Sort by dependency order (topological sort)
        // For simplicity, we'll use a basic sort here
        // A real implementation would use a proper topological sort algorithm
        std.sort.pdq(PluginLoadOrder, self.plugin_load_order.items, {}, compareLoadOrder);
    }

    fn compareLoadOrder(ctx: void, a: PluginLoadOrder, b: PluginLoadOrder) bool {
        _ = ctx;
        // Plugins with fewer dependencies load first
        return a.dependencies.len < b.dependencies.len;
    }

    fn loadPluginsInOrder(self: *Self) !void {
        for (self.plugin_load_order.items) |load_info| {
            self.loadPlugin(load_info.plugin_name) catch |err| {
                std.log.err("Failed to load plugin {s}: {}", .{ load_info.plugin_name, err });
                // Continue loading other plugins
            };
        }
    }

    fn validateDependencies(self: *Self, dependencies: []const []const u8) !void {
        for (dependencies) |dep_name| {
            if (!self.plugins.contains(dep_name)) {
                std.log.err("Unloaded dependency: {s}", .{dep_name});
                return PluginManagerError.DependencyMissing;
            }
        }
    }

    fn loadPluginFromMetadata(self: *Self, metadata: plugin.PluginMetadata) !*plugin.Plugin {
        const p = try plugin.Plugin.init(self.allocator, metadata);
        errdefer p.deinit(self.allocator);

        // TODO: Load actual plugin dynamic library here
        // For now, we create a basic plugin structure

        return p;
    }

    fn createPluginContext(self: *Self, p: *plugin.Plugin) !*PluginContext {
        const ctx = try PluginContext.init(self.allocator, p.metadata.name);
        // Security sandbox integration would be added here
        _ = self.security_sandbox;
        return ctx;
    }

    fn registerPluginWithSubsystems(self: *Self, p: *plugin.Plugin) !void {
        // Register with hook system
        if (self.hook_system) |hook_sys| {
            // Register plugin lifecycle hooks
            if (p.hooks.init) |init_hook| {
                try hook_sys.registerHook(
                    p.metadata.name,
                    hooks.SystemHooks.PLUGIN_LOADED,
                    @ptrCast(init_hook),
                    .normal,
                    5000
                );
            }
        }

        // Allocate resources
        if (self.resource_manager) |rm| {
            try rm.allocateResources(p.metadata.name, p.metadata.resource_requirements);
        }
    }

    fn unregisterPluginFromSubsystems(self: *Self, p: *plugin.Plugin) void {
        // Unregister from hook system
        if (self.hook_system) |hook_sys| {
            hook_sys.unregisterPlugin(p.metadata.name);
        }
        
        // Deallocate resources
        if (self.resource_manager) |rm| {
            rm.deallocateResources(p.metadata.name) catch |err| {
                std.log.warn("Failed to deallocate resources for {s}: {}", .{ p.metadata.name, err });
            };
        }
    }

    fn hasReverseDependencies(self: *Self, plugin_name: []const u8) !bool {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const p = entry.value_ptr.*;
            for (p.metadata.dependencies) |dep| {
                if (std.mem.eql(u8, dep, plugin_name)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn validatePluginSignature(self: *Self, plugin_path: []const u8) !void {
        // TODO: Implement cryptographic signature verification
        _ = self;
        _ = plugin_path;
        std.log.debug("Plugin signature validation (not implemented)", .{});
    }

    fn loadPluginMetadata(self: *Self, plugin_path: []const u8) !plugin.PluginMetadata {
        // TODO: Implement metadata loading from plugin file
        // For now, return dummy metadata
        _ = plugin_path;
        
        return plugin.PluginMetadata{
            .name = try self.allocator.dupe(u8, "example-plugin"),
            .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
            .description = try self.allocator.dupe(u8, "Example plugin"),
            .api_version = 1,
            .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
            .dependencies = &[_][]const u8{},
            .capabilities = &[_]plugin.Capability{},
            .resource_requirements = plugin.ResourceRequirements{},
        };
    }

    fn cleanupPlugins(self: *Self) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const p = entry.value_ptr.*;
            p.deinit(self.allocator);
        }
    }
};

/// Security sandbox for plugin isolation
const SecuritySandbox = struct {
    const Self = @This();
    
    allocator: Allocator,
    config: PluginManagerConfig,
    
    pub fn init(allocator: Allocator, config: PluginManagerConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = config,
        };
        std.log.info("Security sandbox initialized", .{});
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};

/// Resource manager for plugin resource allocation
const ResourceManager = struct {
    const Self = @This();
    
    allocator: Allocator,
    config: PluginManagerConfig,
    allocated_resources: std.StringHashMap(plugin.ResourceRequirements),
    
    pub fn init(allocator: Allocator, config: PluginManagerConfig) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = config,
            .allocated_resources = std.StringHashMap(plugin.ResourceRequirements).init(allocator),
        };
        std.log.info("Resource manager initialized", .{});
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.allocated_resources.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.allocated_resources.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn allocateResources(self: *Self, plugin_name: []const u8, requirements: plugin.ResourceRequirements) !void {
        const name_copy = try self.allocator.dupe(u8, plugin_name);
        try self.allocated_resources.put(name_copy, requirements);
        std.log.info("Allocated resources for plugin: {s}", .{plugin_name});
    }
    
    pub fn deallocateResources(self: *Self, plugin_name: []const u8) !void {
        if (self.allocated_resources.fetchRemove(plugin_name)) |kv| {
            self.allocator.free(kv.key);
            std.log.info("Deallocated resources for plugin: {s}", .{plugin_name});
        }
    }
};

const PluginContext = plugin_context.PluginContext;

/// Test suite
const testing = std.testing;

test "PluginManagerConfig validation" {
    const valid_config = PluginManagerConfig{
        .max_plugins = 50,
        .memory_limit_mb = 256,
        .cpu_limit_percent = 25,
        .plugin_timeout_seconds = 60,
        .max_plugin_size_mb = 50,
    };
    try testing.expect(valid_config.validate());

    const invalid_config = PluginManagerConfig{
        .max_plugins = 0, // Invalid
        .memory_limit_mb = 256,
        .cpu_limit_percent = 25,
        .plugin_timeout_seconds = 60,
        .max_plugin_size_mb = 50,
    };
    try testing.expect(!invalid_config.validate());
}

test "Plugin manager basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a temp directory for testing
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const plugin_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(plugin_dir_path);

    const config = PluginManagerConfig{
        .plugin_dir = plugin_dir_path,
        .cache_dir = plugin_dir_path,
        .auto_load_plugins = false, // Disable auto-loading for test
        .sandbox_enabled = false, // Disable sandbox for simple test
    };

    const manager = try PluginManager.init(allocator, config);
    defer manager.deinit();

    // Test that manager initializes correctly
    try testing.expect(manager.plugins.count() == 0);
    try testing.expect(!manager.shutdown_requested);
}

test "Plugin registration and deregistration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a temp directory for testing
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const plugin_dir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(plugin_dir_path);

    const config = PluginManagerConfig{
        .plugin_dir = plugin_dir_path,
        .cache_dir = plugin_dir_path,
        .auto_load_plugins = false,
        .sandbox_enabled = false,
    };

    const manager = try PluginManager.init(allocator, config);
    defer manager.deinit();

    // Create a test plugin metadata
    const dependencies = try allocator.alloc([]const u8, 0);
    const capabilities = try allocator.alloc(plugin.Capability, 1);
    capabilities[0] = .logging;
    
    const test_metadata = plugin.PluginMetadata{
        .name = try allocator.dupe(u8, "test-plugin"),
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = try allocator.dupe(u8, "Test plugin for manager"),
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = dependencies,
        .capabilities = capabilities,
        .resource_requirements = plugin.ResourceRequirements{},
    };

    // Store the metadata in the manager (manager will take ownership)
    try manager.plugin_metadata.put(try allocator.dupe(u8, "test-plugin"), test_metadata);

    // Test plugin loading
    try manager.loadPlugin("test-plugin");
    try testing.expect(manager.plugins.count() == 1);
    
    const loaded_plugin = manager.getPlugin("test-plugin");
    try testing.expect(loaded_plugin != null);
    try testing.expect(loaded_plugin.?.status == .loaded);

    // Test plugin unloading
    try manager.unloadPlugin("test-plugin");
    try testing.expect(manager.plugins.count() == 0);
    try testing.expect(manager.getPlugin("test-plugin") == null);
}