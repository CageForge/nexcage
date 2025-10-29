/// Core plugin types and interfaces
/// 
/// This module defines the fundamental plugin architecture including
/// plugin metadata, context, capabilities, and lifecycle management.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Semantic version structure for plugin versioning
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

    pub fn isCompatible(self: SemanticVersion, required: SemanticVersion) bool {
        // Compatible if major version matches and minor.patch >= required
        return self.major == required.major and
               (self.minor > required.minor or 
                (self.minor == required.minor and self.patch >= required.patch));
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
    container_list,
    container_info,

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

    // API access
    api_server,
    api_client,

    pub fn toString(self: Capability) []const u8 {
        return @tagName(self);
    }
};

/// Resource requirements for plugins
pub const ResourceRequirements = struct {
    max_memory_mb: u32 = 64,
    max_cpu_percent: u32 = 5,
    max_file_descriptors: u32 = 100,
    max_threads: u32 = 10,
    timeout_seconds: u32 = 30,
    max_network_connections: u32 = 50,
    max_disk_usage_mb: u32 = 100,

    pub fn validate(self: ResourceRequirements) bool {
        return self.max_memory_mb > 0 and self.max_memory_mb <= 2048 and
               self.max_cpu_percent > 0 and self.max_cpu_percent <= 100 and
               self.max_file_descriptors > 0 and self.max_file_descriptors <= 4096 and
               self.max_threads > 0 and self.max_threads <= 100 and
               self.timeout_seconds > 0 and self.timeout_seconds <= 300;
    }
};

/// Plugin metadata structure
pub const PluginMetadata = struct {
    name: []const u8,
    version: SemanticVersion,
    description: []const u8,
    author: []const u8 = "",
    homepage: []const u8 = "",
    license: []const u8 = "",
    api_version: u32,
    nexcage_version: SemanticVersion,
    dependencies: []const []const u8,
    capabilities: []const Capability,
    resource_requirements: ResourceRequirements,
    
    // Extension types this plugin provides
    provides_backend: bool = false,
    provides_cli_commands: bool = false,
    provides_integrations: bool = false,
    provides_monitoring: bool = false,

    pub fn deinit(self: *PluginMetadata, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        if (self.author.len > 0) allocator.free(self.author);
        if (self.homepage.len > 0) allocator.free(self.homepage);
        if (self.license.len > 0) allocator.free(self.license);
        allocator.free(self.dependencies);
        allocator.free(self.capabilities);
    }

    pub fn hasCapability(self: *const PluginMetadata, capability: Capability) bool {
        for (self.capabilities) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }

    pub fn validate(self: *const PluginMetadata) bool {
        return self.name.len > 0 and self.name.len <= 64 and
               self.description.len > 0 and self.description.len <= 512 and
               self.resource_requirements.validate();
    }
};

/// Plugin status enumeration
pub const PluginStatus = enum {
    unloaded,
    loading,
    loaded,
    error_state,
    disabled,
    unloading,

    pub fn toString(self: PluginStatus) []const u8 {
        return @tagName(self);
    }
};

/// Plugin health status
pub const HealthStatus = enum {
    healthy,
    degraded,
    unhealthy,
    unknown,

    pub fn toString(self: HealthStatus) []const u8 {
        return @tagName(self);
    }
};

/// Plugin information for external queries
pub const PluginInfo = struct {
    name: []const u8,
    version: SemanticVersion,
    description: []const u8,
    capabilities: []const Capability,
    status: PluginStatus,
    health: HealthStatus,
    memory_usage_mb: u32,
    cpu_usage_percent: f32,
    uptime_seconds: u64,

    pub fn deinit(self: *PluginInfo, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.description);
        allocator.free(self.capabilities);
    }
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

    pub fn isSuccess(self: CommandResult) bool {
        return self.exit_code == 0;
    }
};

// Forward declarations for complex types that will be defined in other modules
pub const PluginContext = @import("context.zig").PluginContext;
pub const PluginManager = opaque {};
pub const HookSystem = opaque {};
pub const SecuritySandbox = opaque {};

/// Plugin lifecycle hooks
pub const PluginHooks = struct {
    /// Called when plugin is loaded and initialized
    init: ?*const fn(*PluginContext) anyerror!void = null,

    /// Called when plugin is being unloaded
    deinit: ?*const fn(*PluginContext) void = null,

    /// Called when configuration is reloaded
    config_reload: ?*const fn(*PluginContext) anyerror!void = null,

    /// Called for periodic health checks
    health_check: ?*const fn(*PluginContext) anyerror!HealthStatus = null,

    /// Called before system shutdown
    pre_shutdown: ?*const fn(*PluginContext) anyerror!void = null,

    /// Called when plugin is suspended (for hot reload)
    plugin_suspend: ?*const fn(*PluginContext) anyerror!void = null,

    /// Called when plugin is resumed (after hot reload)
    plugin_resume: ?*const fn(*PluginContext) anyerror!void = null,
};

