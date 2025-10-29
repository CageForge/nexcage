/// Configuration Plugins Module
/// 
/// This module provides registration and management for all built-in
/// configuration plugins that extend NexCage's configuration system.

const std = @import("std");
const plugin = @import("../../plugin/mod.zig");
const config_extension = @import("../../plugin/config_extension.zig");
const config_manager = @import("../../plugin/config_manager.zig");

// Import all configuration plugins
pub const backend_config_plugin = @import("backend-config-plugin/plugin.zig");
pub const security_config_plugin = @import("security-config-plugin/plugin.zig");

/// Registry of available configuration plugins
pub const ConfigPluginRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    registered_plugins: std.ArrayList(ConfigPluginEntry),
    
    pub const ConfigPluginEntry = struct {
        name: []const u8,
        description: []const u8,
        extension: *const config_extension.ConfigExtension,
        enabled: bool = true,
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .registered_plugins = std.ArrayList(ConfigPluginEntry).empty,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.registered_plugins.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
        }
        self.registered_plugins.deinit(self.allocator);
    }
    
    /// Register a configuration plugin
    pub fn registerPlugin(
        self: *Self,
        name: []const u8,
        description: []const u8,
        extension: *const config_extension.ConfigExtension
    ) !void {
        const entry = ConfigPluginEntry{
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .extension = extension,
            .enabled = true,
        };
        
        try self.registered_plugins.append(self.allocator, entry);
    }
    
    /// Get all registered plugins
    pub fn getPlugins(self: *Self) []const ConfigPluginEntry {
        return self.registered_plugins.items;
    }
    
    /// Find plugin by name
    pub fn findPlugin(self: *Self, name: []const u8) ?*const ConfigPluginEntry {
        for (self.registered_plugins.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry;
            }
        }
        return null;
    }
    
    /// Enable/disable a plugin
    pub fn setPluginEnabled(self: *Self, name: []const u8, enabled: bool) bool {
        for (self.registered_plugins.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                entry.enabled = enabled;
                return true;
            }
        }
        return false;
    }
};

/// Initialize and register all built-in configuration plugins
pub fn initializeBuiltinConfigPlugins(registry: *ConfigPluginRegistry) !void {
    // Register backend configuration plugin
    try registry.registerPlugin(
        "backend-config",
        "Backend configuration plugin for container runtimes",
        &backend_config_plugin.extension
    );
    
    // Register security configuration plugin
    try registry.registerPlugin(
        "security-config",
        "Security configuration plugin for container security policies",
        &security_config_plugin.extension
    );
}

/// Load all configuration plugins into the configuration manager
pub fn loadConfigPlugins(
    config_plugin_registry: *ConfigPluginRegistry,
    config_plugin_manager: *config_manager.ConfigPluginManager
) !void {
    const plugins = config_plugin_registry.getPlugins();
    
    for (plugins) |plugin_entry| {
        if (plugin_entry.enabled) {
            try config_plugin_manager.registerConfigPlugin(
                plugin_entry.name,
                plugin_entry.extension
            );
        }
    }
}

/// Configuration plugin discovery and loader
pub const ConfigPluginLoader = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    registry: *ConfigPluginRegistry,
    manager: *config_manager.ConfigPluginManager,
    
    pub fn init(
        allocator: std.mem.Allocator,
        registry: *ConfigPluginRegistry,
        manager: *config_manager.ConfigPluginManager
    ) Self {
        return Self{
            .allocator = allocator,
            .registry = registry,
            .manager = manager,
        };
    }
    
    /// Load all enabled configuration plugins
    pub fn loadAllPlugins(self: *Self) !void {
        try loadConfigPlugins(self.registry, self.manager);
    }
    
    /// Generate configuration schema for all plugins
    pub fn generateSchema(self: *Self) !config_manager.ConfigSchema {
        return self.manager.generateConfigSchema();
    }
    
    /// Load and validate configuration from JSON
    pub fn loadConfiguration(self: *Self, json_content: []const u8) !config_manager.EnhancedConfig {
        return self.manager.loadConfiguration(json_content);
    }
    
    /// Validate loaded configuration
    pub fn validateConfiguration(
        self: *Self,
        enhanced_config: *config_manager.EnhancedConfig
    ) !config_manager.ConfigValidationResult {
        return self.manager.validateConfiguration(enhanced_config);
    }
    
    /// Apply validated configuration
    pub fn applyConfiguration(
        self: *Self,
        enhanced_config: *config_manager.EnhancedConfig
    ) !void {
        return self.manager.applyConfiguration(enhanced_config);
    }
};

