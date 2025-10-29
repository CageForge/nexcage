# NexCage Plugin System Architecture

## Overview

This document provides a comprehensive architectural design for implementing a robust, secure, and extensible plugin system in NexCage. The plugin system will enable runtime extensions, custom backends, CLI commands, and integrations while maintaining security, performance, and stability.

## Design Principles

### 1. Security First
- Sandboxed plugin execution
- Capability-based security model
- Plugin signature verification
- Resource limits and isolation

### 2. Performance Oriented
- Lazy loading of plugins
- Hot-reload capabilities
- Minimal runtime overhead
- Memory-efficient plugin management

### 3. Developer Friendly
- Simple plugin API
- Rich development tools
- Comprehensive documentation
- Easy debugging and testing

### 4. Backward Compatibility
- Versioned plugin API
- Graceful degradation
- Migration assistance
- Legacy plugin support

---

## Core Architecture

### Plugin System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    NexCage Core                             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────── │
│  │ Plugin Manager  │  │  Hook System    │  │ Security       │
│  │                 │  │                 │  │ Sandbox        │
│  │ • Registration  │  │ • Lifecycle     │  │                │
│  │ • Discovery     │  │ • Events        │  │ • Capabilities │
│  │ • Lifecycle     │  │ • Callbacks     │  │ • Isolation    │
│  │ • Dependencies  │  │ • Priorities    │  │ • Validation   │
│  └─────────────────┘  └─────────────────┘  └─────────────── │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────── │
│  │ Plugin Registry │  │ Resource Mgmt   │  │ Communication  │
│  │                 │  │                 │  │ Bridge         │
│  │ • Metadata      │  │ • Memory Pools  │  │                │
│  │ • Versioning    │  │ • Limits        │  │ • IPC          │
│  │ • Dependencies  │  │ • Cleanup       │  │ • Serialization│
│  │ • Capabilities  │  │ • Monitoring    │  │ • Protocol     │
│  └─────────────────┘  └─────────────────┘  └─────────────── │
└─────────────────────────────────────────────────────────────┘
```

### Plugin Types

1. **Backend Plugins** - Custom container runtimes
2. **CLI Plugins** - Additional commands and subcommands
3. **Integration Plugins** - External service connectors
4. **Monitoring Plugins** - Metrics, logging, and observability
5. **Security Plugins** - Authentication, authorization, auditing
6. **Storage Plugins** - Custom storage backends
7. **Network Plugins** - Custom networking solutions

---

## Implementation Details

### 1. Plugin Manager

**File:** `src/core/plugin_manager.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// Plugin loading and runtime errors
pub const PluginError = error{
    PluginNotFound,
    IncompatibleVersion,
    InitializationFailed,
    SecurityViolation,
    DependencyMissing,
    ResourceExhausted,
    InvalidSignature,
};

/// Plugin API version for compatibility checking
pub const PLUGIN_API_VERSION: u32 = 1;

