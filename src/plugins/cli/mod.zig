/// CLI Plugins Module
/// 
/// This module provides registration and management for all built-in CLI plugins.

const std = @import("std");
const plugin = @import("../../plugin/mod.zig");
const cli_extension = @import("../../plugin/cli_extension.zig");
const cli_manager = @import("../../plugin/cli_manager.zig");

// Import all CLI plugins
pub const stats_plugin = @import("stats-plugin/plugin.zig");
pub const logs_plugin = @import("logs-plugin/plugin.zig");
pub const network_plugin = @import("network-plugin/plugin.zig");

/// Registry of available CLI plugins
pub const CliPluginRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    registered_plugins: std.ArrayList(CliPluginEntry),
    
    pub const CliPluginEntry = struct {
        name: []const u8,
        description: []const u8,
        extension: *const cli_extension.CliExtension,
        enabled: bool = true,
    };
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .registered_plugins = std.ArrayList(CliPluginEntry).empty,
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.registered_plugins.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.description);
        }
        self.registered_plugins.deinit(self.allocator);
    }
    
    /// Register a CLI plugin
    pub fn registerPlugin(
        self: *Self,
        name: []const u8,
        description: []const u8,
        extension: *const cli_extension.CliExtension
    ) !void {
        const entry = CliPluginEntry{
            .name = try self.allocator.dupe(u8, name),
            .description = try self.allocator.dupe(u8, description),
            .extension = extension,
            .enabled = true,
        };
        
        try self.registered_plugins.append(self.allocator, entry);
    }
    
    /// Get all registered plugins
    pub fn getPlugins(self: *Self) []const CliPluginEntry {
        return self.registered_plugins.items;
    }
    
    /// Find plugin by name
    pub fn findPlugin(self: *Self, name: []const u8) ?*const CliPluginEntry {
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

/// Initialize and register all built-in CLI plugins
pub fn initializeBuiltinCliPlugins(registry: *CliPluginRegistry) !void {
    // Register stats plugin
    try registry.registerPlugin(
        "stats",
        "Container statistics and monitoring commands",
        &stats_plugin.extension
    );
    
    // Register logs plugin
    try registry.registerPlugin(
        "logs",
        "Advanced logging and debugging commands",
        &logs_plugin.extension
    );
    
    // Register network plugin
    try registry.registerPlugin(
        "network",
        "Network management and troubleshooting commands",
        &network_plugin.extension
    );
}

/// Load all CLI plugins into the CLI manager
pub fn loadCliPlugins(
    cli_plugin_registry: *CliPluginRegistry,
    cli_plugin_manager: *cli_manager.CliPluginManager
) !void {
    const plugins = cli_plugin_registry.getPlugins();
    
    for (plugins) |plugin_entry| {
        if (plugin_entry.enabled) {
            try cli_plugin_manager.registerCliPlugin(
                plugin_entry.name,
                plugin_entry.extension
            );
        }
    }
}

/// CLI plugin discovery and loader
pub const CliPluginLoader = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    registry: *CliPluginRegistry,
    manager: *cli_manager.CliPluginManager,
    
    pub fn init(
        allocator: std.mem.Allocator,
        registry: *CliPluginRegistry,
        manager: *cli_manager.CliPluginManager
    ) Self {
        return Self{
            .allocator = allocator,
            .registry = registry,
            .manager = manager,
        };
    }
    
    /// Load all enabled CLI plugins
    pub fn loadAllPlugins(self: *Self) !void {
        try loadCliPlugins(self.registry, self.manager);
    }
    
    /// Get list of available CLI commands
    pub fn getAvailableCommands(self: *Self) ![][]const u8 {
        return self.manager.getAllCommands(self.allocator);
    }
    
    /// Execute a CLI command
    pub fn executeCommand(
        self: *Self,
        command_name: []const u8,
        args: []const []const u8
    ) !cli_extension.CliResult {
        return self.manager.executeCommand(command_name, args, self.allocator);
    }
};

/// Test suite
const testing = std.testing;

test "CLI plugin registry operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = CliPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Test plugin registration
    try registry.registerPlugin(
        "test-plugin",
        "Test plugin description",
        &stats_plugin.extension
    );
    
    // Test finding plugin
    const found = registry.findPlugin("test-plugin");
    try testing.expect(found != null);
    try testing.expect(std.mem.eql(u8, found.?.name, "test-plugin"));
    
    // Test enabling/disabling
    try testing.expect(registry.setPluginEnabled("test-plugin", false));
    try testing.expect(!found.?.enabled);
    
    try testing.expect(registry.setPluginEnabled("test-plugin", true));
    try testing.expect(found.?.enabled);
    
    // Test non-existent plugin
    try testing.expect(!registry.setPluginEnabled("non-existent", false));
}

test "builtin CLI plugins initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var registry = CliPluginRegistry.init(allocator);
    defer registry.deinit();
    
    // Initialize builtin plugins
    try initializeBuiltinCliPlugins(&registry);
    
    // Check that all plugins are registered
    const plugins = registry.getPlugins();
    try testing.expect(plugins.len == 3);
    
    // Verify specific plugins
    try testing.expect(registry.findPlugin("stats") != null);
    try testing.expect(registry.findPlugin("logs") != null);
    try testing.expect(registry.findPlugin("network") != null);
}

test "CLI plugin loading integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_plugin_manager = cli_manager.CliPluginManager.init(allocator, &plugin_manager);
    defer cli_plugin_manager.deinit();
    
    // Create CLI plugin registry
    var cli_plugin_registry = CliPluginRegistry.init(allocator);
    defer cli_plugin_registry.deinit();
    
    // Initialize builtin plugins
    try initializeBuiltinCliPlugins(&cli_plugin_registry);
    
    // Load plugins into manager
    try loadCliPlugins(&cli_plugin_registry, &cli_plugin_manager);
    
    // Verify plugins are loaded
    const plugin_list = try cli_plugin_manager.listPlugins(allocator);
    defer {
        for (plugin_list) |name| {
            allocator.free(name);
        }
        allocator.free(plugin_list);
    }
    
    try testing.expect(plugin_list.len == 3);
}