/// Enhanced Configuration System Integration
/// 
/// This module integrates the plugin-aware configuration system with
/// the existing NexCage core configuration, providing a unified interface.

const std = @import("std");
const core = @import("mod.zig");
const plugin = @import("../plugin/mod.zig");
const config_plugins = @import("../plugins/config/mod.zig");

/// Enhanced configuration loader that supports both core and plugin configurations
pub const EnhancedConfigLoader = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    core_loader: core.config.ConfigLoader,
    plugin_system: ?*config_plugins.EnhancedConfigSystem = null,
    logger: ?*core.LogContext = null,
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .core_loader = core.config.ConfigLoader.init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        if (self.plugin_system) |system| {
            system.deinit();
            self.allocator.destroy(system);
        }
    }
    
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        if (self.plugin_system) |system| {
            system.setLogger(logger);
        }
    }
    
    /// Initialize plugin system for enhanced configuration
    pub fn initializePluginSystem(self: *Self, plugin_manager: *plugin.PluginManager) !void {
        self.plugin_system = try self.allocator.create(config_plugins.EnhancedConfigSystem);
        self.plugin_system.? = try config_plugins.EnhancedConfigSystem.init(
            self.allocator,
            plugin_manager
        );
        
        if (self.logger) |log| {
            self.plugin_system.?.setLogger(log);
        }
        
        try self.plugin_system.?.initialize();
    }
    
    /// Load configuration with plugin support
    pub fn loadEnhancedConfiguration(self: *Self, json_content: []const u8) !EnhancedConfigurationResult {
        // Load core configuration
        const core_config = try self.core_loader.loadFromString(json_content);
        
        // Load plugin configuration if plugin system is available
        var plugin_config: ?plugin.EnhancedConfig = null;
        if (self.plugin_system) |system| {
            plugin_config = try system.loadAndApplyConfiguration(json_content);
        }
        
        return EnhancedConfigurationResult{
            .core_config = core_config,
            .plugin_config = plugin_config,
            .has_plugins = self.plugin_system != null,
        };
    }
    
    /// Load from default locations with plugin support
    pub fn loadDefaultEnhanced(self: *Self) !EnhancedConfigurationResult {
        // Try to load from default locations
        const default_paths = [_][]const u8{
            "./config.json",
            "/etc/nexcage/config.json",
            "/etc/nexcage/nexcage.json",
        };
        
        for (default_paths) |path| {
            if (self.loadEnhancedFromFile(path)) |result| {
                return result;
            } else |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            }
        }
        
        // Return default configuration if no file found
        const core_config = try core.config.Config.init(self.allocator, .lxc);
        return EnhancedConfigurationResult{
            .core_config = core_config,
            .plugin_config = null,
            .has_plugins = false,
        };
    }
    
    /// Load from file with plugin support
    pub fn loadEnhancedFromFile(self: *Self, file_path: []const u8) !EnhancedConfigurationResult {
        const file_content = std.fs.cwd().readFileAlloc(
            self.allocator,
            file_path,
            1024 * 1024
        ) catch |err| switch (err) {
            error.FileNotFound => return error.FileNotFound,
            else => return err,
        };
        defer self.allocator.free(file_content);
        
        return self.loadEnhancedConfiguration(file_content);
    }
    
    /// Get plugin configuration value
    pub fn getPluginValue(
        self: *const Self,
        result: *const EnhancedConfigurationResult,
        plugin_name: []const u8,
        key: []const u8
    ) ?*const plugin.ConfigValue {
        _ = self;
        if (result.plugin_config) |*config| {
            return config.getPluginValue(plugin_name, key);
        }
        return null;
    }
    
    /// Check if a backend is enabled via plugin configuration
    pub fn isBackendEnabled(
        self: *const Self,
        result: *const EnhancedConfigurationResult,
        backend_name: []const u8
    ) bool {
        const enabled_key = std.fmt.allocPrint(
            self.allocator,
            "{s}.enabled",
            .{backend_name}
        ) catch return true; // Default to enabled on allocation error
        defer self.allocator.free(enabled_key);
        
        if (self.getPluginValue(result, "backend-config", enabled_key)) |value| {
            return value.asBoolean() orelse true;
        }
        
        return true; // Default to enabled
    }
    
    /// Get backend priority from plugin configuration
    pub fn getBackendPriority(
        self: *const Self,
        result: *const EnhancedConfigurationResult,
        backend_name: []const u8
    ) u32 {
        const priority_key = std.fmt.allocPrint(
            self.allocator,
            "{s}.priority",
            .{backend_name}
        ) catch return 100; // Default priority on allocation error
        defer self.allocator.free(priority_key);
        
        if (self.getPluginValue(result, "backend-config", priority_key)) |value| {
            if (value.asNumber()) |priority| {
                return @intFromFloat(priority);
            }
        }
        
        // Return default priorities
        if (std.mem.eql(u8, backend_name, "crun")) return 10;
        if (std.mem.eql(u8, backend_name, "runc")) return 20;
        if (std.mem.eql(u8, backend_name, "proxmox-lxc")) return 30;
        if (std.mem.eql(u8, backend_name, "proxmox-vm")) return 40;
        
        return 100;
    }
    
    /// Generate configuration documentation
    pub fn generateConfigurationDocs(self: *Self) ![]const u8 {
        var docs = std.ArrayList(u8).empty;
        defer docs.deinit(self.allocator);
        
        const writer = docs.writer(self.allocator);
        
        try writer.print("# NexCage Configuration Documentation\n\n");
        try writer.print("This document describes the complete configuration options for NexCage.\n\n");
        
        // Core configuration documentation
        try writer.print("## Core Configuration\n\n");
        try writer.print("The core configuration includes runtime, logging, and networking options.\n\n");
        try writer.print("```json\n");
        try writer.print("{{\n");
        try writer.print("  \"runtime_type\": \"lxc\",\n");
        try writer.print("  \"log_level\": \"info\",\n");
        try writer.print("  \"log_file\": \"/var/log/nexcage.log\",\n");
        try writer.print("  \"data_dir\": \"/var/lib/nexcage\",\n");
        try writer.print("  \"network\": {{\n");
        try writer.print("    \"bridge\": \"lxcbr0\"\n");
        try writer.print("  }}\n");
        try writer.print("}}\n");
        try writer.print("```\n\n");
        
        // Plugin configuration documentation
        if (self.plugin_system) |system| {
            try writer.print("## Plugin Configuration\n\n");
            try writer.print("Plugin-specific configuration options:\n\n");
            
            const schema = try system.generateConfigurationSchema();
            defer {
                var sch = schema;
                sch.deinit(self.allocator);
            }
            
            var plugin_iter = schema.plugins.iterator();
            while (plugin_iter.next()) |entry| {
                const plugin_name = entry.key_ptr.*;
                const plugin_schema = entry.value_ptr.*;
                
                try writer.print("### {s}\n\n", .{plugin_name});
                try writer.print("{s}\n\n", .{plugin_schema.description});
                
                for (plugin_schema.sections) |section| {
                    try writer.print("#### {s}\n\n", .{section.name});
                    try writer.print("{s}\n\n", .{section.description});
                    
                    try writer.print("```json\n");
                    try writer.print("\"plugins\": {{\n");
                    try writer.print("  \"{s}\": {{\n", .{plugin_name});
                    try writer.print("    \"{s}\": {{\n", .{section.name});
                    
                    for (section.fields) |field| {
                        const default_val = field.default_value orelse "null";
                        try writer.print("      \"{s}\": {s}, // {s}\n", .{ field.name, default_val, field.description });
                    }
                    
                    try writer.print("    }}\n");
                    try writer.print("  }}\n");
                    try writer.print("}}\n");
                    try writer.print("```\n\n");
                }
            }
        }
        
        return docs.toOwnedSlice(self.allocator);
    }
};

