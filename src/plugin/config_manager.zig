/// Configuration Plugin Manager
/// 
/// This module manages configuration plugins and integrates them with the
/// main NexCage configuration system, providing plugin-aware configuration.

const std = @import("std");
const plugin = @import("mod.zig");
const config_extension = @import("config_extension.zig");
const core = @import("../core/mod.zig");

/// Registered configuration plugin information
pub const RegisteredConfigPlugin = struct {
    name: []const u8,
    extension: *const config_extension.ConfigExtension,
    context: *config_extension.ConfigContext,
    sections: []config_extension.ConfigSection,
    
    pub fn deinit(self: *RegisteredConfigPlugin, allocator: std.mem.Allocator) void {
        self.extension.deinit(allocator, self.context);
        allocator.free(self.sections);
        allocator.free(self.name);
        self.context.deinit();
        allocator.destroy(self.context);
    }
};

/// Configuration Plugin Manager
pub const ConfigPluginManager = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(RegisteredConfigPlugin),
    plugin_manager: *plugin.PluginManager,
    global_context: *config_extension.ConfigContext,
    logger: ?*core.LogContext = null,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_manager: *plugin.PluginManager,
        global_plugin_context: *plugin.PluginContext
    ) !Self {
        // Create global configuration context
        const global_context = try allocator.create(config_extension.ConfigContext);
        global_context.* = config_extension.ConfigContext.init(allocator, global_plugin_context);
        
        return Self{
            .allocator = allocator,
            .plugins = std.StringHashMap(RegisteredConfigPlugin).init(allocator),
            .plugin_manager = plugin_manager,
            .global_context = global_context,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.plugins.deinit();
        
        self.global_context.deinit();
        self.allocator.destroy(self.global_context);
    }
    
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        self.global_context.logger = logger;
    }
    
    /// Register a configuration plugin
    pub fn registerConfigPlugin(
        self: *Self,
        plugin_name: []const u8,
        extension: *const config_extension.ConfigExtension
    ) !void {
        if (self.logger) |log| {
            try log.info("Registering configuration plugin: {s}", .{plugin_name});
        }
        
        // Create plugin-specific context
        const metadata = extension.getMetadata();
        const plugin_context = try self.allocator.create(plugin.PluginContext);
        plugin_context.* = try plugin.PluginContext.init(self.allocator, metadata);
        
        const context = try self.allocator.create(config_extension.ConfigContext);
        context.* = config_extension.ConfigContext.init(self.allocator, plugin_context);
        
        if (self.logger) |log| {
            context.logger = log;
        }
        
        // Initialize the extension
        try extension.init(self.allocator, context);
        
        // Register configuration sections from the extension
        const sections = try extension.registerSections(self.allocator, context);
        
        // Add sections to global context
        for (sections) |section| {
            try self.global_context.registerSection(section);
        }
        
        const registered_plugin = RegisteredConfigPlugin{
            .name = try self.allocator.dupe(u8, plugin_name),
            .extension = extension,
            .context = context,
            .sections = sections,
        };
        
        try self.plugins.put(registered_plugin.name, registered_plugin);
        
        if (self.logger) |log| {
            try log.info("Registered configuration plugin '{s}' with {d} sections", .{ plugin_name, sections.len });
        }
    }
    
    /// Unregister a configuration plugin
    pub fn unregisterConfigPlugin(self: *Self, plugin_name: []const u8) !void {
        if (self.plugins.fetchRemove(plugin_name)) |kv| {
            if (self.logger) |log| {
                try log.info("Unregistering configuration plugin: {s}", .{plugin_name});
            }
            
            kv.value.deinit(self.allocator);
            self.allocator.free(kv.key);
        }
    }
    
    /// Load configuration from JSON with plugin support
    pub fn loadConfiguration(
        self: *Self,
        json_content: []const u8
    ) !EnhancedConfig {
        // Parse JSON
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_content, .{});
        defer parsed.deinit();
        
        var enhanced_config = EnhancedConfig.init(self.allocator);
        
        // Load core configuration
        var config_loader = core.config.ConfigLoader.init(self.allocator);
        enhanced_config.core_config = try config_loader.loadFromString(json_content);
        
        // Load plugin configurations
        const root_object = parsed.value.object;
        
        // Check for plugins section
        if (root_object.get("plugins")) |plugins_value| {
            const plugins_object = plugins_value.object;
            
            var plugin_iter = self.plugins.iterator();
            while (plugin_iter.next()) |entry| {
                const plugin_name = entry.key_ptr.*;
                const registered_plugin = entry.value_ptr.*;
                
                if (plugins_object.get(plugin_name)) |plugin_config| {
                    try self.loadPluginConfiguration(
                        registered_plugin,
                        plugin_config,
                        &enhanced_config
                    );
                }
            }
        }
        
        return enhanced_config;
    }
    
    /// Load configuration for a specific plugin
    fn loadPluginConfiguration(
        self: *Self,
        registered_plugin: RegisteredConfigPlugin,
        plugin_config: std.json.Value,
        enhanced_config: *EnhancedConfig
    ) !void {
        const plugin_name = registered_plugin.name;
        
        if (self.logger) |log| {
            try log.info("Loading configuration for plugin: {s}", .{plugin_name});
        }
        
        // Parse plugin configuration values
        var plugin_values = std.StringHashMap(config_extension.ConfigValue).init(self.allocator);
        defer {
            var iter = plugin_values.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            plugin_values.deinit();
        }
        
        // Load configuration values based on registered sections
        for (registered_plugin.sections) |section| {
            try self.loadSectionConfiguration(
                section,
                plugin_config,
                plugin_name,
                &plugin_values
            );
        }
        
        // Store plugin configuration
        try enhanced_config.plugin_configs.put(
            try self.allocator.dupe(u8, plugin_name),
            plugin_values
        );
        
        // Update plugin context with values
        var iter = plugin_values.iterator();
        while (iter.next()) |entry| {
            try registered_plugin.context.setValue(
                entry.key_ptr.*,
                entry.value_ptr.*
            );
        }
    }
    
    /// Load configuration for a specific section
    fn loadSectionConfiguration(
        self: *Self,
        section: config_extension.ConfigSection,
        plugin_config: std.json.Value,
        plugin_name: []const u8,
        plugin_values: *std.StringHashMap(config_extension.ConfigValue)
    ) !void {
        // Look for section in plugin config
        if (plugin_config.object.get(section.name)) |section_value| {
            const section_object = section_value.object;
            
            // Load each field in the section
            for (section.fields) |field| {
                const field_key = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{s}",
                    .{ section.name, field.name }
                );
                defer self.allocator.free(field_key);
                
                if (section_object.get(field.name)) |field_value| {
                    const config_value = config_extension.ConfigValue{
                        .value = field_value,
                        .source = .file,
                        .validated = false,
                    };
                    
                    try plugin_values.put(
                        try self.allocator.dupe(u8, field_key),
                        config_value
                    );
                } else if (field.default_value) |default_val| {
                    // Use default value
                    const default_json = try std.json.parseFromSlice(
                        std.json.Value,
                        self.allocator,
                        default_val,
                        .{}
                    );
                    defer default_json.deinit();
                    
                    const config_value = config_extension.ConfigValue{
                        .value = default_json.value,
                        .source = .default,
                        .validated = false,
                    };
                    
                    try plugin_values.put(
                        try self.allocator.dupe(u8, field_key),
                        config_value
                    );
                }
            }
        } else {
            // Load default values for missing sections
            try self.loadDefaultSectionConfiguration(section, plugin_name, plugin_values);
        }
    }
    
    /// Load default configuration for a section
    fn loadDefaultSectionConfiguration(
        self: *Self,
        section: config_extension.ConfigSection,
        plugin_name: []const u8,
        plugin_values: *std.StringHashMap(config_extension.ConfigValue)
    ) !void {
        _ = plugin_name;
        
        for (section.fields) |field| {
            if (field.default_value) |default_val| {
                const field_key = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{s}",
                    .{ section.name, field.name }
                );
                defer self.allocator.free(field_key);
                
                const default_json = try std.json.parseFromSlice(
                    std.json.Value,
                    self.allocator,
                    default_val,
                    .{}
                );
                defer default_json.deinit();
                
                const config_value = config_extension.ConfigValue{
                    .value = default_json.value,
                    .source = .default,
                    .validated = false,
                };
                
                try plugin_values.put(
                    try self.allocator.dupe(u8, field_key),
                    config_value
                );
            }
        }
    }
    
    /// Validate all plugin configurations
    pub fn validateConfiguration(self: *Self, enhanced_config: *EnhancedConfig) !ConfigValidationResult {
        var all_errors = std.ArrayList(config_extension.ConfigValidationError).empty;
        defer all_errors.deinit(self.allocator);
        
        var plugin_iter = self.plugins.iterator();
        while (plugin_iter.next()) |entry| {
            const plugin_name = entry.key_ptr.*;
            const registered_plugin = entry.value_ptr.*;
            
            // Validate using plugin's validation function
            const result = try registered_plugin.extension.validateConfig(
                self.allocator,
                registered_plugin.context
            );
            defer {
                var res = result;
                res.deinit(self.allocator);
            }
            
            if (!result.success) {
                for (result.errors) |error_item| {
                    try all_errors.append(self.allocator, config_extension.ConfigValidationError{
                        .field_name = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}.{s}",
                            .{ plugin_name, error_item.field_name }
                        ),
                        .error_type = error_item.error_type,
                        .message = try self.allocator.dupe(u8, error_item.message),
                    });
                }
            }
            
            // Validate using context validation
            const context_errors = try registered_plugin.context.validate();
            defer {
                for (context_errors) |*error_item| {
                    error_item.deinit(self.allocator);
                }
                self.allocator.free(context_errors);
            }
            
            for (context_errors) |error_item| {
                try all_errors.append(self.allocator, config_extension.ConfigValidationError{
                    .field_name = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}.{s}",
                        .{ plugin_name, error_item.field_name }
                    ),
                    .error_type = error_item.error_type,
                    .message = try self.allocator.dupe(u8, error_item.message),
                });
            }
        }
        
        // Update enhanced config validation status
        enhanced_config.validation_errors = try all_errors.toOwnedSlice(self.allocator);
        enhanced_config.is_valid = enhanced_config.validation_errors.len == 0;
        
        return ConfigValidationResult{
            .is_valid = enhanced_config.is_valid,
            .error_count = enhanced_config.validation_errors.len,
            .errors = enhanced_config.validation_errors,
        };
    }
    
    /// Apply configuration to all plugins
    pub fn applyConfiguration(self: *Self, enhanced_config: *EnhancedConfig) !void {
        if (!enhanced_config.is_valid) {
            return error.InvalidConfiguration;
        }
        
        var plugin_iter = self.plugins.iterator();
        while (plugin_iter.next()) |entry| {
            const registered_plugin = entry.value_ptr.*;
            
            try registered_plugin.extension.applyConfig(
                self.allocator,
                registered_plugin.context
            );
        }
        
        if (self.logger) |log| {
            try log.info("Applied configuration to all plugins", .{});
        }
    }
    
    /// Generate configuration schema for all registered plugins
    pub fn generateConfigSchema(self: *Self) !ConfigSchema {
        var schema = ConfigSchema.init(self.allocator);
        
        var plugin_iter = self.plugins.iterator();
        while (plugin_iter.next()) |entry| {
            const plugin_name = entry.key_ptr.*;
            const registered_plugin = entry.value_ptr.*;
            
            const plugin_schema = PluginSchema{
                .name = try self.allocator.dupe(u8, plugin_name),
                .description = try self.allocator.dupe(u8, registered_plugin.extension.getMetadata().description),
                .sections = try self.allocator.dupe(config_extension.ConfigSection, registered_plugin.sections),
            };
            
            try schema.plugins.put(plugin_schema.name, plugin_schema);
        }
        
        return schema;
    }
    
    /// List registered configuration plugins
    pub fn listPlugins(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var plugin_names = std.ArrayList([]const u8).empty;
        defer plugin_names.deinit(allocator);
        
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            try plugin_names.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return plugin_names.toOwnedSlice(allocator);
    }
    
    /// Get plugin information
    pub fn getPluginInfo(self: *Self, plugin_name: []const u8) ?plugin.PluginMetadata {
        if (self.plugins.get(plugin_name)) |registered_plugin| {
            return registered_plugin.extension.getMetadata();
        }
        return null;
    }
};

