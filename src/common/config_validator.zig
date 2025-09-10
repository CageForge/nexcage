/// Configuration validation and schema management for Proxmox LXCRI
/// 
/// This module provides comprehensive configuration validation, schema checking,
/// and configuration versioning capabilities to ensure robust configuration management.

const std = @import("std");
const types = @import("types");
const logger = @import("logger");
const json = std.json;

/// Configuration validation error types
pub const ValidationError = error{
    InvalidSchema,
    MissingRequiredField,
    InvalidFieldType,
    InvalidFieldValue,
    UnsupportedVersion,
    ConfigurationTooLarge,
    CircularReference,
    InvalidRange,
    InvalidFormat,
};

/// Configuration schema version for migration support
pub const ConfigVersion = enum(u32) {
    v1_0 = 100,
    v1_1 = 101,
    v1_2 = 102,
    v2_0 = 200,
    current = v2_0,

    /// Converts version string to enum
    pub fn fromString(version_str: []const u8) !ConfigVersion {
        if (std.mem.eql(u8, version_str, "1.0")) return .v1_0;
        if (std.mem.eql(u8, version_str, "1.1")) return .v1_1;
        if (std.mem.eql(u8, version_str, "1.2")) return .v1_2;
        if (std.mem.eql(u8, version_str, "2.0")) return .v2_0;
        return ValidationError.UnsupportedVersion;
    }

    /// Converts enum to string
    pub fn toString(self: ConfigVersion) []const u8 {
        return switch (self) {
            .v1_0 => "1.0",
            .v1_1 => "1.1", 
            .v1_2 => "1.2",
            .v2_0 => "2.0",
            .current => "2.0",
        };
    }
};