/// Enhanced configuration result containing both core and plugin configs
pub const EnhancedConfigurationResult = struct {
    core_config: core.config.Config,
    plugin_config: ?plugin.EnhancedConfig,
    has_plugins: bool,
    
    pub fn deinit(self: *EnhancedConfigurationResult) void {
        self.core_config.deinit();
        if (self.plugin_config) |*config| {
            config.deinit();
        }
    }
    
    /// Get the core configuration
    pub fn getCoreConfig(self: *const EnhancedConfigurationResult) *const core.config.Config {
        return &self.core_config;
    }
    
    /// Get the plugin configuration (if available)
    pub fn getPluginConfig(self: *const EnhancedConfigurationResult) ?*const plugin.EnhancedConfig {
        if (self.plugin_config) |*config| {
            return config;
        }
        return null;
    }
    
    /// Check if configuration is valid
    pub fn isValid(self: *const EnhancedConfigurationResult) bool {
        if (self.plugin_config) |*config| {
            return config.is_valid;
        }
        return true; // Core config is always considered valid if it loads
    }
    
    /// Get validation errors
    pub fn getValidationErrors(self: *const EnhancedConfigurationResult) []const plugin.ConfigValidationError {
        if (self.plugin_config) |*config| {
            return config.validation_errors;
        }
        return &[_]plugin.ConfigValidationError{};
    }
};

/// Global enhanced configuration loader instance
var global_enhanced_loader: ?EnhancedConfigLoader = null;

/// Initialize global enhanced configuration loader
pub fn initGlobalEnhancedLoader(allocator: std.mem.Allocator) void {
    global_enhanced_loader = EnhancedConfigLoader.init(allocator);
}

/// Get global enhanced configuration loader
pub fn getGlobalEnhancedLoader() ?*EnhancedConfigLoader {
    return if (global_enhanced_loader) |*loader| loader else null;
}

/// Deinitialize global enhanced configuration loader
pub fn deinitGlobalEnhancedLoader() void {
    if (global_enhanced_loader) |*loader| {
        loader.deinit();
        global_enhanced_loader = null;
    }
}

/// Test suite
const testing = std.testing;

test "enhanced configuration loader basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var loader = EnhancedConfigLoader.init(allocator);
    defer loader.deinit();
    
    // Test loading basic configuration without plugins
    const test_config = 
        \\{
        \\  "runtime_type": "lxc",
        \\  "log_level": "info"
        \\}
    ;
    
    var result = try loader.loadEnhancedConfiguration(test_config);
    defer result.deinit();
    
    try testing.expect(!result.has_plugins);
    try testing.expect(result.isValid());
}

test "enhanced configuration with plugin system" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    var loader = EnhancedConfigLoader.init(allocator);
    defer loader.deinit();
    
    // Initialize plugin system
    try loader.initializePluginSystem(&plugin_manager);
    
    // Test loading configuration with plugins
    const test_config = 
        \\{
        \\  "runtime_type": "lxc",
        \\  "log_level": "info",
        \\  "plugins": {
        \\    "backend-config": {
        \\      "crun": {
        \\        "enabled": true,
        \\        "priority": 10
        \\      }
        \\    }
        \\  }
        \\}
    ;
    
    var result = try loader.loadEnhancedConfiguration(test_config);
    defer result.deinit();
    
    try testing.expect(result.has_plugins);
    try testing.expect(result.isValid());
    
    // Test getting plugin values
    try testing.expect(loader.isBackendEnabled(&result, "crun"));
    try testing.expect(loader.getBackendPriority(&result, "crun") == 10);
}