/// Configuration Extension Plugin Interface
/// 
/// This module defines the interface for plugins that can contribute
/// configuration options and validate configurations.

const std = @import("std");
const plugin = @import("mod.zig");
const core = @import("../core/mod.zig");

/// Configuration field definition
pub const ConfigField = struct {
    name: []const u8,
    field_type: FieldType,
    description: []const u8,
    required: bool = false,
    default_value: ?[]const u8 = null,
    validation: ?ValidationRule = null,
    sensitive: bool = false, // For secrets, tokens, etc.
    
    pub const FieldType = enum {
        string,
        number,
        boolean,
        array,
        object,
        enum_value,
    };
    
    pub const ValidationRule = struct {
        rule_type: RuleType,
        value: []const u8,
        
        pub const RuleType = enum {
            min_length,
            max_length,
            pattern, // regex pattern
            min_value,
            max_value,
            one_of, // enum values
        };
    };
};

/// Configuration section definition
pub const ConfigSection = struct {
    name: []const u8,
    description: []const u8,
    fields: []const ConfigField,
    dependencies: []const []const u8 = &[_][]const u8{}, // Required plugins
    optional: bool = false,
};

/// Configuration value with metadata
pub const ConfigValue = struct {
    value: std.json.Value,
    source: ConfigSource,
    validated: bool = false,
    
    pub const ConfigSource = enum {
        default,
        file,
        environment,
        command_line,
        plugin,
    };
    
    pub fn asString(self: *const ConfigValue) ?[]const u8 {
        return switch (self.value) {
            .string => |s| s,
            else => null,
        };
    }
    
    pub fn asNumber(self: *const ConfigValue) ?f64 {
        return switch (self.value) {
            .float => |f| f,
            .integer => |i| @floatFromInt(i),
            else => null,
        };
    }
    
    pub fn asBoolean(self: *const ConfigValue) ?bool {
        return switch (self.value) {
            .bool => |b| b,
            else => null,
        };
    }
    
    pub fn asArray(self: *const ConfigValue) ?std.json.Array {
        return switch (self.value) {
            .array => |a| a,
            else => null,
        };
    }
    
    pub fn asObject(self: *const ConfigValue) ?std.json.ObjectMap {
        return switch (self.value) {
            .object => |o| o,
            else => null,
        };
    }
};

