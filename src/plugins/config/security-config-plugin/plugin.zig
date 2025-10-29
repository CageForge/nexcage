/// Security Configuration Plugin
/// 
/// This plugin provides comprehensive security configuration options
/// for NexCage, including container security policies and restrictions.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const config_extension = @import("../../../plugin/config_extension.zig");

/// Register security configuration sections
fn registerSections(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) ![]config_extension.ConfigSection {
    _ = context;
    
    const sections = try allocator.alloc(config_extension.ConfigSection, 3);
    
    // Container security policies
    sections[0] = config_extension.ConfigSection{
        .name = "container_security",
        .description = "Container-level security configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "default_seccomp",
                .field_type = .boolean,
                .description = "Enable seccomp filtering by default",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_apparmor",
                .field_type = .boolean,
                .description = "Enable AppArmor confinement by default",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_selinux",
                .field_type = .boolean,
                .description = "Enable SELinux confinement by default",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "default_readonly_rootfs",
                .field_type = .boolean,
                .description = "Make container root filesystem read-only by default",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "default_no_new_privileges",
                .field_type = .boolean,
                .description = "Disable privilege escalation by default",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_user_namespace",
                .field_type = .boolean,
                .description = "Use user namespaces by default",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "allowed_capabilities",
                .field_type = .array,
                .description = "List of allowed Linux capabilities",
                .default_value = "[\"CAP_CHOWN\", \"CAP_DAC_OVERRIDE\", \"CAP_FSETID\", \"CAP_FOWNER\", \"CAP_SETGID\", \"CAP_SETUID\"]",
            },
            config_extension.ConfigField{
                .name = "forbidden_capabilities",
                .field_type = .array,
                .description = "List of forbidden Linux capabilities",
                .default_value = "[\"CAP_SYS_ADMIN\", \"CAP_NET_ADMIN\", \"CAP_SYS_MODULE\"]",
            },
        },
    };
    
    // Network security policies
    sections[1] = config_extension.ConfigSection{
        .name = "network_security",
        .description = "Network security configuration",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enable_network_policies",
                .field_type = .boolean,
                .description = "Enable network policy enforcement",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_network_isolation",
                .field_type = .boolean,
                .description = "Isolate container networks by default",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "allow_host_network",
                .field_type = .boolean,
                .description = "Allow containers to use host network",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "allow_privileged_ports",
                .field_type = .boolean,
                .description = "Allow binding to privileged ports (<1024)",
                .default_value = "false",
            },
            config_extension.ConfigField{
                .name = "max_port_range",
                .field_type = .number,
                .description = "Maximum port number containers can bind to",
                .default_value = "65535",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .max_value,
                    .value = "65535",
                },
            },
            config_extension.ConfigField{
                .name = "blocked_networks",
                .field_type = .array,
                .description = "List of network ranges to block",
                .default_value = "[\"169.254.0.0/16\", \"127.0.0.0/8\"]",
            },
            config_extension.ConfigField{
                .name = "enable_dns_filtering",
                .field_type = .boolean,
                .description = "Enable DNS request filtering",
                .default_value = "false",
            },
        },
    };
    
    // Resource limits and quotas
    sections[2] = config_extension.ConfigSection{
        .name = "resource_security",
        .description = "Resource limits and security quotas",
        .fields = &[_]config_extension.ConfigField{
            config_extension.ConfigField{
                .name = "enforce_memory_limits",
                .field_type = .boolean,
                .description = "Enforce memory limits on all containers",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_memory_limit_mb",
                .field_type = .number,
                .description = "Default memory limit in MB",
                .default_value = "512",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "64",
                },
            },
            config_extension.ConfigField{
                .name = "max_memory_limit_mb",
                .field_type = .number,
                .description = "Maximum memory limit in MB",
                .default_value = "4096",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "128",
                },
            },
            config_extension.ConfigField{
                .name = "enforce_cpu_limits",
                .field_type = .boolean,
                .description = "Enforce CPU limits on all containers",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_cpu_limit",
                .field_type = .number,
                .description = "Default CPU limit (cores)",
                .default_value = "1.0",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "0.1",
                },
            },
            config_extension.ConfigField{
                .name = "max_cpu_limit",
                .field_type = .number,
                .description = "Maximum CPU limit (cores)",
                .default_value = "4.0",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "0.5",
                },
            },
            config_extension.ConfigField{
                .name = "enforce_pid_limits",
                .field_type = .boolean,
                .description = "Enforce PID limits on containers",
                .default_value = "true",
            },
            config_extension.ConfigField{
                .name = "default_pid_limit",
                .field_type = .number,
                .description = "Default PID limit",
                .default_value = "1024",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "10",
                },
            },
            config_extension.ConfigField{
                .name = "max_file_descriptors",
                .field_type = .number,
                .description = "Maximum file descriptors per container",
                .default_value = "1024",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "64",
                },
            },
            config_extension.ConfigField{
                .name = "max_container_lifetime_hours",
                .field_type = .number,
                .description = "Maximum container lifetime in hours (0 = unlimited)",
                .default_value = "0",
                .validation = config_extension.ConfigField.ValidationRule{
                    .rule_type = .min_value,
                    .value = "0",
                },
            },
        },
    };
    
    return sections;
}