/// Enhanced configuration system that integrates with existing NexCage config
pub const EnhancedConfigSystem = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugin_manager: *plugin.PluginManager,
    config_plugin_manager: *config_manager.ConfigPluginManager,
    config_plugin_registry: *ConfigPluginRegistry,
    loader: ConfigPluginLoader,
    logger: ?*@import("../../core/mod.zig").LogContext = null,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_manager: *plugin.PluginManager
    ) !Self {
        // Create global plugin context for configuration system
        const global_metadata = plugin.PluginMetadata{
            .name = "global-config-system",
            .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
            .description = "Global configuration system",
            .api_version = 1,
            .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
            .dependencies = &[_][]const u8{},
            .capabilities = &[_]plugin.Capability{.logging},
            .resource_requirements = plugin.ResourceRequirements{},
            .provides_cli_commands = false,
        };
        
        const global_context = try allocator.create(plugin.PluginContext);
        global_context.* = try plugin.PluginContext.init(allocator, global_metadata);
        
        // Create configuration plugin manager
        const config_plugin_manager = try allocator.create(config_manager.ConfigPluginManager);
        config_plugin_manager.* = try config_manager.ConfigPluginManager.init(
            allocator,
            plugin_manager,
            global_context
        );
        
        // Create configuration plugin registry
        const config_plugin_registry = try allocator.create(ConfigPluginRegistry);
        config_plugin_registry.* = ConfigPluginRegistry.init(allocator);
        
        // Create loader
        const loader = ConfigPluginLoader.init(
            allocator,
            config_plugin_registry,
            config_plugin_manager
        );
        
        return Self{
            .allocator = allocator,
            .plugin_manager = plugin_manager,
            .config_plugin_manager = config_plugin_manager,
            .config_plugin_registry = config_plugin_registry,
            .loader = loader,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.config_plugin_manager.deinit();
        self.allocator.destroy(self.config_plugin_manager);
        
        self.config_plugin_registry.deinit();
        self.allocator.destroy(self.config_plugin_registry);
    }
    
    pub fn setLogger(self: *Self, logger: *@import("../../core/mod.zig").LogContext) void {
        self.logger = logger;
        self.config_plugin_manager.setLogger(logger);
    }
    
    /// Initialize the complete configuration system
    pub fn initialize(self: *Self) !void {
        // Register built-in configuration plugins
        try initializeBuiltinConfigPlugins(self.config_plugin_registry);
        
        // Load all enabled plugins
        try self.loader.loadAllPlugins();
        
        if (self.logger) |log| {
            try log.info("Enhanced configuration system initialized", .{});
        }
    }
    
    /// Load configuration from file path
    pub fn loadFromFile(self: *Self, file_path: []const u8) !config_manager.EnhancedConfig {
        const file_content = try std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            1024 * 1024
        );
        defer self.allocator.free(file_content);
        
        return self.loader.loadConfiguration(file_content);
    }
    
    /// Load configuration from JSON string
    pub fn loadFromString(self: *Self, json_content: []const u8) !config_manager.EnhancedConfig {
        return self.loader.loadConfiguration(json_content);
    }
    
    /// Complete configuration loading, validation, and application workflow
    pub fn loadAndApplyConfiguration(self: *Self, json_content: []const u8) !config_manager.EnhancedConfig {
        // Load configuration
        var enhanced_config = try self.loader.loadConfiguration(json_content);
        errdefer enhanced_config.deinit();
        
        // Validate configuration
        const validation_result = try self.loader.validateConfiguration(&enhanced_config);
        
        if (!validation_result.is_valid) {
            if (self.logger) |log| {
                try log.err("Configuration validation failed with {d} errors:", .{validation_result.error_count});
                for (validation_result.errors) |error_item| {
                    try log.err("  {s}: {s}", .{ error_item.field_name, error_item.message });
                }
            }
            return error.InvalidConfiguration;
        }
        
        // Apply configuration
        try self.loader.applyConfiguration(&enhanced_config);
        
        if (self.logger) |log| {
            try log.info("Configuration loaded and applied successfully", .{});
        }
        
        return enhanced_config;
    }
    
    /// Generate configuration schema documentation
    pub fn generateConfigurationSchema(self: *Self) !config_manager.ConfigSchema {
        return self.loader.generateSchema();
    }
    
    /// List registered configuration plugins
    pub fn listConfigPlugins(self: *Self) ![][]const u8 {
        return self.config_plugin_manager.listPlugins(self.allocator);
    }
    
    /// Get plugin information
    pub fn getPluginInfo(self: *Self, plugin_name: []const u8) ?plugin.PluginMetadata {
        return self.config_plugin_manager.getPluginInfo(plugin_name);
    }
};

