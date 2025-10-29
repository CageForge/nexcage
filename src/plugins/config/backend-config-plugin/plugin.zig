/// Backend Configuration Plugin
/// 
/// This plugin provides configuration options for backend plugins,
/// allowing users to configure backend-specific settings.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const config_extension = @import("../../../plugin/config_extension.zig");

/// Register configuration sections for backend plugins
fn registerSections(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) ![]config_extension.ConfigSection {
    _ = context;
    
    const sections = try allocator.alloc(config_extension.ConfigSection, 4);
    
    // Crun backend configuration
    sections[0] = config_extension.ConfigSection{
        .name = "crun",
        .description = "Crun OCI runtime configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enabled",
                .field_type = .boolean,
                .description = "Enable crun backend",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "priority",
                .field_type = .number,
                .description = "Backend priority (lower = higher priority)",
                .default_value = "10",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "binary_path",
                .field_type = .string,
                .description = "Path to crun binary",
                .default_value = "\"/usr/bin/crun\"",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "log_level",
                .field_type = .enum_value,
                .description = "Crun log level",
                .default_value = "\"warn\"",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .one_of,
                    .value = "debug,info,warn,error",
                },
            },
            config_extension.ConfigField{
                .name = "systemd_cgroup",
                .field_type = .boolean,
                .description = "Use systemd for cgroup management",
                .default_value = "false",
            },
        },
    };
    
    // Runc backend configuration
    sections[1] = config_extension.ConfigSection{
        .name = "runc",
        .description = "Runc OCI runtime configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enabled",
                .field_type = .boolean,
                .description = "Enable runc backend",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "priority",
                .field_type = .number,
                .description = "Backend priority (lower = higher priority)",
                .default_value = "20",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "binary_path",
                .field_type = .string,
                .description = "Path to runc binary",
                .default_value = "\"/usr/bin/runc\"",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "debug",
                .field_type = .boolean,
                .description = "Enable debug logging for runc",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "systemd_cgroup",
                .field_type = .boolean,
                .description = "Use systemd for cgroup management",
                .default_value = "false",
            },
        },
    };
    
    // Proxmox LXC backend configuration
    sections[2] = config_extension.ConfigSection{
        .name = "proxmox-lxc",
        .description = "Proxmox LXC backend configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enabled",
                .field_type = .boolean,
                .description = "Enable Proxmox LXC backend",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "priority",
                .field_type = .number,
                .description = "Backend priority (lower = higher priority)",
                .default_value = "30",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_host",
                .field_type = .string,
                .description = "Proxmox VE host address",
                .required = true,
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "3",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_port",
                .field_type = .number,
                .description = "Proxmox VE API port",
                .default_value = "8006",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_node",
                .field_type = .string,
                .description = "Proxmox VE node name",
                .default_value = "\"pve\"",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_token",
                .field_type = .string,
                .description = "Proxmox VE API token",
                .required = true,
                .sensitive = true,
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "10",
                },
            },
            config_extension.ConfigField{
                .name = "verify_ssl",
                .field_type = .boolean,
                .description = "Verify SSL certificates",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "timeout",
                .field_type = .number,
                .description = "API timeout in seconds",
                .default_value = "30",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "5",
                },
            },
        },
    };
    
    // Proxmox VM backend configuration
    sections[3] = config_extension.ConfigSection{
        .name = "proxmox-vm",
        .description = "Proxmox VM backend configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enabled",
                .field_type = .boolean,
                .description = "Enable Proxmox VM backend",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "priority",
                .field_type = .number,
                .description = "Backend priority (lower = higher priority)",
                .default_value = "40",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_host",
                .field_type = .string,
                .description = "Proxmox VE host address",
                .required = true,
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "3",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_port",
                .field_type = .number,
                .description = "Proxmox VE API port",
                .default_value = "8006",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_node",
                .field_type = .string,
                .description = "Proxmox VE node name",
                .default_value = "\"pve\"",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "proxmox_token",
                .field_type = .string,
                .description = "Proxmox VE API token",
                .required = true,
                .sensitive = true,
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_length,
                    .value = "10",
                },
            },
            config_extension.ConfigField{
                .name = "verify_ssl",
                .field_type = .boolean,
                .description = "Verify SSL certificates",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "vm_cores",
                .field_type = .number,
                .description = "Default VM CPU cores",
                .default_value = "2",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
            config_extension.ConfigField{
                .name = "vm_memory",
                .field_type = .number,
                .description = "Default VM memory in MB",
                .default_value = "2048",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "512",
                },
            },
            config_extension.ConfigField{
                .name = "vm_disk",
                .field_type = .number,
                .description = "Default VM disk size in GB",
                .default_value = "20",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "1",
                },
            },
        },
    };
    
    return sections;
}