/// Validate security configuration
fn validateConfig(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !config_extension.ConfigResult {
    var errors = std.ArrayList(config_extension.ConfigValidationError).empty;
    defer errors.deinit(allocator);
    
    // Validate memory limits are consistent
    const default_memory = context.getValue("resource_security.default_memory_limit_mb");
    const max_memory = context.getValue("resource_security.max_memory_limit_mb");
    
    if (default_memory != null and max_memory != null) {
        const default_val = default_memory.?.asNumber() orelse 0;
        const max_val = max_memory.?.asNumber() orelse 0;
        
        if (default_val > max_val) {
            try errors.append(allocator, config_extension.ConfigValidationError{
                .field_name = try allocator.dupe(u8, "resource_security.default_memory_limit_mb"),
                .error_type = .validation_failed,
                .message = try allocator.dupe(u8, "Default memory limit cannot exceed maximum memory limit"),
            });
        }
    }
    
    // Validate CPU limits are consistent
    const default_cpu = context.getValue("resource_security.default_cpu_limit");
    const max_cpu = context.getValue("resource_security.max_cpu_limit");
    
    if (default_cpu != null and max_cpu != null) {
        const default_val = default_cpu.?.asNumber() orelse 0;
        const max_val = max_cpu.?.asNumber() orelse 0;
        
        if (default_val > max_val) {
            try errors.append(allocator, config_extension.ConfigValidationError{
                .field_name = try allocator.dupe(u8, "resource_security.default_cpu_limit"),
                .error_type = .validation_failed,
                .message = try allocator.dupe(u8, "Default CPU limit cannot exceed maximum CPU limit"),
            });
        }
    }
    
    // Validate that if network policies are enabled, some restrictions are in place
    const enable_policies = context.getValue("network_security.enable_network_policies");
    if (enable_policies != null) {
        if (enable_policies.?.asBoolean()) |enabled| {
            if (enabled) {
                const isolation = context.getValue("network_security.default_network_isolation");
                const host_network = context.getValue("network_security.allow_host_network");
                
                if (isolation != null and host_network != null) {
                    const isolation_enabled = isolation.?.asBoolean() orelse false;
                    const host_network_allowed = host_network.?.asBoolean() orelse false;
                    
                    if (!isolation_enabled and host_network_allowed) {
                        try errors.append(allocator, config_extension.ConfigValidationError{
                            .field_name = try allocator.dupe(u8, "network_security"),
                            .error_type = .validation_failed,
                            .message = try allocator.dupe(u8, "When network policies are enabled, either network isolation should be enabled or host network should be restricted"),
                        });
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

/// Apply security configuration
fn applyConfig(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !void {
    _ = allocator;
    
    try context.logInfo("Applying security configuration...", .{});
    
    // Log security policy status
    const seccomp = context.getValue("container_security.default_seccomp");
    if (seccomp) |value| {
        if (value.asBoolean()) |enabled| {
            try context.logInfo("Default seccomp filtering: {}", .{enabled});
        }
    }
    
    const apparmor = context.getValue("container_security.default_apparmor");
    if (apparmor) |value| {
        if (value.asBoolean()) |enabled| {
            try context.logInfo("Default AppArmor confinement: {}", .{enabled});
        }
    }
    
    const network_isolation = context.getValue("network_security.default_network_isolation");
    if (network_isolation) |value| {
        if (value.asBoolean()) |enabled| {
            try context.logInfo("Default network isolation: {}", .{enabled});
        }
    }
    
    const memory_limit = context.getValue("resource_security.default_memory_limit_mb");
    if (memory_limit) |value| {
        if (value.asNumber()) |limit| {
            try context.logInfo("Default memory limit: {d} MB", .{limit});
        }
    }
    
    try context.logInfo("Security configuration applied successfully", .{});
}

/// Get default security values
fn getDefaults(
    allocator: std.mem.Allocator,
    context: *config_extension.ConfigContext
) !std.StringHashMap(config_extension.ConfigValue) {
    _ = context;
    
    var defaults = std.StringHashMap(config_extension.ConfigValue).init(allocator);
    
    // Add default security values
    try defaults.put(
        try allocator.dupe(u8, "container_security.default_seccomp"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "container_security.default_apparmor"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "network_security.enable_network_policies"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    try defaults.put(
        try allocator.dupe(u8, "resource_security.enforce_memory_limits"),
        config_extension.ConfigValue{
            .value = std.json.Value{ .bool = true },
            .source = .default,
        }
    );
    
    return defaults;
}

/// Get plugin metadata
fn getMetadata() plugin.PluginMetadata {
    return plugin.PluginMetadata{
        .name = "security-config-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Security configuration plugin for NexCage",
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
    try context.logInfo("Security configuration plugin initialized", .{});
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