/// Field validation rule
pub const ValidationRule = struct {
    field_name: []const u8,
    required: bool = false,
    min_length: ?usize = null,
    max_length: ?usize = null,
    min_value: ?i64 = null,
    max_value: ?i64 = null,
    pattern: ?[]const u8 = null,
    allowed_values: ?[]const []const u8 = null,
    custom_validator: ?*const fn (value: json.Value) ValidationError!void = null,

    /// Validates a JSON value against this rule
    pub fn validate(self: *const ValidationRule, value: ?json.Value) ValidationError!void {
        // Check if required field is present
        if (self.required and value == null) {
            logger.err("Required field '{s}' is missing", .{self.field_name}) catch {};
            return ValidationError.MissingRequiredField;
        }

        if (value == null) return; // Optional field not present

        const val = value.?;

        // String validation
        if (val == .string) {
            const str_val = val.string;
            
            if (self.min_length) |min| {
                if (str_val.len < min) {
                    logger.err("Field '{s}' is too short (min: {d}, actual: {d})", .{ self.field_name, min, str_val.len }) catch {};
                    return ValidationError.InvalidFieldValue;
                }
            }
            
            if (self.max_length) |max| {
                if (str_val.len > max) {
                    logger.err("Field '{s}' is too long (max: {d}, actual: {d})", .{ self.field_name, max, str_val.len }) catch {};
                    return ValidationError.InvalidFieldValue;
                }
            }

            if (self.allowed_values) |allowed| {
                var found = false;
                for (allowed) |allowed_val| {
                    if (std.mem.eql(u8, str_val, allowed_val)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    logger.err("Field '{s}' has invalid value '{s}'", .{ self.field_name, str_val }) catch {};
                    return ValidationError.InvalidFieldValue;
                }
            }
        }

        // Number validation
        if (val == .integer) {
            const int_val = val.integer;
            
            if (self.min_value) |min| {
                if (int_val < min) {
                    logger.err("Field '{s}' is too small (min: {d}, actual: {d})", .{ self.field_name, min, int_val }) catch {};
                    return ValidationError.InvalidFieldValue;
                }
            }
            
            if (self.max_value) |max| {
                if (int_val > max) {
                    logger.err("Field '{s}' is too large (max: {d}, actual: {d})", .{ self.field_name, max, int_val }) catch {};
                    return ValidationError.InvalidFieldValue;
                }
            }
        }

        // Custom validation
        if (self.custom_validator) |validator| {
            try validator(val);
        }
    }
};

/// Configuration schema for validation
pub const ConfigSchema = struct {
    version: ConfigVersion,
    rules: []const ValidationRule,
    allocator: std.mem.Allocator,

    /// Creates a new configuration schema
    pub fn init(allocator: std.mem.Allocator, version: ConfigVersion, rules: []const ValidationRule) ConfigSchema {
        return ConfigSchema{
            .version = version,
            .rules = rules,
            .allocator = allocator,
        };
    }

    /// Validates a configuration object against this schema
    pub fn validate(self: *const ConfigSchema, config: json.Value) ValidationError!void {
        logger.info("Validating configuration against schema version {s}", .{self.version.toString()}) catch {};

        if (config != .object) {
            return ValidationError.InvalidSchema;
        }

        const config_obj = config.object;

        // Validate each rule
        for (self.rules) |rule| {
            const field_value = config_obj.get(rule.field_name);
            try rule.validate(field_value);
        }

        logger.info("Configuration validation completed successfully", .{}) catch {};
    }
};

/// Hot-reload configuration manager
pub const HotReloadManager = struct {
    config_path: []const u8,
    last_modified: i128,
    callback: ?*const fn (new_config: types.Config) void,
    allocator: std.mem.Allocator,
    running: bool,

    /// Initializes hot-reload manager
    pub fn init(allocator: std.mem.Allocator, config_path: []const u8, callback: ?*const fn (new_config: types.Config) void) HotReloadManager {
        return HotReloadManager{
            .config_path = config_path,
            .last_modified = 0,
            .callback = callback,
            .allocator = allocator,
            .running = false,
        };
    }

    /// Starts monitoring configuration file for changes
    pub fn start(self: *HotReloadManager) !void {
        self.running = true;
        logger.info("Starting hot-reload monitoring for: {s}", .{self.config_path}) catch {};
        
        // Initial file modification time
        self.last_modified = try self.getFileModTime();
        
        // In a real implementation, this would run in a separate thread
        // For now, we provide the interface
    }

    /// Stops monitoring
    pub fn stop(self: *HotReloadManager) void {
        self.running = false;
        logger.info("Stopped hot-reload monitoring", .{}) catch {};
    }

    /// Checks if configuration file has been modified
    pub fn checkForUpdates(self: *HotReloadManager) !bool {
        if (!self.running) return false;

        const current_mod_time = try self.getFileModTime();
        if (current_mod_time > self.last_modified) {
            self.last_modified = current_mod_time;
            logger.info("Configuration file modified, triggering reload", .{}) catch {};
            
            if (self.callback) |callback| {
                // In a real implementation, we would load and parse the new config
                // callback(new_config);
            }
            
            return true;
        }
        
        return false;
    }

    /// Gets file modification time
    fn getFileModTime(self: *HotReloadManager) !i128 {
        const file = std.fs.cwd().openFile(self.config_path, .{}) catch |err| {
            logger.warn("Failed to open config file for mod time check: {s}", .{@errorName(err)}) catch {};
            return 0;
        };
        defer file.close();

        const stat = try file.stat();
        return stat.mtime;
    }
};

/// Configuration migration utilities
pub const ConfigMigration = struct {
    /// Migrates configuration from old version to current version
    pub fn migrate(allocator: std.mem.Allocator, old_config: json.Value, from_version: ConfigVersion, to_version: ConfigVersion) !json.Value {
        logger.info("Migrating configuration from {s} to {s}", .{ from_version.toString(), to_version.toString() }) catch {};

        if (from_version == to_version) {
            return old_config;
        }

        // Migration logic would go here
        // For now, we return the original config
        logger.warn("Configuration migration not yet implemented", .{}) catch {};
        return old_config;
    }
};

/// Predefined validation rules for common configuration fields
pub const CommonRules = struct {
    pub const proxmox_host = ValidationRule{
        .field_name = "host",
        .required = true,
        .min_length = 1,
        .max_length = 255,
        .pattern = "^[a-zA-Z0-9.-]+$",
    };

    pub const proxmox_port = ValidationRule{
        .field_name = "port",
        .required = true,
        .min_value = 1,
        .max_value = 65535,
    };

    pub const log_level = ValidationRule{
        .field_name = "log_level",
        .required = false,
        .allowed_values = &[_][]const u8{ "debug", "info", "warn", "error" },
    };

    pub const container_id = ValidationRule{
        .field_name = "id",
        .required = true,
        .min_length = 1,
        .max_length = 64,
        .pattern = "^[a-zA-Z0-9_-]+$",
    };
};

/// Creates a default schema for Proxmox LXCRI configuration
pub fn createDefaultSchema(allocator: std.mem.Allocator) !ConfigSchema {
    const rules = try allocator.alloc(ValidationRule, 4);
    rules[0] = CommonRules.proxmox_host;
    rules[1] = CommonRules.proxmox_port;
    rules[2] = CommonRules.log_level;
    rules[3] = CommonRules.container_id;

    return ConfigSchema.init(allocator, ConfigVersion.current, rules);
}

/// Validates a configuration file
pub fn validateConfigFile(allocator: std.mem.Allocator, config_path: []const u8) ValidationError!void {
    logger.info("Validating configuration file: {s}", .{config_path}) catch {};

    // Read and parse configuration file
    const file_content = std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| {
        logger.err("Failed to read config file: {s}", .{@errorName(err)}) catch {};
        return ValidationError.InvalidSchema;
    };
    defer allocator.free(file_content);

    const config_json = json.parseFromSlice(json.Value, allocator, file_content, .{}) catch |err| {
        logger.err("Failed to parse JSON config: {s}", .{@errorName(err)}) catch {};
        return ValidationError.InvalidSchema;
    };
    defer config_json.deinit();

    // Create and apply schema validation
    const schema = try createDefaultSchema(allocator);
    defer allocator.free(schema.rules);

    try schema.validate(config_json.value);
    logger.info("Configuration file validation successful", .{}) catch {};
}