/// Test suite
const testing = std.testing;

test "configuration plugin registry operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = ConfigPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Test plugin registration
    try registry.registerPlugin(
        "test-config-plugin",
        "Test configuration plugin",
        &backend_config_plugin.extension
    );
    
    // Test finding plugin
    const found = registry.findPlugin("test-config-plugin");
    try testing.expect(found != null);
    try testing.expect(std.mem.eql(u8, found.?.name, "test-config-plugin"));
    
    // Test enabling/disabling
    try testing.expect(registry.setPluginEnabled("test-config-plugin", false));
    try testing.expect(!found.?.enabled);
    
    try testing.expect(registry.setPluginEnabled("test-config-plugin", true));
    try testing.expect(found.?.enabled);
    
    // Test non-existent plugin
    try testing.expect(!registry.setPluginEnabled("non-existent", false));
}

test "builtin configuration plugins initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = ConfigPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Initialize builtin plugins
    try initializeBuiltinConfigPlugins(&registry);
    
    // Check that all plugins are registered
    const plugins = registry.getPlugins();
    try testing.expect(plugins.len == 2);
    
    // Verify specific plugins
    try testing.expect(registry.findPlugin("backend-config") != null);
    try testing.expect(registry.findPlugin("security-config") != null);
}

test "enhanced configuration system integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create enhanced configuration system
    var config_system = try EnhancedConfigSystem.init(allocator, &plugin_manager);
    defer config_system.deinit();
    
    // Initialize the system
    try config_system.initialize();
    
    // Test listing configuration plugins
    const plugin_list = try config_system.listConfigPlugins();
    defer {
        for (plugin_list) |name| {
            allocator.free(name);
        }
        allocator.free(plugin_list);
    }
    
    try testing.expect(plugin_list.len == 2);
    
    // Test loading basic configuration
    const test_config = 
        \\{
        \\  "runtime_type": "lxc",
        \\  "log_level": "info",
        \\  "plugins": {
        \\    "backend-config": {
        \\      "crun": {
        \\        "enabled": true,
        \\        "priority": 10
        \\      },
        \\      "runc": {
        \\        "enabled": false,
        \\        "priority": 20
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    var enhanced_config = try config_system.loadAndApplyConfiguration(test_config);
    defer enhanced_config.deinit();
    
    try testing.expect(enhanced_config.is_valid);
}