/// Plugin manager handles the complete lifecycle of plugins
pub const PluginManager = struct {
    const Self = @This();

    allocator: Allocator,
    plugins: HashMap([]const u8, *Plugin),
    plugin_registry: *PluginRegistry,
    hook_system: *HookSystem,
    security_sandbox: *SecuritySandbox,
    resource_manager: *ResourceManager,
    config: PluginManagerConfig,

    pub const PluginManagerConfig = struct {
        plugin_dir: []const u8 = "/etc/nexcage/plugins",
        max_plugins: u32 = 100,
        enable_hot_reload: bool = true,
        require_signatures: bool = true,
        sandbox_enabled: bool = true,
        memory_limit_mb: u32 = 512,
        cpu_limit_percent: u32 = 10,
    };

    pub fn init(allocator: Allocator, config: PluginManagerConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .plugins = HashMap([]const u8, *Plugin).init(allocator),
            .plugin_registry = try PluginRegistry.init(allocator),
            .hook_system = try HookSystem.init(allocator),
            .security_sandbox = try SecuritySandbox.init(allocator, config.sandbox_enabled),
            .resource_manager = try ResourceManager.init(allocator, config),
            .config = config,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        // Unload all plugins
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            self.unloadPlugin(entry.key_ptr.*) catch {};
        }

        self.plugins.deinit();
        self.plugin_registry.deinit();
        self.hook_system.deinit();
        self.security_sandbox.deinit();
        self.resource_manager.deinit();
        self.allocator.destroy(self);
    }

    /// Discover and register all plugins in the plugin directory
    pub fn discoverPlugins(self: *Self) !void {
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
                self.registerPluginFromFile(entry.name) catch |err| {
                    std.log.err("Failed to register plugin {s}: {}", .{ entry.name, err });
                };
            }
        }
    }

    /// Register a plugin from a file
    pub fn registerPluginFromFile(self: *Self, filename: []const u8) !void {
        const plugin_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.config.plugin_dir, filename });
        defer self.allocator.free(plugin_path);

        // Validate plugin signature if required
        if (self.config.require_signatures) {
            try self.validatePluginSignature(plugin_path);
        }

        // Load plugin metadata
        const metadata = try self.loadPluginMetadata(plugin_path);
        defer metadata.deinit(self.allocator);

        // Check version compatibility
        if (metadata.api_version != PLUGIN_API_VERSION) {
            return PluginError.IncompatibleVersion;
        }

        // Check dependencies
        try self.validateDependencies(metadata.dependencies);

        // Create plugin instance
        const plugin = try self.loadPlugin(plugin_path, metadata);
        errdefer plugin.deinit();

        // Register with plugin registry
        try self.plugin_registry.register(metadata.name, plugin);

        // Store in active plugins map
        try self.plugins.put(try self.allocator.dupe(u8, metadata.name), plugin);

        std.log.info("Plugin registered: {s} v{}", .{ metadata.name, metadata.version });
    }

    /// Load and initialize a plugin
    fn loadPlugin(self: *Self, plugin_path: []const u8, metadata: PluginMetadata) !*Plugin {
        // Create sandbox environment for the plugin
        const sandbox = try self.security_sandbox.createSandbox(metadata.name, metadata.capabilities);
        errdefer sandbox.destroy();

        // Allocate resources for the plugin
        const resources = try self.resource_manager.allocateResources(metadata.name, metadata.resource_requirements);
        errdefer self.resource_manager.deallocateResources(metadata.name);

        // Load the plugin dynamic library
        const lib = std.DynLib.open(plugin_path) catch |err| {
            std.log.err("Failed to load plugin library {s}: {}", .{ plugin_path, err });
            return PluginError.InitializationFailed;
        };
        errdefer lib.close();

        // Get plugin entry point
        const plugin_entry = lib.lookup(*const fn() PluginError!*Plugin, "nexcage_plugin_entry") orelse {
            std.log.err("Plugin entry point not found in {s}", .{plugin_path});
            return PluginError.InitializationFailed;
        };

        // Initialize the plugin
        const plugin = plugin_entry() catch |err| {
            std.log.err("Plugin initialization failed for {s}: {}", .{ metadata.name, err });
            return PluginError.InitializationFailed;
        };

        // Set up plugin context
        plugin.context = PluginContext{
            .allocator = resources.allocator,
            .sandbox = sandbox,
            .hook_system = self.hook_system,
            .manager = self,
            .metadata = metadata,
        };

        // Call plugin initialization hook
        if (plugin.hooks.init) |init_hook| {
            init_hook(&plugin.context) catch |err| {
                std.log.err("Plugin init hook failed for {s}: {}", .{ metadata.name, err });
                return PluginError.InitializationFailed;
            };
        }

        return plugin;
    }

    /// Unload a plugin
    pub fn unloadPlugin(self: *Self, plugin_name: []const u8) !void {
        const plugin = self.plugins.get(plugin_name) orelse return PluginError.PluginNotFound;

        // Call plugin cleanup hook
        if (plugin.hooks.deinit) |deinit_hook| {
            deinit_hook(&plugin.context);
        }

        // Remove from registry
        try self.plugin_registry.unregister(plugin_name);

        // Cleanup resources
        self.resource_manager.deallocateResources(plugin_name) catch {};

        // Destroy sandbox
        plugin.context.sandbox.destroy();

        // Remove from active plugins
        _ = self.plugins.remove(plugin_name);

        plugin.deinit();

        std.log.info("Plugin unloaded: {s}", .{plugin_name});
    }

    /// Get a plugin by name
    pub fn getPlugin(self: *Self, plugin_name: []const u8) ?*Plugin {
        return self.plugins.get(plugin_name);
    }

    /// List all loaded plugins
    pub fn listPlugins(self: *Self, allocator: Allocator) ![]PluginInfo {
        var plugin_list = ArrayList(PluginInfo).init(allocator);
        errdefer plugin_list.deinit();

        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            const plugin = entry.value_ptr.*;
            try plugin_list.append(PluginInfo{
                .name = try allocator.dupe(u8, plugin.context.metadata.name),
                .version = plugin.context.metadata.version,
                .description = try allocator.dupe(u8, plugin.context.metadata.description),
                .capabilities = try allocator.dupe(Capability, plugin.context.metadata.capabilities),
                .status = .loaded,
            });
        }

        return plugin_list.toOwnedSlice();
    }

    /// Enable hot reload for a plugin
    pub fn enableHotReload(self: *Self, plugin_name: []const u8) !void {
        if (!self.config.enable_hot_reload) {
            return error.HotReloadDisabled;
        }

        // Implementation for file watching and automatic reload
        // This would use inotify on Linux, kqueue on BSD, ReadDirectoryChangesW on Windows
        _ = self;
        _ = plugin_name;
        // TODO: Implement file watching
    }

    /// Validate plugin signature
    fn validatePluginSignature(self: *Self, plugin_path: []const u8) !void {
        // Implementation for cryptographic signature verification
        _ = self;
        _ = plugin_path;
        // TODO: Implement signature validation using libsodium or similar
    }

    /// Load plugin metadata from file
    fn loadPluginMetadata(self: *Self, plugin_path: []const u8) !PluginMetadata {
        _ = self;
        _ = plugin_path;
        // TODO: Implement metadata parsing from plugin file
        return PluginMetadata{
            .name = "example",
            .version = SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
            .description = "Example plugin",
            .api_version = PLUGIN_API_VERSION,
            .dependencies = &[_][]const u8{},
            .capabilities = &[_]Capability{},
            .resource_requirements = ResourceRequirements{},
        };
    }

    /// Validate plugin dependencies
    fn validateDependencies(self: *Self, dependencies: []const []const u8) !void {
        for (dependencies) |dep| {
            if (self.plugins.get(dep) == null) {
                std.log.err("Missing dependency: {s}", .{dep});
                return PluginError.DependencyMissing;
            }
        }
    }
};
```

### 2. Plugin Interface

**File:** `src/core/plugin.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Semantic version structure
pub const SemanticVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn format(
        self: SemanticVersion,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        return std.fmt.format(writer, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
    }
};

/// Plugin capabilities define what the plugin can access
pub const Capability = enum {
    // File system access
    filesystem_read,
    filesystem_write,
    filesystem_execute,

    // Network access
    network_client,
    network_server,
    network_raw,

    // Process management
    process_spawn,
    process_signal,
    process_ptrace,

    // System information
    system_info,
    system_metrics,

    // Container operations
    container_create,
    container_start,
    container_stop,
    container_delete,
    container_exec,

    // Host integration
    host_command,
    host_mount,
    host_device,

    // Configuration access
    config_read,
    config_write,

    // Logging and metrics
    logging,
    metrics,
    tracing,
};

/// Resource requirements for plugins
pub const ResourceRequirements = struct {
    max_memory_mb: u32 = 64,
    max_cpu_percent: u32 = 5,
    max_file_descriptors: u32 = 100,
    max_threads: u32 = 10,
    timeout_seconds: u32 = 30,
};

/// Plugin metadata
pub const PluginMetadata = struct {
    name: []const u8,
    version: SemanticVersion,
    description: []const u8,
    author: []const u8 = "",
    homepage: []const u8 = "",
    api_version: u32,
    dependencies: []const []const u8,
    capabilities: []const Capability,
    resource_requirements: ResourceRequirements,

    pub fn deinit(self: *PluginMetadata, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        if (self.author.len > 0) allocator.free(self.author);
        if (self.homepage.len > 0) allocator.free(self.homepage);
        allocator.free(self.dependencies);
        allocator.free(self.capabilities);
    }
};

/// Plugin status
pub const PluginStatus = enum {
    unloaded,
    loading,
    loaded,
    error_state,
    disabled,
};

/// Plugin information for listing
pub const PluginInfo = struct {
    name: []const u8,
    version: SemanticVersion,
    description: []const u8,
    capabilities: []const Capability,
    status: PluginStatus,

    pub fn deinit(self: *PluginInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.capabilities);
    }
};