/// Plugin extension interfaces
pub const PluginExtensions = struct {
    /// Backend extension for container runtime implementations
    backend: ?*const BackendExtension = null,

    /// CLI command extensions
    cli_commands: ?[]const CLICommandExtension = null,

    /// Integration extensions for external services
    integrations: ?[]const IntegrationExtension = null,

    /// Monitoring and metrics extensions
    monitoring: ?*const MonitoringExtension = null,

    /// Security extensions
    security: ?*const SecurityExtension = null,
};

/// Main plugin structure
pub const Plugin = struct {
    const Self = @This();

    /// Plugin metadata
    metadata: PluginMetadata,

    /// Plugin context (set by plugin manager)
    context: ?*PluginContext = null,

    /// Lifecycle hooks
    hooks: PluginHooks,

    /// Plugin extensions
    extensions: PluginExtensions,

    /// Plugin-specific data (opaque to the framework)
    data: ?*anyopaque = null,

    /// Plugin status
    status: PluginStatus = .unloaded,

    /// Health status
    health: HealthStatus = .unknown,

    /// Runtime statistics
    stats: PluginStats = PluginStats{},

    pub fn init(allocator: Allocator, metadata: PluginMetadata) !*Self {
        const self = try allocator.create(Self);
        
        // Create a deep copy of metadata to avoid shared pointer issues
        const copied_metadata = PluginMetadata{
            .name = try allocator.dupe(u8, metadata.name),
            .version = metadata.version,
            .description = try allocator.dupe(u8, metadata.description),
            .author = if (metadata.author.len > 0) try allocator.dupe(u8, metadata.author) else "",
            .homepage = if (metadata.homepage.len > 0) try allocator.dupe(u8, metadata.homepage) else "",
            .license = if (metadata.license.len > 0) try allocator.dupe(u8, metadata.license) else "",
            .api_version = metadata.api_version,
            .nexcage_version = metadata.nexcage_version,
            .dependencies = try allocator.dupe([]const u8, metadata.dependencies),
            .capabilities = try allocator.dupe(Capability, metadata.capabilities),
            .resource_requirements = metadata.resource_requirements,
            .provides_backend = metadata.provides_backend,
            .provides_cli_commands = metadata.provides_cli_commands,
            .provides_integrations = metadata.provides_integrations,
            .provides_monitoring = metadata.provides_monitoring,
        };
        
        self.* = Self{
            .metadata = copied_metadata,
            .hooks = PluginHooks{},
            .extensions = PluginExtensions{},
        };
        return self;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.metadata.deinit(allocator);
        allocator.destroy(self);
    }

    /// Get plugin information for external queries
    pub fn getInfo(self: *const Self, allocator: Allocator) !PluginInfo {
        return PluginInfo{
            .name = try allocator.dupe(u8, self.metadata.name),
            .version = self.metadata.version,
            .description = try allocator.dupe(u8, self.metadata.description),
            .capabilities = try allocator.dupe(Capability, self.metadata.capabilities),
            .status = self.status,
            .health = self.health,
            .memory_usage_mb = self.stats.memory_usage_mb,
            .cpu_usage_percent = self.stats.cpu_usage_percent,
            .uptime_seconds = self.stats.uptime_seconds,
        };
    }

    /// Check if plugin has a specific capability
    pub fn hasCapability(self: *const Self, capability: Capability) bool {
        return self.metadata.hasCapability(capability);
    }

    /// Update plugin statistics
    pub fn updateStats(self: *Self, memory_mb: u32, cpu_percent: f32) void {
        self.stats.memory_usage_mb = memory_mb;
        self.stats.cpu_usage_percent = cpu_percent;
        self.stats.last_update = std.time.timestamp();
        
        if (self.status == .loaded) {
            self.stats.uptime_seconds = @intCast(std.time.timestamp() - self.stats.load_time);
        }
    }

    /// Set plugin status
    pub fn setStatus(self: *Self, status: PluginStatus) void {
        self.status = status;
        if (status == .loaded) {
            self.stats.load_time = std.time.timestamp();
        }
    }
};

/// Plugin runtime statistics
pub const PluginStats = struct {
    memory_usage_mb: u32 = 0,
    cpu_usage_percent: f32 = 0.0,
    uptime_seconds: u64 = 0,
    load_time: i64 = 0,
    last_update: i64 = 0,
    hooks_executed: u64 = 0,
    hooks_failed: u64 = 0,
    commands_executed: u64 = 0,
    commands_failed: u64 = 0,
};

// Extension type definitions (these will be implemented in separate files)

/// Backend extension interface
pub const BackendExtension = struct {
    name: []const u8,
    description: []const u8,
    version: SemanticVersion,
    
    // Function pointers for backend operations
    create: *const fn(*PluginContext, []const u8) anyerror!void,
    start: *const fn(*PluginContext, []const u8) anyerror!void,
    stop: *const fn(*PluginContext, []const u8) anyerror!void,
    delete: *const fn(*PluginContext, []const u8) anyerror!void,
    list: *const fn(*PluginContext, Allocator) anyerror![]const u8,
    info: *const fn(*PluginContext, []const u8, Allocator) anyerror![]const u8,
    exec: *const fn(*PluginContext, []const u8, []const []const u8, Allocator) anyerror!CommandResult,
};