/// Configuration context for plugins
pub const ConfigContext = struct {
    allocator: std.mem.Allocator,
    plugin_context: *plugin.PluginContext,
    sections: std.StringHashMap(ConfigSection),
    values: std.StringHashMap(ConfigValue),
    logger: ?*core.LogContext = null,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_context: *plugin.PluginContext
    ) ConfigContext {
        return ConfigContext{
            .allocator = allocator,
            .plugin_context = plugin_context,
            .sections = std.StringHashMap(ConfigSection).init(allocator),
            .values = std.StringHashMap(ConfigValue).init(allocator),
        };
    }
    
    pub fn deinit(self: *ConfigContext) void {
        var section_iter = self.sections.iterator();
        while (section_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.sections.deinit();
        
        var value_iter = self.values.iterator();
        while (value_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.values.deinit();
    }
    
    /// Get configuration value by key
    pub fn getValue(self: *const ConfigContext, key: []const u8) ?*const ConfigValue {
        return self.values.get(key);
    }
    
    /// Set configuration value
    pub fn setValue(self: *ConfigContext, key: []const u8, value: ConfigValue) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        try self.values.put(key_copy, value);
    }
    
    /// Get section definition
    pub fn getSection(self: *const ConfigContext, name: []const u8) ?*const ConfigSection {
        return self.sections.get(name);
    }
    
    /// Register configuration section
    pub fn registerSection(self: *ConfigContext, section: ConfigSection) !void {
        const name_copy = try self.allocator.dupe(u8, section.name);
        try self.sections.put(name_copy, section);
    }
    
    /// Validate configuration against registered sections
    pub fn validate(self: *ConfigContext) ![]ConfigValidationError {
        var errors = std.ArrayList(ConfigValidationError).empty;
        defer errors.deinit(self.allocator);
        
        var section_iter = self.sections.iterator();
        while (section_iter.next()) |entry| {
            const section = entry.value_ptr.*;
            try self.validateSection(section, &errors);
        }
        
        return errors.toOwnedSlice(self.allocator);
    }
    
    /// Validate a specific section
    fn validateSection(
        self: *ConfigContext,
        section: ConfigSection,
        errors: *std.ArrayList(ConfigValidationError)
    ) !void {
        for (section.fields) |field| {
            const field_key = try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}",
                .{ section.name, field.name }
            );
            defer self.allocator.free(field_key);
            
            if (self.getValue(field_key)) |value| {
                try self.validateField(field, value, field_key, errors);
            } else if (field.required) {
                try errors.append(self.allocator, ConfigValidationError{
                    .field_name = try self.allocator.dupe(u8, field_key),
                    .error_type = .missing_required_field,
                    .message = try std.fmt.allocPrint(
                        self.allocator,
                        "Required field '{s}' is missing",
                        .{field_key}
                    ),
                });
            }
        }
    }
    
    /// Validate a specific field
    fn validateField(
        self: *ConfigContext,
        field: ConfigField,
        value: *const ConfigValue,
        field_key: []const u8,
        errors: *std.ArrayList(ConfigValidationError)
    ) !void {
        // Type validation
        const type_valid = switch (field.field_type) {
            .string => value.asString() != null,
            .number => value.asNumber() != null,
            .boolean => value.asBoolean() != null,
            .array => value.asArray() != null,
            .object => value.asObject() != null,
            .enum_value => value.asString() != null, // Enum validation done separately
        };
        
        if (!type_valid) {
            try errors.append(self.allocator, ConfigValidationError{
                .field_name = try self.allocator.dupe(u8, field_key),
                .error_type = .invalid_type,
                .message = try std.fmt.allocPrint(
                    self.allocator,
                    "Field '{s}' has invalid type, expected {s}",
                    .{ field_key, @tagName(field.field_type) }
                ),
            });
            return;
        }
        
        // Custom validation rules
        if (field.validation) |validation| {
            try self.validateRule(field, value, field_key, validation, errors);
        }
    }
    
    /// Validate a specific rule
    fn validateRule(
        self: *ConfigContext,
        field: ConfigField,
        value: *const ConfigValue,
        field_key: []const u8,
        rule: ConfigField.ValidationRule,
        errors: *std.ArrayList(ConfigValidationError)
    ) !void {
        _ = field;
        
        switch (rule.rule_type) {
            .min_length => {
                if (value.asString()) |str| {
                    const min_len = std.fmt.parseInt(usize, rule.value, 10) catch return;
                    if (str.len < min_len) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' must be at least {d} characters long",
                                .{ field_key, min_len }
                            ),
                        });
                    }
                }
            },
            .max_length => {
                if (value.asString()) |str| {
                    const max_len = std.fmt.parseInt(usize, rule.value, 10) catch return;
                    if (str.len > max_len) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' must be at most {d} characters long",
                                .{ field_key, max_len }
                            ),
                        });
                    }
                }
            },
            .min_value => {
                if (value.asNumber()) |num| {
                    const min_val = std.fmt.parseFloat(f64, rule.value) catch return;
                    if (num < min_val) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' must be at least {d}",
                                .{ field_key, min_val }
                            ),
                        });
                    }
                }
            },
            .max_value => {
                if (value.asNumber()) |num| {
                    const max_val = std.fmt.parseFloat(f64, rule.value) catch return;
                    if (num > max_val) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' must be at most {d}",
                                .{ field_key, max_val }
                            ),
                        });
                    }
                }
            },
            .pattern => {
                // Simple pattern matching - could be enhanced with real regex
                if (value.asString()) |str| {
                    if (!std.mem.containsAtLeast(u8, str, 1, rule.value)) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' does not match required pattern",
                                .{field_key}
                            ),
                        });
                    }
                }
            },
            .one_of => {
                if (value.asString()) |str| {
                    var valid_values = std.mem.splitSequence(u8, rule.value, ",");
                    var is_valid = false;
                    while (valid_values.next()) |valid_value| {
                        if (std.mem.eql(u8, std.mem.trim(u8, valid_value, " "), str)) {
                            is_valid = true;
                            break;
                        }
                    }
                    if (!is_valid) {
                        try errors.append(self.allocator, ConfigValidationError{
                            .field_name = try self.allocator.dupe(u8, field_key),
                            .error_type = .validation_failed,
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Field '{s}' must be one of: {s}",
                                .{ field_key, rule.value }
                            ),
                        });
                    }
                }
            },
        }
    }
    
    /// Log info message if logger is available
    pub fn logInfo(self: *const ConfigContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.info(format, args);
        }
    }
    
    /// Log warning message if logger is available
    pub fn logWarn(self: *const ConfigContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.warn(format, args);
        }
    }
    
    /// Log error message if logger is available
    pub fn logError(self: *const ConfigContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.err(format, args);
        }
    }
};

/// Configuration validation error
pub const ConfigValidationError = struct {
    field_name: []const u8,
    error_type: ErrorType,
    message: []const u8,
    
    pub const ErrorType = enum {
        missing_required_field,
        invalid_type,
        validation_failed,
        dependency_missing,
    };
    
    pub fn deinit(self: *ConfigValidationError, allocator: std.mem.Allocator) void {
        allocator.free(self.field_name);
        allocator.free(self.message);
    }
};