/// Plugin context provided to plugins at runtime
pub const PluginContext = struct {
    allocator: Allocator,
    sandbox: *SecuritySandbox,
    hook_system: *HookSystem,
    manager: *PluginManager,
    metadata: PluginMetadata,

    /// Get core configuration
    pub fn getConfig(self: *PluginContext) *const core.Config {
        return &self.manager.core_config;
    }

    /// Log a message from the plugin
    pub fn log(self: *PluginContext, level: core.LogLevel, comptime format: []const u8, args: anytype) void {
        self.manager.logger.logf(level, "[Plugin:{s}] " ++ format, .{self.metadata.name} ++ args);
    }

    /// Register a hook
    pub fn registerHook(self: *PluginContext, hook_name: []const u8, callback: HookCallback) !void {
        try self.hook_system.registerHook(self.metadata.name, hook_name, callback);
    }

    /// Execute a system command (requires host_command capability)
    pub fn executeCommand(self: *PluginContext, args: []const []const u8) !CommandResult {
        if (!self.hasCapability(.host_command)) {
            return error.InsufficientCapabilities;
        }

        return self.sandbox.executeCommand(args);
    }

    /// Check if plugin has a specific capability
    pub fn hasCapability(self: *PluginContext, capability: Capability) bool {
        for (self.metadata.capabilities) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }
};

/// Plugin lifecycle hooks
pub const PluginHooks = struct {
    /// Called when plugin is loaded
    init: ?*const fn(*PluginContext) PluginError!void = null,

    /// Called when plugin is unloaded
    deinit: ?*const fn(*PluginContext) void = null,

    /// Called when configuration is reloaded
    config_reload: ?*const fn(*PluginContext) PluginError!void = null,

    /// Called for health checks
    health_check: ?*const fn(*PluginContext) PluginError!HealthStatus = null,
};

/// Plugin extension interfaces
pub const PluginExtensions = struct {
    /// Backend extension
    backend: ?BackendExtension = null,

    /// CLI command extension
    cli_command: ?CLICommandExtension = null,

    /// Integration extension
    integration: ?IntegrationExtension = null,

    /// Monitoring extension
    monitoring: ?MonitoringExtension = null,
};

/// Main plugin structure
pub const Plugin = struct {
    const Self = @This();

    /// Plugin metadata
    metadata: PluginMetadata,

    /// Plugin context (set by plugin manager)
    context: PluginContext = undefined,

    /// Lifecycle hooks
    hooks: PluginHooks,

    /// Plugin extensions
    extensions: PluginExtensions,

    /// Plugin-specific data
    data: ?*anyopaque = null,

    /// Initialize the plugin
    pub fn init(allocator: Allocator, metadata: PluginMetadata) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .metadata = metadata,
            .hooks = PluginHooks{},
            .extensions = PluginExtensions{},
        };
        return self;
    }

    /// Cleanup plugin resources
    pub fn deinit(self: *Self) void {
        self.context.allocator.destroy(self);
    }

    /// Get plugin information
    pub fn getInfo(self: *Self) PluginInfo {
        return PluginInfo{
            .name = self.metadata.name,
            .version = self.metadata.version,
            .description = self.metadata.description,
            .capabilities = self.metadata.capabilities,
            .status = .loaded,
        };
    }
};

/// Health status for plugins
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
    unknown,
};

