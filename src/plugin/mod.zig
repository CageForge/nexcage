/// NexCage Plugin System
/// 
/// This module provides the core plugin framework for NexCage, enabling
/// secure, extensible, and performant plugin-based architecture.

pub const plugin = @import("plugin.zig");
pub const manager = @import("manager.zig");
pub const hooks = @import("hooks.zig");
pub const context = @import("context.zig");
pub const validation = @import("validation.zig");
pub const cli_extension = @import("cli_extension.zig");
pub const cli_manager = @import("cli_manager.zig");
pub const config_extension = @import("config_extension.zig");
pub const config_manager = @import("config_manager.zig");
pub const sandbox = @import("sandbox.zig");

// Re-export main types for convenience
pub const Plugin = plugin.Plugin;
pub const PluginManager = manager.PluginManager;
pub const HookSystem = hooks.HookSystem;
pub const PluginContext = context.PluginContext;
pub const CliExtension = cli_extension.CliExtension;
pub const CliPluginManager = cli_manager.CliPluginManager;
pub const CliContext = cli_extension.CliContext;
pub const CliCommand = cli_extension.CliCommand;
pub const ConfigExtension = config_extension.ConfigExtension;
pub const ConfigPluginManager = config_manager.ConfigPluginManager;
pub const ConfigContext = config_extension.ConfigContext;
pub const EnhancedConfig = config_manager.EnhancedConfig;
pub const SecuritySandbox = sandbox.SecuritySandbox;

// Plugin API version for compatibility
pub const PLUGIN_API_VERSION: u32 = 1;

// Common errors
pub const PluginError = error{
    PluginNotFound,
    IncompatibleVersion,
    InitializationFailed,
    SecurityViolation,
    DependencyMissing,
    ResourceExhausted,
    InvalidSignature,
    InvalidInput,
    RuntimeError,
    InsufficientCapabilities,
};

// Re-export key types
pub const PluginMetadata = plugin.PluginMetadata;
pub const PluginHooks = plugin.PluginHooks;
pub const Capability = plugin.Capability;
pub const SemanticVersion = plugin.SemanticVersion;
pub const HealthStatus = plugin.HealthStatus;
pub const PluginStatus = plugin.PluginStatus;
pub const ResourceRequirements = plugin.ResourceRequirements;

// Hook system types
pub const HookPriority = hooks.HookPriority;
pub const HookContext = hooks.HookContext;
pub const SystemHooks = hooks.SystemHooks;
pub const ContainerHooks = hooks.ContainerHooks;
pub const CLIHooks = hooks.CLIHooks;
pub const APIHooks = hooks.APIHooks;

// Manager configuration
pub const PluginManagerConfig = manager.PluginManagerConfig;

// Extension interfaces
pub const BackendExtension = plugin.BackendExtension;
pub const CLICommandExtension = plugin.CLICommandExtension;
pub const IntegrationExtension = plugin.IntegrationExtension;
pub const MonitoringExtension = plugin.MonitoringExtension;
pub const SecurityExtension = plugin.SecurityExtension;