/// Configuration extension result
pub const ConfigResult = struct {
    success: bool,
    errors: []ConfigValidationError = &[_]ConfigValidationError{},
    
    pub fn isSuccess() ConfigResult {
        return ConfigResult{ .success = true };
    }
    
    pub fn failure(errors: []ConfigValidationError) ConfigResult {
        return ConfigResult{
            .success = false,
            .errors = errors,
        };
    }
    
    pub fn deinit(self: *ConfigResult, allocator: std.mem.Allocator) void {
        for (self.errors) |*error_item| {
            error_item.deinit(allocator);
        }
        allocator.free(self.errors);
    }
};

/// Configuration Extension Plugin Interface
pub const ConfigExtension = struct {
    /// Register configuration sections provided by this plugin
    register_sections_fn: *const fn(allocator: std.mem.Allocator, context: *ConfigContext) anyerror![]ConfigSection,
    
    /// Validate configuration values
    validate_config_fn: ?*const fn(allocator: std.mem.Allocator, context: *ConfigContext) anyerror!ConfigResult = null,
    
    /// Apply configuration changes
    apply_config_fn: ?*const fn(allocator: std.mem.Allocator, context: *ConfigContext) anyerror!void = null,
    
    /// Get default configuration values
    get_defaults_fn: ?*const fn(allocator: std.mem.Allocator, context: *ConfigContext) anyerror!std.StringHashMap(ConfigValue) = null,
    
    /// Initialize configuration extension
    init_fn: ?*const fn(allocator: std.mem.Allocator, context: *ConfigContext) anyerror!void = null,
    
    /// Deinitialize configuration extension
    deinit_fn: ?*const fn(allocator: std.mem.Allocator, context: *ConfigContext) void = null,
    
    /// Get plugin metadata for configuration extension
    get_metadata_fn: *const fn() plugin.PluginMetadata,
    
    /// Register configuration sections
    pub fn registerSections(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) ![]ConfigSection {
        return self.register_sections_fn(allocator, context);
    }
    
    /// Validate configuration
    pub fn validateConfig(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) !ConfigResult {
        if (self.validate_config_fn) |validate_fn| {
            return validate_fn(allocator, context);
        }
        return ConfigResult.isSuccess();
    }
    
    /// Apply configuration
    pub fn applyConfig(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) !void {
        if (self.apply_config_fn) |apply_fn| {
            try apply_fn(allocator, context);
        }
    }
    
    /// Get default values
    pub fn getDefaults(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) !std.StringHashMap(ConfigValue) {
        if (self.get_defaults_fn) |defaults_fn| {
            return defaults_fn(allocator, context);
        }
        return std.StringHashMap(ConfigValue).init(allocator);
    }
    
    /// Initialize extension
    pub fn init(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) !void {
        if (self.init_fn) |init_fn| {
            try init_fn(allocator, context);
        }
    }
    
    /// Deinitialize extension
    pub fn deinit(
        self: *const ConfigExtension,
        allocator: std.mem.Allocator,
        context: *ConfigContext
    ) void {
        if (self.deinit_fn) |deinit_fn| {
            deinit_fn(allocator, context);
        }
    }
    
    /// Get metadata
    pub fn getMetadata(self: *const ConfigExtension) plugin.PluginMetadata {
        return self.get_metadata_fn();
    }
};

/// Test suite
const testing = std.testing;

test "configuration context basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create mock plugin context
    const metadata = plugin.PluginMetadata{
        .name = "test-config-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Test config plugin",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = false,
    };
    
    var plugin_context = try plugin.PluginContext.init(allocator, metadata);
    defer plugin_context.deinit();
    
    var config_context = ConfigContext.init(allocator, &plugin_context);
    defer config_context.deinit();
    
    // Test setting and getting values
    const test_value = ConfigValue{
        .value = std.json.Value{ .string = "test-value" },
        .source = .default,
    };
    
    try config_context.setValue("test.key", test_value);
    
    const retrieved = config_context.getValue("test.key");
    try testing.expect(retrieved != null);
    try testing.expect(std.mem.eql(u8, retrieved.?.asString().?, "test-value"));
}

test "configuration field validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create mock plugin context
    const metadata = plugin.PluginMetadata{
        .name = "test-config-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Test config plugin",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = false,
    };
    
    var plugin_context = try plugin.PluginContext.init(allocator, metadata);
    defer plugin_context.deinit();
    
    var config_context = ConfigContext.init(allocator, &plugin_context);
    defer config_context.deinit();
    
    // Register a section with validation
    const test_section = ConfigSection{
        .name = "test",
        .description = "Test section",
        .fields = &[_]ConfigField{
            ConfigField{
                .name = "required_field",
                .field_type = .string,
                .description = "A required string field",
                .required = true,
                .validation = ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "5",
                },
            },
        },
    };
    
    try config_context.registerSection(test_section);
    
    // Test validation with missing required field
    const errors = try config_context.validate();
    defer {
        for (errors) |*error_item| {
            error_item.deinit(allocator);
        }
        allocator.free(errors);
    }
    
    try testing.expect(errors.len == 1);
    try testing.expect(errors[0].error_type == .missing_required_field);
}