/// Validate backend configuration
fn validateConfig(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !config_extension.ConfigResult {
    var errors = std.ArrayList(config_extension.ConfigValidationError).empty;
    defer errors.deinit(allocator);
    
    // Custom validation logic for backend configuration
    // Check that at least one backend is enabled
    const backends = [_][]const u8{ "crun", "runc", "proxmox-lxc", "proxmox-vm" };
    var any_enabled = false;
    
    for (backends) |backend| {
        const enabled_key = try std.fmt.allocPrint(allocator, "{s}.enabled", .{backend});
        defer allocator.free(enabled_key);
        
        if (context.getValue(enabled_key)) |value| {
            if (value.asBoolean()) |enabled| {
                if (enabled) {
                    any_enabled = true;
                    break;
                }
            }
        }
    }
    
    if (!any_enabled) {
        try errors.append(allocator, config_extension.ConfigValidationError{
            .field_name = try allocator.dupe(u8, "backends"),
            .error_type = .validation_failed,
            .message = try allocator.dupe(u8, "At least one backend must be enabled"),
        });
    }
    
    // Validate Proxmox backends have required fields when enabled
    const proxmox_backends = [_][]const u8{ "proxmox-lxc", "proxmox-vm" };
    for (proxmox_backends) |backend| {
        const enabled_key = try std.fmt.allocPrint(allocator, "{s}.enabled", .{backend});
        defer allocator.free(enabled_key);
        
        if (context.getValue(enabled_key)) |value| {
            if (value.asBoolean()) |enabled| {
                if (enabled) {
                    // Check required fields
                    const required_fields = [_][]const u8{ "proxmox_host", "proxmox_token" };
                    for (required_fields) |field| {
                        const field_key = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ backend, field });
                        defer allocator.free(field_key);
                        
                        if (context.getValue(field_key) == null) {
                            try errors.append(allocator, config_extension.ConfigValidationError{
                                .field_name = try allocator.dupe(u8, field_key),
                                .error_type = .missing_required_field,
                                .message = try std.fmt.allocPrint(
                                    allocator,
                                    "Field '{s}' is required when {s} backend is enabled",
                                    .{ field_key, backend }
                                ),
                            });
                        }
                    }
                }
            }
        }
    }
    
    if (errors.items.len > 0) {
        return config_extension.ConfigResult.failure(try errors.toOwnedSlice(allocator));
    }
    
    return config_extension.ConfigResult.isSuccess();
}

/// Apply backend configuration
fn applyConfig(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !void {
    _ = allocator;
    
    try context.logInfo("Applying backend configuration...", .{});
    
    // Apply configuration to backends
    const backends = [_][]const u8{ "crun", "runc", "proxmox-lxc", "proxmox-vm" };
    for (backends) |backend| {
        const enabled_key = try std.fmt.allocPrint(context.allocator, "{s}.enabled", .{backend});
        defer context.allocator.free(enabled_key);
        
        if (context.getValue(enabled_key)) |value| {
            if (value.asBoolean()) |enabled| {
                if (enabled) {
                    try context.logInfo("Backend {s} is enabled", .{backend});
                } else {
                    try context.logInfo("Backend {s} is disabled", .{backend});
                }
            }
        }
    }
    
    try context.logInfo("Backend configuration applied successfully", .{});
}

/// Get default configuration values
fn getDefaults(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !std.StringHashMap(config_extension.ConfigValue) {
    _ = context;
    
    var defaults = std.StringHashMap(config_extension.ConfigValue).init(allocator);
    
    // Add default values for common settings
    try defaults.put(
        try allocator.dupe(u8, "crun.enabled"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "runc.enabled"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "proxmox-lxc.enabled"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = false },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "proxmox-vm.enabled"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = false },
            .source = .default,
        }
    );
    
    return defaults;
}

/// Get plugin metadata
fn getMetadata() plugin.PluginMetadata {
    return plugin.PluginMetadata{
        .name = "backend-config-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Backend configuration plugin for NexCage",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 32,
            .max_cpu_percent = 2,
        },
        .provides_cli_commands = false,
        .provides_backend = false,
        .provides_integrations = false,
        .provides_monitoring = false,
    };
}

/// Initialize plugin
fn initPlugin(allocator: std.mem.Allocator, context: *config_extension.ConfigContext) !void {
    _ = allocator;
    try context.logInfo("Backend configuration plugin initialized", .{});
}

/// Deinitialize plugin
fn deinitPlugin(allocator: std.mem.Allocator, context: *config_extension.ConfigContext) void {
    _ = allocator;
    _ = context;
    // Cleanup logic if needed
}

/// Export the configuration extension interface
pub const extension = config_extension.ConfigExtension{
    .register_sections_fn = registerSections,
    .validate_config_fn = validateConfig,
    .apply_config_fn = applyConfig,
    .get_defaults_fn = getDefaults,
    .get_metadata_fn = getMetadata,
    .init_fn = initPlugin,
    .deinit_fn = deinitPlugin,
};

/// Export plugin metadata for registration
pub const metadata = getMetadata();