/// CLI command extension interface
pub const CLICommandExtension = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    examples: []const []const u8,
    
    // Function pointers for CLI operations
    execute: *const fn(*PluginContext, []const []const u8, Allocator) anyerror!void,
    help: *const fn(*PluginContext, Allocator) anyerror![]const u8,
    validate: *const fn(*PluginContext, []const []const u8) anyerror!void,
    complete: ?*const fn(*PluginContext, []const []const u8, Allocator) anyerror![]const []const u8 = null,
};

/// Integration extension interface
pub const IntegrationExtension = struct {
    name: []const u8,
    description: []const u8,
    version: SemanticVersion,
    
    // Function pointers for integration operations
    connect: *const fn(*PluginContext, []const u8) anyerror!void,
    disconnect: *const fn(*PluginContext) anyerror!void,
    health_check: *const fn(*PluginContext) anyerror!HealthStatus,
    send_request: *const fn(*PluginContext, []const u8, Allocator) anyerror![]const u8,
};

/// Monitoring extension interface
pub const MonitoringExtension = struct {
    name: []const u8,
    description: []const u8,
    version: SemanticVersion,
    
    // Function pointers for monitoring operations
    collect_metrics: *const fn(*PluginContext, Allocator) anyerror![]const u8,
    export_metrics: *const fn(*PluginContext, []const u8) anyerror!void,
    create_alert: *const fn(*PluginContext, []const u8, []const u8) anyerror!void,
};

/// Security extension interface
pub const SecurityExtension = struct {
    name: []const u8,
    description: []const u8,
    version: SemanticVersion,
    
    // Function pointers for security operations
    authenticate: *const fn(*PluginContext, []const u8, []const u8) anyerror!bool,
    authorize: *const fn(*PluginContext, []const u8, []const u8) anyerror!bool,
    audit_log: *const fn(*PluginContext, []const u8) anyerror!void,
    encrypt: *const fn(*PluginContext, []const u8, Allocator) anyerror![]const u8,
    decrypt: *const fn(*PluginContext, []const u8, Allocator) anyerror![]const u8,
};

/// Test suite
const testing = std.testing;

test "SemanticVersion compatibility" {
    const v1_0_0 = SemanticVersion{ .major = 1, .minor = 0, .patch = 0 };
    const v1_0_1 = SemanticVersion{ .major = 1, .minor = 0, .patch = 1 };
    const v1_1_0 = SemanticVersion{ .major = 1, .minor = 1, .patch = 0 };
    const v2_0_0 = SemanticVersion{ .major = 2, .minor = 0, .patch = 0 };

    try testing.expect(v1_0_0.isCompatible(v1_0_0));
    try testing.expect(v1_0_1.isCompatible(v1_0_0));
    try testing.expect(v1_1_0.isCompatible(v1_0_0));
    try testing.expect(!v1_0_0.isCompatible(v1_0_1));
    try testing.expect(!v2_0_0.isCompatible(v1_0_0));
    try testing.expect(!v1_0_0.isCompatible(v2_0_0));
}

test "ResourceRequirements validation" {
    const valid = ResourceRequirements{
        .max_memory_mb = 128,
        .max_cpu_percent = 10,
        .max_file_descriptors = 256,
        .max_threads = 5,
        .timeout_seconds = 60,
    };
    try testing.expect(valid.validate());

    const invalid_memory = ResourceRequirements{
        .max_memory_mb = 0, // Invalid
        .max_cpu_percent = 10,
        .max_file_descriptors = 256,
        .max_threads = 5,
        .timeout_seconds = 60,
    };
    try testing.expect(!invalid_memory.validate());

    const invalid_cpu = ResourceRequirements{
        .max_memory_mb = 128,
        .max_cpu_percent = 150, // Invalid
        .max_file_descriptors = 256,
        .max_threads = 5,
        .timeout_seconds = 60,
    };
    try testing.expect(!invalid_cpu.validate());
}

test "PluginMetadata capabilities" {
    const metadata = PluginMetadata{
        .name = "test-plugin",
        .version = SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Test plugin",
        .api_version = 1,
        .nexcage_version = SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]Capability{ .logging, .container_create },
        .resource_requirements = ResourceRequirements{},
    };

    try testing.expect(metadata.hasCapability(.logging));
    try testing.expect(metadata.hasCapability(.container_create));
    try testing.expect(!metadata.hasCapability(.filesystem_write));
}

test "CommandResult success check" {
    const success_result = CommandResult{
        .exit_code = 0,
        .stdout = "success",
        .stderr = "",
        .duration_ms = 100,
    };
    try testing.expect(success_result.isSuccess());

    const failure_result = CommandResult{
        .exit_code = 1,
        .stdout = "",
        .stderr = "error",
        .duration_ms = 50,
    };
    try testing.expect(!failure_result.isSuccess());
}