/// Command execution result
pub const CommandResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    duration_ms: u64,

    pub fn deinit(self: *CommandResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

// Forward declarations for complex types
const PluginManager = @import("plugin_manager.zig").PluginManager;
const HookSystem = @import("hooks.zig").HookSystem;
const SecuritySandbox = @import("security_sandbox.zig").SecuritySandbox;
const HookCallback = @import("hooks.zig").HookCallback;
const BackendExtension = @import("extensions/backend.zig").BackendExtension;
const CLICommandExtension = @import("extensions/cli_command.zig").CLICommandExtension;
const IntegrationExtension = @import("extensions/integration.zig").IntegrationExtension;
const MonitoringExtension = @import("extensions/monitoring.zig").MonitoringExtension;
const core = @import("../core.zig");
const PluginError = @import("plugin_manager.zig").PluginError;
```

### 3. Hook System

**File:** `src/core/hooks.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;

/// Hook execution priority
pub const HookPriority = enum(u8) {
    critical = 0,
    high = 1,
    normal = 2,
    low = 3,
    background = 4,
};

/// Hook execution context
pub const HookContext = struct {
    hook_name: []const u8,
    plugin_name: []const u8,
    data: ?*anyopaque = null,
    metadata: HashMap([]const u8, []const u8),

    pub fn init(allocator: Allocator, hook_name: []const u8, plugin_name: []const u8) HookContext {
        return HookContext{
            .hook_name = hook_name,
            .plugin_name = plugin_name,
            .metadata = HashMap([]const u8, []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *HookContext) void {
        self.metadata.deinit();
    }

    pub fn setMetadata(self: *HookContext, key: []const u8, value: []const u8) !void {
        try self.metadata.put(key, value);
    }

    pub fn getMetadata(self: *HookContext, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

/// Hook callback function signature
pub const HookCallback = *const fn(*HookContext) anyerror!void;

/// Hook registration information
pub const HookRegistration = struct {
    plugin_name: []const u8,
    callback: HookCallback,
    priority: HookPriority,
    enabled: bool = true,
};

/// System lifecycle hooks
pub const SystemHooks = struct {
    pub const STARTUP = "system.startup";
    pub const SHUTDOWN = "system.shutdown";
    pub const CONFIG_RELOAD = "system.config_reload";
    pub const HEALTH_CHECK = "system.health_check";
};

/// Container lifecycle hooks
pub const ContainerHooks = struct {
    pub const PRE_CREATE = "container.pre_create";
    pub const POST_CREATE = "container.post_create";
    pub const PRE_START = "container.pre_start";
    pub const POST_START = "container.post_start";
    pub const PRE_STOP = "container.pre_stop";
    pub const POST_STOP = "container.post_stop";
    pub const PRE_DELETE = "container.pre_delete";
    pub const POST_DELETE = "container.post_delete";
};

/// CLI hooks
pub const CLIHooks = struct {
    pub const PRE_COMMAND = "cli.pre_command";
    pub const POST_COMMAND = "cli.post_command";
    pub const COMMAND_ERROR = "cli.command_error";
};

/// Hook system manages plugin hooks and their execution
pub const HookSystem = struct {
    const Self = @This();

    allocator: Allocator,
    hooks: HashMap([]const u8, ArrayList(HookRegistration)),
    hook_stats: HashMap([]const u8, HookStats),
    config: HookSystemConfig,

    pub const HookSystemConfig = struct {
        max_execution_time_ms: u32 = 5000,
        enable_async_execution: bool = true,
        max_concurrent_hooks: u32 = 10,
        enable_hook_metrics: bool = true,
    };

    pub const HookStats = struct {
        executions: u64 = 0,
        failures: u64 = 0,
        total_duration_ms: u64 = 0,
        last_execution: i64 = 0,
        avg_duration_ms: f64 = 0.0,
    };

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .hooks = HashMap([]const u8, ArrayList(HookRegistration)).init(allocator),
            .hook_stats = HashMap([]const u8, HookStats).init(allocator),
            .config = HookSystemConfig{},
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.hooks.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.hooks.deinit();
        self.hook_stats.deinit();
        self.allocator.destroy(self);
    }

    /// Register a hook callback
    pub fn registerHook(
        self: *Self,
        plugin_name: []const u8,
        hook_name: []const u8,
        callback: HookCallback,
        priority: HookPriority,
    ) !void {
        const registration = HookRegistration{
            .plugin_name = try self.allocator.dupe(u8, plugin_name),
            .callback = callback,
            .priority = priority,
        };

        var hook_list = self.hooks.get(hook_name) orelse blk: {
            const new_list = ArrayList(HookRegistration).init(self.allocator);
            try self.hooks.put(try self.allocator.dupe(u8, hook_name), new_list);
            break :blk self.hooks.getPtr(hook_name).?;
        };

        try hook_list.append(registration);

        // Sort by priority (critical first)
        std.sort.sort(HookRegistration, hook_list.items, {}, compareHookPriority);

        std.log.debug("Hook registered: {s} -> {s} (priority: {})", .{ plugin_name, hook_name, priority });
    }

    /// Unregister all hooks for a plugin
    pub fn unregisterPlugin(self: *Self, plugin_name: []const u8) void {
        var iterator = self.hooks.iterator();
        while (iterator.next()) |entry| {
            const hook_list = entry.value_ptr;
            var i: usize = 0;
            while (i < hook_list.items.len) {
                if (std.mem.eql(u8, hook_list.items[i].plugin_name, plugin_name)) {
                    self.allocator.free(hook_list.items[i].plugin_name);
                    _ = hook_list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Execute all hooks for a given hook name
    pub fn executeHooks(self: *Self, hook_name: []const u8, context: *HookContext) !void {
        const hook_list = self.hooks.get(hook_name) orelse return;

        const start_time = std.time.milliTimestamp();
        var successful_executions: u32 = 0;
        var failed_executions: u32 = 0;

        for (hook_list.items) |registration| {
            if (!registration.enabled) continue;

            const hook_start = std.time.milliTimestamp();

            // Execute hook with timeout
            const result = self.executeHookWithTimeout(registration, context);

            const hook_duration = std.time.milliTimestamp() - hook_start;

            switch (result) {
                .success => {
                    successful_executions += 1;
                    std.log.debug("Hook executed successfully: {s} -> {s} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        hook_duration,
                    });
                },
                .failure => |err| {
                    failed_executions += 1;
                    std.log.err("Hook execution failed: {s} -> {s}: {} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        err,
                        hook_duration,
                    });
                },
                .timeout => {
                    failed_executions += 1;
                    std.log.err("Hook execution timed out: {s} -> {s} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        hook_duration,
                    });
                },
            }

            // Update statistics
            if (self.config.enable_hook_metrics) {
                self.updateHookStats(hook_name, hook_duration, result == .success);
            }
        }

        const total_duration = std.time.milliTimestamp() - start_time;
        std.log.debug("Hook execution completed: {s} - {}/{} successful ({}ms total)", .{
            hook_name,
            successful_executions,
            successful_executions + failed_executions,
            total_duration,
        });
    }

    /// Execute hooks asynchronously
    pub fn executeHooksAsync(self: *Self, hook_name: []const u8, context: *HookContext) !void {
        if (!self.config.enable_async_execution) {
            return self.executeHooks(hook_name, context);
        }

        // TODO: Implement async execution using thread pool
        return self.executeHooks(hook_name, context);
    }

    /// Execute a single hook with timeout
    fn executeHookWithTimeout(
        self: *Self,
        registration: HookRegistration,
        context: *HookContext,
    ) HookExecutionResult {
        _ = self;

        // TODO: Implement proper timeout mechanism
        // For now, execute directly
        registration.callback(context) catch |err| {
            return HookExecutionResult{ .failure = err };
        };

        return HookExecutionResult.success;
    }

    /// Update hook execution statistics
    fn updateHookStats(self: *Self, hook_name: []const u8, duration_ms: i64, success: bool) void {
        var stats = self.hook_stats.get(hook_name) orelse HookStats{};

        stats.executions += 1;
        if (!success) stats.failures += 1;
        stats.total_duration_ms += @intCast(duration_ms);
        stats.last_execution = std.time.timestamp();
        stats.avg_duration_ms = @as(f64, @floatFromInt(stats.total_duration_ms)) / @as(f64, @floatFromInt(stats.executions));

        self.hook_stats.put(hook_name, stats) catch {};
    }

    /// Get hook execution statistics
    pub fn getHookStats(self: *Self, hook_name: []const u8) ?HookStats {
        return self.hook_stats.get(hook_name);
    }

    /// List all registered hooks
    pub fn listHooks(self: *Self, allocator: Allocator) ![]HookInfo {
        var hook_list = ArrayList(HookInfo).init(allocator);
        errdefer hook_list.deinit();

        var iterator = self.hooks.iterator();
        while (iterator.next()) |entry| {
            const hook_name = entry.key_ptr.*;
            const registrations = entry.value_ptr.*;

            for (registrations.items) |reg| {
                try hook_list.append(HookInfo{
                    .hook_name = try allocator.dupe(u8, hook_name),
                    .plugin_name = try allocator.dupe(u8, reg.plugin_name),
                    .priority = reg.priority,
                    .enabled = reg.enabled,
                });
            }
        }

        return hook_list.toOwnedSlice();
    }

    /// Enable/disable a specific hook
    pub fn setHookEnabled(self: *Self, hook_name: []const u8, plugin_name: []const u8, enabled: bool) !void {
        const hook_list = self.hooks.getPtr(hook_name) orelse return error.HookNotFound;

        for (hook_list.items) |*registration| {
            if (std.mem.eql(u8, registration.plugin_name, plugin_name)) {
                registration.enabled = enabled;
                std.log.info("Hook {s}:{s} {s}", .{ plugin_name, hook_name, if (enabled) "enabled" else "disabled" });
                return;
            }
        }

        return error.PluginNotFound;
    }

    fn compareHookPriority(context: void, a: HookRegistration, b: HookRegistration) bool {
        _ = context;
        return @intFromEnum(a.priority) < @intFromEnum(b.priority);
    }
};

/// Hook execution result
const HookExecutionResult = union(enum) {
    success: void,
    failure: anyerror,
    timeout: void,
};

/// Hook information for listing
pub const HookInfo = struct {
    hook_name: []const u8,
    plugin_name: []const u8,
    priority: HookPriority,
    enabled: bool,

    pub fn deinit(self: *HookInfo, allocator: Allocator) void {
        allocator.free(self.hook_name);
        allocator.free(self.plugin_name);
    }
};
```

### 4. Security Sandbox

**File:** `src/core/security_sandbox.zig`

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const plugin = @import("plugin.zig");

/// Security sandbox for plugin isolation
pub const SecuritySandbox = struct {
    const Self = @This();

    allocator: Allocator,
    sandboxes: HashMap([]const u8, *PluginSandbox),
    enabled: bool,
    config: SandboxConfig,

    pub const SandboxConfig = struct {
        enable_namespace_isolation: bool = true,
        enable_seccomp: bool = true,
        enable_cgroups: bool = true,
        enable_chroot: bool = false,
        temp_dir: []const u8 = "/tmp/nexcage-plugins",
        max_open_files: u32 = 1024,
        max_memory_mb: u32 = 512,
        max_cpu_percent: u32 = 10,
    };

    pub fn init(allocator: Allocator, enabled: bool) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .sandboxes = HashMap([]const u8, *PluginSandbox).init(allocator),
            .enabled = enabled,
            .config = SandboxConfig{},
        };

        if (enabled) {
            try self.initializeSandboxEnvironment();
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.sandboxes.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.destroy();
        }
        self.sandboxes.deinit();
        self.allocator.destroy(self);
    }

    /// Create a new sandbox for a plugin
    pub fn createSandbox(
        self: *Self,
        plugin_name: []const u8,
        capabilities: []const plugin.Capability,
    ) !*PluginSandbox {
        if (!self.enabled) {
            return try PluginSandbox.createNoop(self.allocator, plugin_name);
        }

        const sandbox = try PluginSandbox.create(
            self.allocator,
            plugin_name,
            capabilities,
            self.config,
        );

        try self.sandboxes.put(try self.allocator.dupe(u8, plugin_name), sandbox);

        std.log.debug("Sandbox created for plugin: {s}", .{plugin_name});
        return sandbox;
    }

    /// Destroy a sandbox
    pub fn destroySandbox(self: *Self, plugin_name: []const u8) void {
        if (self.sandboxes.get(plugin_name)) |sandbox| {
            sandbox.destroy();
            _ = self.sandboxes.remove(plugin_name);
            std.log.debug("Sandbox destroyed for plugin: {s}", .{plugin_name});
        }
    }

    /// Initialize the sandbox environment
    fn initializeSandboxEnvironment(self: *Self) !void {
        // Create temporary directory for plugin sandboxes
        std.fs.cwd().makePath(self.config.temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Set up cgroups if enabled
        if (self.config.enable_cgroups) {
            try self.setupCgroups();
        }

        std.log.info("Sandbox environment initialized");
    }

    /// Set up cgroups for plugin resource management
    fn setupCgroups(self: *Self) !void {
        _ = self;
        // TODO: Implement cgroups setup
        std.log.debug("Cgroups setup (not implemented)");
    }
};

/// Individual plugin sandbox
pub const PluginSandbox = struct {
    const Self = @This();

    allocator: Allocator,
    plugin_name: []const u8,
    capabilities: []const plugin.Capability,
    config: SecuritySandbox.SandboxConfig,
    sandbox_dir: []const u8,
    is_noop: bool,

    /// Create a real sandbox with isolation
    pub fn create(
        allocator: Allocator,
        plugin_name: []const u8,
        capabilities: []const plugin.Capability,
        config: SecuritySandbox.SandboxConfig,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const sandbox_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ config.temp_dir, plugin_name },
        );
        errdefer allocator.free(sandbox_dir);

        // Create sandbox directory
        try std.fs.cwd().makePath(sandbox_dir);

        self.* = Self{
            .allocator = allocator,
            .plugin_name = try allocator.dupe(u8, plugin_name),
            .capabilities = try allocator.dupe(plugin.Capability, capabilities),
            .config = config,
            .sandbox_dir = sandbox_dir,
            .is_noop = false,
        };

        try self.setupIsolation();

        return self;
    }

    /// Create a no-op sandbox (when sandboxing is disabled)
    pub fn createNoop(allocator: Allocator, plugin_name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .plugin_name = try allocator.dupe(u8, plugin_name),
            .capabilities = &[_]plugin.Capability{},
            .config = SecuritySandbox.SandboxConfig{},
            .sandbox_dir = "",
            .is_noop = true,
        };
        return self;
    }

    pub fn destroy(self: *Self) void {
        if (!self.is_noop) {
            self.cleanupIsolation();
            
            // Remove sandbox directory
            std.fs.cwd().deleteTree(self.sandbox_dir) catch |err| {
                std.log.warn("Failed to cleanup sandbox directory {s}: {}", .{ self.sandbox_dir, err });
            };
            
            self.allocator.free(self.sandbox_dir);
            self.allocator.free(self.capabilities);
        }
        
        self.allocator.free(self.plugin_name);
        self.allocator.destroy(self);
    }

    /// Execute a command within the sandbox
    pub fn executeCommand(self: *Self, args: []const []const u8) !plugin.CommandResult {
        if (self.is_noop) {
            return self.executeCommandUnsandboxed(args);
        }

        // Check if plugin has permission to execute commands
        if (!self.hasCapability(.host_command)) {
            return error.InsufficientCapabilities;
        }

        return self.executeCommandSandboxed(args);
    }

    /// Check if sandbox has a specific capability
    pub fn hasCapability(self: *Self, capability: plugin.Capability) bool {
        for (self.capabilities) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }

    /// Set up isolation mechanisms
    fn setupIsolation(self: *Self) !void {
        if (self.config.enable_namespace_isolation) {
            try self.setupNamespaces();
        }

        if (self.config.enable_seccomp) {
            try self.setupSeccomp();
        }

        if (self.config.enable_cgroups) {
            try self.setupPluginCgroups();
        }
    }

    /// Clean up isolation mechanisms
    fn cleanupIsolation(self: *Self) void {
        // TODO: Cleanup namespaces, seccomp, cgroups
        _ = self;
    }

    /// Set up Linux namespaces for isolation
    fn setupNamespaces(self: *Self) !void {
        _ = self;
        // TODO: Implement namespace setup using unshare()
        std.log.debug("Namespace isolation setup (not implemented)");
    }

    /// Set up seccomp filtering
    fn setupSeccomp(self: *Self) !void {
        _ = self;
        // TODO: Implement seccomp filtering based on capabilities
        std.log.debug("Seccomp filtering setup (not implemented)");
    }

    /// Set up cgroups for this specific plugin
    fn setupPluginCgroups(self: *Self) !void {
        _ = self;
        // TODO: Implement per-plugin cgroups
        std.log.debug("Plugin cgroups setup (not implemented)");
    }

    /// Execute command without sandboxing
    fn executeCommandUnsandboxed(self: *Self, args: []const []const u8) !plugin.CommandResult {
        const start_time = std.time.milliTimestamp();

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024, // 1MB limit
        });

        const end_time = std.time.milliTimestamp();

        return plugin.CommandResult{
            .exit_code = @intCast(result.term.Exited),
            .stdout = result.stdout,
            .stderr = result.stderr,
            .duration_ms = @intCast(end_time - start_time),
        };
    }

    /// Execute command with sandboxing
    fn executeCommandSandboxed(self: *Self, args: []const []const u8) !plugin.CommandResult {
        // TODO: Implement sandboxed command execution
        // This would involve setting up the sandbox environment and executing the command within it
        return self.executeCommandUnsandboxed(args);
    }
};
```

### 5. Plugin Extensions

**File:** `src/core/extensions/backend.zig`

```zig
const std = @import("std");
const core = @import("../../core.zig");

/// Backend extension interface for plugins
pub const BackendExtension = struct {
    const Self = @This();

    /// Extension metadata
    name: []const u8,
    description: []const u8,
    version: []const u8,

    /// Backend implementation
    impl: *const BackendImpl,

    /// Backend interface implementation
    pub const BackendImpl = struct {
        /// Create a container
        create: *const fn(*core.PluginContext, core.SandboxConfig) core.Error!void,

        /// Start a container
        start: *const fn(*core.PluginContext, []const u8) core.Error!void,

        /// Stop a container
        stop: *const fn(*core.PluginContext, []const u8) core.Error!void,

        /// Delete a container
        delete: *const fn(*core.PluginContext, []const u8) core.Error!void,

        /// List containers
        list: *const fn(*core.PluginContext, std.mem.Allocator) core.Error![]core.ContainerInfo,

        /// Get container info
        info: *const fn(*core.PluginContext, []const u8, std.mem.Allocator) core.Error!core.ContainerInfo,

        /// Execute command in container
        exec: *const fn(*core.PluginContext, []const u8, []const []const u8, std.mem.Allocator) core.Error!void,
    };

    pub fn init(name: []const u8, description: []const u8, version: []const u8, impl: *const BackendImpl) Self {
        return Self{
            .name = name,
            .description = description,
            .version = version,
            .impl = impl,
        };
    }
};
```

**File:** `src/core/extensions/cli_command.zig`

```zig
const std = @import("std");
const core = @import("../../core.zig");

/// CLI command extension for plugins
pub const CLICommandExtension = struct {
    const Self = @This();

    /// Command metadata
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    examples: []const []const u8,

    /// Command implementation
    impl: *const CommandImpl,

    /// Command interface implementation
    pub const CommandImpl = struct {
        /// Execute the command
        execute: *const fn(*core.PluginContext, core.RuntimeOptions, std.mem.Allocator) core.Error!void,

        /// Get command help
        help: *const fn(*core.PluginContext, std.mem.Allocator) core.Error![]const u8,

        /// Validate command arguments
        validate: *const fn(*core.PluginContext, []const []const u8) core.Error!void,

        /// Complete command arguments (for shell completion)
        complete: ?*const fn(*core.PluginContext, []const []const u8, std.mem.Allocator) core.Error![][]const u8 = null,
    };

    pub fn init(
        name: []const u8,
        description: []const u8,
        usage: []const u8,
        examples: []const []const u8,
        impl: *const CommandImpl,
    ) Self {
        return Self{
            .name = name,
            .description = description,
            .usage = usage,
            .examples = examples,
            .impl = impl,
        };
    }
};
```

---

## Plugin Development Guide

### Creating a Simple Plugin

**File:** `examples/plugins/hello_world/src/main.zig`

```zig
const std = @import("std");
const nexcage = @import("nexcage-plugin-api");

// Plugin metadata
const PLUGIN_METADATA = nexcage.PluginMetadata{
    .name = "hello-world",
    .version = nexcage.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "A simple hello world plugin",
    .author = "NexCage Team",
    .api_version = nexcage.PLUGIN_API_VERSION,
    .dependencies = &[_][]const u8{},
    .capabilities = &[_]nexcage.Capability{.logging},
    .resource_requirements = nexcage.ResourceRequirements{
        .max_memory_mb = 10,
        .max_cpu_percent = 1,
    },
};

var plugin_instance: ?*nexcage.Plugin = null;

/// Plugin entry point - called by NexCage when loading the plugin
export fn nexcage_plugin_entry() nexcage.PluginError!*nexcage.Plugin {
    const allocator = std.heap.c_allocator;
    
    const plugin = try nexcage.Plugin.init(allocator, PLUGIN_METADATA);
    
    // Set up plugin hooks
    plugin.hooks = nexcage.PluginHooks{
        .init = pluginInit,
        .deinit = pluginDeinit,
        .health_check = pluginHealthCheck,
    };
    
    // Set up CLI command extension
    plugin.extensions.cli_command = nexcage.CLICommandExtension.init(
        "hello",
        "Print a hello message",
        "nexcage hello [options]",
        &[_][]const u8{
            "nexcage hello",
            "nexcage hello --name World",
        },
        &hello_command_impl,
    );
    
    plugin_instance = plugin;
    return plugin;
}

/// Plugin initialization hook
fn pluginInit(context: *nexcage.PluginContext) nexcage.PluginError!void {
    context.log(.info, "Hello World plugin initialized!");
    
    // Register for system startup hook
    try context.registerHook(nexcage.SystemHooks.STARTUP, onSystemStartup);
}

/// Plugin cleanup hook
fn pluginDeinit(context: *nexcage.PluginContext) void {
    context.log(.info, "Hello World plugin shutting down!");
}

/// Plugin health check hook
fn pluginHealthCheck(context: *nexcage.PluginContext) nexcage.PluginError!nexcage.HealthStatus {
    _ = context;
    return .healthy;
}

/// System startup hook handler
fn onSystemStartup(hook_context: *nexcage.HookContext) anyerror!void {
    // Get plugin context from hook context
    const plugin_context = @ptrCast(*nexcage.PluginContext, @alignCast(@alignOf(nexcage.PluginContext), hook_context.data.?));
    plugin_context.log(.info, "System started - Hello from plugin!");
}

/// Hello command implementation
const hello_command_impl = nexcage.CLICommandExtension.CommandImpl{
    .execute = helloExecute,
    .help = helloHelp,
    .validate = helloValidate,
};

fn helloExecute(context: *nexcage.PluginContext, options: nexcage.RuntimeOptions, allocator: std.mem.Allocator) nexcage.PluginError!void {
    _ = allocator;
    
    const name = if (options.args != null and options.args.?.len > 0) 
        options.args.?[0] 
    else 
        "World";
    
    context.log(.info, "Hello, {s}!", .{name});
    std.debug.print("Hello, {s}!\n", .{name});
}

fn helloHelp(context: *nexcage.PluginContext, allocator: std.mem.Allocator) nexcage.PluginError![]const u8 {
    _ = context;
    return try std.fmt.allocPrint(allocator,
        \\Usage: nexcage hello [name]
        \\
        \\Print a hello message.
        \\
        \\Arguments:
        \\  name    Name to greet (default: World)
        \\
        \\Examples:
        \\  nexcage hello
        \\  nexcage hello Alice
    );
}

fn helloValidate(context: *nexcage.PluginContext, args: []const []const u8) nexcage.PluginError!void {
    _ = context;
    if (args.len > 1) {
        return nexcage.PluginError.InvalidInput;
    }
}
```

### Building the Plugin

**File:** `examples/plugins/hello_world/build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Plugin shared library
    const plugin_lib = b.addSharedLibrary(.{
        .name = "hello-world",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link NexCage plugin API
    plugin_lib.addIncludePath(b.path("../../../src"));
    
    // Set output name with plugin extension
    plugin_lib.setOutputPath("hello-world.nexcage-plugin");
    
    b.installArtifact(plugin_lib);
}
```

### Creating a Backend Plugin

**File:** `examples/plugins/custom_backend/src/main.zig`

```zig
const std = @import("std");
const nexcage = @import("nexcage-plugin-api");

const PLUGIN_METADATA = nexcage.PluginMetadata{
    .name = "custom-backend",
    .version = nexcage.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Custom container backend implementation",
    .api_version = nexcage.PLUGIN_API_VERSION,
    .dependencies = &[_][]const u8{},
    .capabilities = &[_]nexcage.Capability{
        .container_create,
        .container_start,
        .container_stop,
        .container_delete,
        .filesystem_read,
        .filesystem_write,
        .host_command,
    },
    .resource_requirements = nexcage.ResourceRequirements{
        .max_memory_mb = 100,
        .max_cpu_percent = 20,
    },
};

export fn nexcage_plugin_entry() nexcage.PluginError!*nexcage.Plugin {
    const allocator = std.heap.c_allocator;
    
    const plugin = try nexcage.Plugin.init(allocator, PLUGIN_METADATA);
    
    // Set up backend extension
    plugin.extensions.backend = nexcage.BackendExtension.init(
        "custom-backend",
        "Custom container backend with special features",
        "1.0.0",
        &backend_impl,
    );
    
    return plugin;
}

const backend_impl = nexcage.BackendExtension.BackendImpl{
    .create = backendCreate,
    .start = backendStart,
    .stop = backendStop,
    .delete = backendDelete,
    .list = backendList,
    .info = backendInfo,
    .exec = backendExec,
};

fn backendCreate(context: *nexcage.PluginContext, config: nexcage.SandboxConfig) nexcage.PluginError!void {
    context.log(.info, "Creating container with custom backend: {s}", .{config.name});
    
    // Custom container creation logic here
    const create_args = [_][]const u8{
        "custom-runtime",
        "create",
        "--name", config.name,
        "--image", config.image orelse "alpine:latest",
    };
    
    const result = try context.executeCommand(&create_args);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        context.log(.err, "Container creation failed: {s}", .{result.stderr});
        return nexcage.PluginError.RuntimeError;
    }
    
    context.log(.info, "Container created successfully: {s}", .{config.name});
}

fn backendStart(context: *nexcage.PluginContext, container_id: []const u8) nexcage.PluginError!void {
    context.log(.info, "Starting container: {s}", .{container_id});
    
    const start_args = [_][]const u8{
        "custom-runtime",
        "start",
        container_id,
    };
    
    const result = try context.executeCommand(&start_args);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        return nexcage.PluginError.RuntimeError;
    }
}

fn backendStop(context: *nexcage.PluginContext, container_id: []const u8) nexcage.PluginError!void {
    context.log(.info, "Stopping container: {s}", .{container_id});
    
    const stop_args = [_][]const u8{
        "custom-runtime",
        "stop",
        container_id,
    };
    
    const result = try context.executeCommand(&stop_args);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        return nexcage.PluginError.RuntimeError;
    }
}

fn backendDelete(context: *nexcage.PluginContext, container_id: []const u8) nexcage.PluginError!void {
    context.log(.info, "Deleting container: {s}", .{container_id});
    
    const delete_args = [_][]const u8{
        "custom-runtime",
        "delete",
        container_id,
    };
    
    const result = try context.executeCommand(&delete_args);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        return nexcage.PluginError.RuntimeError;
    }
}

fn backendList(context: *nexcage.PluginContext, allocator: std.mem.Allocator) nexcage.PluginError![]nexcage.ContainerInfo {
    const list_args = [_][]const u8{
        "custom-runtime",
        "list",
        "--format", "json",
    };
    
    const result = try context.executeCommand(&list_args);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        return nexcage.PluginError.RuntimeError;
    }
    
    // Parse JSON output and convert to ContainerInfo array
    // This is a simplified example
    var container_list = std.ArrayList(nexcage.ContainerInfo).init(allocator);
    
    // TODO: Implement proper JSON parsing
    try container_list.append(nexcage.ContainerInfo{
        .allocator = allocator,
        .id = try allocator.dupe(u8, "example-container"),
        .name = try allocator.dupe(u8, "example-container"),
        .status = try allocator.dupe(u8, "running"),
        .backend_type = try allocator.dupe(u8, "custom-backend"),
    });
    
    return container_list.toOwnedSlice();
}

fn backendInfo(context: *nexcage.PluginContext, container_id: []const u8, allocator: std.mem.Allocator) nexcage.PluginError!nexcage.ContainerInfo {
    _ = context;
    
    // TODO: Implement container info retrieval
    return nexcage.ContainerInfo{
        .allocator = allocator,
        .id = try allocator.dupe(u8, container_id),
        .name = try allocator.dupe(u8, container_id),
        .status = try allocator.dupe(u8, "running"),
        .backend_type = try allocator.dupe(u8, "custom-backend"),
    };
}

fn backendExec(context: *nexcage.PluginContext, container_id: []const u8, command: []const []const u8, allocator: std.mem.Allocator) nexcage.PluginError!void {
    _ = allocator;
    
    context.log(.info, "Executing command in container {s}: {s}", .{ container_id, command });
    
    var exec_args = std.ArrayList([]const u8).init(context.allocator);
    defer exec_args.deinit();
    
    try exec_args.appendSlice(&[_][]const u8{ "custom-runtime", "exec", container_id });
    try exec_args.appendSlice(command);
    
    const result = try context.executeCommand(exec_args.items);
    defer result.deinit(context.allocator);
    
    if (result.exit_code != 0) {
        return nexcage.PluginError.RuntimeError;
    }
}
```

---

## Plugin Configuration

### Plugin Configuration File

**File:** `/etc/nexcage/plugins/config.json`

```json
{
  "plugin_manager": {
    "plugin_dir": "/etc/nexcage/plugins",
    "max_plugins": 100,
    "enable_hot_reload": true,
    "require_signatures": true,
    "sandbox_enabled": true,
    "memory_limit_mb": 512,
    "cpu_limit_percent": 10
  },
  "plugins": {
    "hello-world": {
      "enabled": true,
      "config": {
        "default_name": "NexCage User"
      }
    },
    "custom-backend": {
      "enabled": true,
      "config": {
        "runtime_path": "/usr/local/bin/custom-runtime",
        "default_image": "alpine:latest"
      }
    },
    "monitoring-plugin": {
      "enabled": false,
      "config": {
        "metrics_endpoint": "http://prometheus:9090",
        "collection_interval": 30
      }
    }
  },
  "hooks": {
    "system.startup": {
      "enabled": true,
      "timeout_ms": 5000
    },
    "container.pre_create": {
      "enabled": true,
      "timeout_ms": 10000
    }
  },
  "security": {
    "allowed_capabilities": [
      "filesystem_read",
      "filesystem_write",
      "container_create",
      "container_start",
      "container_stop",
      "logging",
      "metrics"
    ],
    "denied_capabilities": [
      "host_device",
      "process_ptrace"
    ]
  }
}
```

---

## Plugin Registry

### Plugin Manifest Format

**File:** `plugin-manifest.json`

```json
{
  "name": "custom-backend",
  "version": "1.0.0",
  "description": "Custom container backend with special features",
  "author": "Example Developer",
  "homepage": "https://github.com/example/nexcage-custom-backend",
  "license": "MIT",
  "api_version": 1,
  "nexcage_version": ">=0.7.0",
  "dependencies": [],
  "capabilities": [
    "container_create",
    "container_start",
    "container_stop",
    "container_delete",
    "filesystem_read",
    "filesystem_write",
    "host_command"
  ],
  "resource_requirements": {
    "max_memory_mb": 100,
    "max_cpu_percent": 20,
    "max_file_descriptors": 200,
    "max_threads": 5,
    "timeout_seconds": 60
  },
  "extensions": [
    "backend"
  ],
  "hooks": [
    "system.startup",
    "container.pre_create",
    "container.post_create"
  ],
  "configuration_schema": {
    "type": "object",
    "properties": {
      "runtime_path": {
        "type": "string",
        "description": "Path to the custom runtime binary"
      },
      "default_image": {
        "type": "string",
        "description": "Default container image to use"
      }
    },
    "required": ["runtime_path"]
  },
  "files": {
    "binary": "custom-backend.nexcage-plugin",
    "checksum": "sha256:abc123...",
    "signature": "signature.sig"
  }
}
```

---

## Implementation Timeline

### Phase 1: Core Infrastructure (Week 1-2)
1. Implement `PluginManager` basic functionality
2. Create `Plugin` interface and basic types
3. Implement simple hook system
4. Add plugin discovery and registration

### Phase 2: Security & Isolation (Week 3-4)
1. Implement `SecuritySandbox` with basic isolation
2. Add capability-based security model
3. Implement resource limits and monitoring
4. Add plugin signature verification

### Phase 3: Extensions System (Week 5-6)
1. Implement backend plugin extensions
2. Add CLI command extensions
3. Create integration plugin framework
4. Implement monitoring extensions

### Phase 4: Advanced Features (Week 7-8)
1. Add hot-reload capabilities
2. Implement plugin dependency management
3. Add comprehensive error handling
4. Create plugin development tools

### Phase 5: Testing & Documentation (Week 9-10)
1. Comprehensive testing suite
2. Example plugins
3. Developer documentation
4. Security audit and hardening

---

## Security Considerations

### Plugin Validation
- Cryptographic signature verification
- Capability validation against manifest
- Resource requirement validation
- API version compatibility checks

### Runtime Security
- Sandboxed execution environments
- Capability-based access control
- Resource limits enforcement
- System call filtering (seccomp)

### Plugin Communication
- Secure IPC mechanisms
- Input validation and sanitization
- Rate limiting and DoS protection
- Audit logging for security events

---

## Performance Considerations

### Plugin Loading
- Lazy loading to reduce startup time
- Plugin caching to avoid repeated loads
- Dependency resolution optimization
- Memory pool allocation for plugins

### Hook Execution
- Asynchronous hook execution where possible
- Timeout mechanisms to prevent hangs
- Priority-based execution ordering
- Performance metrics and monitoring

### Resource Management
- Memory pool allocation
- Resource cleanup on plugin unload
- Garbage collection for long-running plugins
- Resource usage monitoring and alerting

---

## Conclusion

This plugin system architecture provides a robust, secure, and extensible foundation for extending NexCage's functionality. The design balances security, performance, and developer experience while maintaining the core stability of the container runtime.

Key benefits:
- **Security**: Sandboxed execution and capability-based security
- **Performance**: Efficient resource management and lazy loading
- **Extensibility**: Multiple extension points and rich API
- **Developer Experience**: Simple API and comprehensive tooling
- **Maintainability**: Clean architecture and comprehensive testing

The implementation can be done incrementally, allowing for early feedback and iteration while building toward the full vision of a pluggable container runtime ecosystem.