/// Enhanced configuration that includes plugin configurations
pub const EnhancedConfig = struct {
    allocator: std.mem.Allocator,
    core_config: core.config.Config,
    plugin_configs: std.StringHashMap(std.StringHashMap(config_extension.ConfigValue)),
    is_valid: bool = false,
    validation_errors: []config_extension.ConfigValidationError = &[_]config_extension.ConfigValidationError{},
    
    pub fn init(allocator: std.mem.Allocator) EnhancedConfig {
        return EnhancedConfig{
            .allocator = allocator,
            .core_config = undefined, // Will be set during loading
            .plugin_configs = std.StringHashMap(std.StringHashMap(config_extension.ConfigValue)).init(allocator),
        };
    }
    
    pub fn deinit(self: *EnhancedConfig) void {
        self.core_config.deinit();
        
        var plugin_iter = self.plugin_configs.iterator();
        while (plugin_iter.next()) |entry| {
            var config_iter = entry.value_ptr.iterator();
            while (config_iter.next()) |config_entry| {
                self.allocator.free(config_entry.key_ptr.*);
            }
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.plugin_configs.deinit();
        
        for (self.validation_errors) |*error_item| {
            error_item.deinit(self.allocator);
        }
        self.allocator.free(self.validation_errors);
    }
    
    /// Get configuration value for a plugin
    pub fn getPluginValue(
        self: *const EnhancedConfig,
        plugin_name: []const u8,
        key: []const u8
    ) ?*const config_extension.ConfigValue {
        if (self.plugin_configs.get(plugin_name)) |plugin_config| {
            return plugin_config.get(key);
        }
        return null;
    }
};

/// Configuration validation result
pub const ConfigValidationResult = struct {
    is_valid: bool,
    error_count: usize,
    errors: []config_extension.ConfigValidationError,
};

/// Configuration schema for documentation/validation
pub const ConfigSchema = struct {
    plugins: std.StringHashMap(PluginSchema),
    
    pub fn init(allocator: std.mem.Allocator) ConfigSchema {
        return ConfigSchema{
            .plugins = std.StringHashMap(PluginSchema).init(allocator),
        };
    }
    
    pub fn deinit(self: *ConfigSchema, allocator: std.mem.Allocator) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.plugins.deinit();
    }
};

/// Plugin schema definition
pub const PluginSchema = struct {
    name: []const u8,
    description: []const u8,
    sections: []config_extension.ConfigSection,
    
    pub fn deinit(self: *PluginSchema, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.sections);
    }
};

/// Test suite
const testing = std.testing;

test "configuration plugin manager basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create global plugin context
    const global_metadata = plugin.PluginMetadata{
        .name = "global-config",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Global configuration",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = false,
    };
    
    var global_context = try plugin.PluginContext.init(allocator, global_metadata);
    defer global_context.deinit();
    
    // Create configuration plugin manager
    var config_manager = try ConfigPluginManager.init(allocator, &plugin_manager, &global_context);
    defer config_manager.deinit();
    
    // Test that manager initializes correctly
    const plugin_list = try config_manager.listPlugins(allocator);
    defer {
        for (plugin_list) |name| {
            allocator.free(name);
        }
        allocator.free(plugin_list);
    }
    try testing.expect(plugin_list.len == 0);
}

test "configuration loading and validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create global plugin context
    const global_metadata = plugin.PluginMetadata{
        .name = "global-config",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Global configuration",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = false,
    };
    
    var global_context = try plugin.PluginContext.init(allocator, global_metadata);
    defer global_context.deinit();
    
    // Create configuration plugin manager
    var config_manager = try ConfigPluginManager.init(allocator, &plugin_manager, &global_context);
    defer config_manager.deinit();
    
    // Test loading basic configuration
    const test_config = 
        \\{
        \\  "runtime_type": "lxc",
        \\  "log_level": "info",
        \\  "plugins": {}
        \\}
    ;
    
    var enhanced_config = try config_manager.loadConfiguration(test_config);
    defer enhanced_config.deinit();
    
    // Test validation
    const validation_result = try config_manager.validateConfiguration(&enhanced_config);
    try testing.expect(validation_result.is_valid);
    try testing.expect(validation_result.error_count == 0);
}