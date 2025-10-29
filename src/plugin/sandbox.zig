/// Security Sandbox - Secure plugin execution environment
/// 
/// This module provides security isolation for plugins using various techniques
/// including namespaces, cgroups, seccomp, and capability restrictions.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const plugin = @import("plugin.zig");
const validation = @import("validation.zig");

/// File access types for validation
pub const FileAccessType = enum { 
    read, 
    write, 
    execute 
};

/// Network operations for validation
pub const NetworkOperation = enum { 
    connect, 
    bind, 
    listen 
};

/// Sandbox configuration
pub const SandboxConfig = struct {
    enable_namespace_isolation: bool = true,
    enable_seccomp: bool = true,
    enable_cgroups: bool = true,
    enable_chroot: bool = false,
    temp_dir: []const u8 = "/tmp/nexcage-plugins",
    max_open_files: u32 = 1024,
    max_memory_mb: u32 = 512,
    max_cpu_percent: u32 = 10,
    network_isolation: NetworkIsolation = .restricted,
    filesystem_access: FilesystemAccess = .read_only,

    pub const NetworkIsolation = enum {
        none,        // Full network access
        restricted,  // Limited network access
        isolated,    // No network access
    };

    pub const FilesystemAccess = enum {
        read_only,   // Read-only access to allowed paths
        read_write,  // Read-write access to allowed paths
        isolated,    // Access only to plugin sandbox directory
    };

    pub fn validate(self: *const SandboxConfig) bool {
        return self.max_open_files > 0 and self.max_open_files <= 4096 and
               self.max_memory_mb > 0 and self.max_memory_mb <= 4096 and
               self.max_cpu_percent > 0 and self.max_cpu_percent <= 100;
    }
};

/// Security sandbox errors
pub const SandboxError = error{
    SandboxCreationFailed,
    NamespaceCreationFailed,
    CgroupSetupFailed,
    SeccompSetupFailed,
    PermissionDenied,
    ResourceLimitExceeded,
    InvalidCapability,
    IsolationViolation,
} || Allocator.Error;

/// Resource usage statistics
pub const ResourceUsage = struct {
    memory_used_mb: u32 = 0,
    cpu_usage_percent: f32 = 0.0,
    open_files: u32 = 0,
    network_connections: u32 = 0,
    disk_read_mb: u32 = 0,
    disk_write_mb: u32 = 0,
    
    pub fn isWithinLimits(self: ResourceUsage, requirements: plugin.ResourceRequirements) bool {
        return self.memory_used_mb <= requirements.max_memory_mb and
               self.cpu_usage_percent <= @as(f32, @floatFromInt(requirements.max_cpu_percent)) and
               self.open_files <= requirements.max_file_descriptors;
    }
};

/// Security violation record
pub const SecurityViolation = struct {
    timestamp: i64,
    plugin_name: []const u8,
    violation_type: ViolationType,
    description: []const u8,
    severity: Severity,

    pub const ViolationType = enum {
        capability_violation,
        resource_limit_exceeded,
        filesystem_access_denied,
        network_access_denied,
        syscall_blocked,
        path_traversal_attempt,
    };

    pub const Severity = enum {
        low,
        medium,
        high,
        critical,
    };

    pub fn deinit(self: *SecurityViolation, allocator: Allocator) void {
        allocator.free(self.plugin_name);
        allocator.free(self.description);
    }
};

/// Main security sandbox manager
pub const SecuritySandbox = struct {
    const Self = @This();

    allocator: Allocator,
    config: SandboxConfig,
    enabled: bool,
    
    // Sandbox management
    active_sandboxes: std.StringHashMap(*PluginSandbox),
    security_violations: ArrayList(SecurityViolation),
    
    // Resource monitoring
    resource_monitor_enabled: bool = true,
    last_resource_check: i64 = 0,

    pub fn init(allocator: Allocator, config: SandboxConfig) !*Self {
        if (!config.validate()) {
            return SandboxError.SandboxCreationFailed;
        }

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = Self{
            .allocator = allocator,
            .config = config,
            .enabled = true,
            .active_sandboxes = std.StringHashMap(*PluginSandbox).init(allocator),
            .security_violations = ArrayList(SecurityViolation).empty,
        };

        // Initialize sandbox environment
        try self.initializeSandboxEnvironment();

        std.log.info("Security sandbox initialized (enabled: {})", .{self.enabled});
        return self;
    }

    pub fn deinit(self: *Self) void {
        // Destroy all active sandboxes
        var iterator = self.active_sandboxes.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.destroy();
        }
        self.active_sandboxes.deinit();

        // Clean up security violations
        for (self.security_violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.security_violations.deinit(self.allocator);

        self.allocator.destroy(self);
    }

    /// Create a new sandbox for a plugin
    pub fn createSandbox(
        self: *Self,
        plugin_name: []const u8,
        capabilities: []const plugin.Capability,
        requirements: plugin.ResourceRequirements,
    ) !*PluginSandbox {
        // Validate plugin name
        try validation.validateContainerId(plugin_name);

        if (!self.enabled) {
            return try PluginSandbox.createNoop(self.allocator, plugin_name);
        }

        // Check if sandbox already exists
        if (self.active_sandboxes.contains(plugin_name)) {
            return SandboxError.SandboxCreationFailed;
        }

        std.log.debug("Creating sandbox for plugin: {s}", .{plugin_name});

        const sandbox = try PluginSandbox.create(
            self.allocator,
            plugin_name,
            capabilities,
            requirements,
            self.config,
        );
        errdefer sandbox.destroy();

        // Register sandbox
        try self.active_sandboxes.put(try self.allocator.dupe(u8, plugin_name), sandbox);

        std.log.info("Sandbox created for plugin: {s}", .{plugin_name});
        return sandbox;
    }

    /// Destroy a sandbox
    pub fn destroySandbox(self: *Self, plugin_name: []const u8) void {
        if (self.active_sandboxes.fetchRemove(plugin_name)) |kv| {
            kv.value.destroy();
            self.allocator.free(kv.key);
            std.log.info("Sandbox destroyed for plugin: {s}", .{plugin_name});
        }
    }

    /// Get sandbox for a plugin
    pub fn getSandbox(self: *Self, plugin_name: []const u8) ?*PluginSandbox {
        return self.active_sandboxes.get(plugin_name);
    }

    /// Monitor resource usage of all sandboxes
    pub fn monitorResourceUsage(self: *Self) !std.StringHashMap(ResourceUsage) {
        if (!self.resource_monitor_enabled) {
            return std.StringHashMap(ResourceUsage).init(self.allocator);
        }

        var usage_map = std.StringHashMap(ResourceUsage).init(self.allocator);
        
        var iterator = self.active_sandboxes.iterator();
        while (iterator.next()) |entry| {
            const plugin_name = entry.key_ptr.*;
            const sandbox = entry.value_ptr.*;
            
            const usage = try sandbox.getResourceUsage();
            try usage_map.put(try self.allocator.dupe(u8, plugin_name), usage);
            
            // Check for resource violations
            if (!usage.isWithinLimits(sandbox.requirements)) {
                try self.recordSecurityViolation(SecurityViolation{
                    .timestamp = std.time.timestamp(),
                    .plugin_name = try self.allocator.dupe(u8, plugin_name),
                    .violation_type = .resource_limit_exceeded,
                    .description = try std.fmt.allocPrint(self.allocator, 
                        "Resource limits exceeded: memory={d}MB, cpu={d:.1}%",
                        .{ usage.memory_used_mb, usage.cpu_usage_percent }
                    ),
                    .severity = .high,
                });
            }
        }
        
        self.last_resource_check = std.time.timestamp();
        return usage_map;
    }

    /// Get security violations
    pub fn getSecurityViolations(self: *Self, allocator: Allocator) ![]SecurityViolation {
        var violations = ArrayList(SecurityViolation).empty;
        errdefer violations.deinit(allocator);

        for (self.security_violations.items) |violation| {
            try violations.append(allocator, SecurityViolation{
                .timestamp = violation.timestamp,
                .plugin_name = try allocator.dupe(u8, violation.plugin_name),
                .violation_type = violation.violation_type,
                .description = try allocator.dupe(u8, violation.description),
                .severity = violation.severity,
            });
        }

        return violations.toOwnedSlice(allocator);
    }

    /// Clear security violations
    pub fn clearSecurityViolations(self: *Self) void {
        for (self.security_violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.security_violations.clearRetainingCapacity();
    }

    // Private implementation methods

    fn initializeSandboxEnvironment(self: *Self) !void {
        // Create sandbox directory
        std.fs.cwd().makePath(self.config.temp_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        // Initialize cgroups if enabled
        if (self.config.enable_cgroups) {
            try self.setupGlobalCgroups();
        }

        // Initialize seccomp if enabled
        if (self.config.enable_seccomp) {
            try self.setupGlobalSeccomp();
        }

        std.log.debug("Sandbox environment initialized", .{});
    }

    fn setupGlobalCgroups(self: *Self) !void {
        // TODO: Implement cgroups v2 setup
        _ = self;
        std.log.debug("Global cgroups setup (not implemented)", .{});
    }

    fn setupGlobalSeccomp(self: *Self) !void {
        // TODO: Implement seccomp BPF setup
        _ = self;
        std.log.debug("Global seccomp setup (not implemented)", .{});
    }

    fn recordSecurityViolation(self: *Self, violation: SecurityViolation) !void {
        try self.security_violations.append(self.allocator, violation);
        
        std.log.warn("Security violation recorded: {s} - {} - {s}",
            .{ violation.plugin_name, violation.violation_type, violation.description }
        );

        // TODO: Implement security violation response (alerts, plugin suspension, etc.)
    }
};

/// Individual plugin sandbox
pub const PluginSandbox = struct {
    const Self = @This();

    allocator: Allocator,
    plugin_name: []const u8,
    capabilities: []const plugin.Capability,
    requirements: plugin.ResourceRequirements,
    config: SandboxConfig,
    sandbox_dir: []const u8,
    is_noop: bool,
    
    // Isolation state
    namespace_fd: ?std.posix.fd_t = null,
    cgroup_path: ?[]const u8 = null,
    seccomp_fd: ?std.posix.fd_t = null,
    
    // Resource tracking
    process_ids: ArrayList(std.posix.pid_t),
    start_time: i64,

    /// Create a real sandbox with isolation
    pub fn create(
        allocator: Allocator,
        plugin_name: []const u8,
        capabilities: []const plugin.Capability,
        requirements: plugin.ResourceRequirements,
        config: SandboxConfig,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const sandbox_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ config.temp_dir, plugin_name },
        );
        errdefer allocator.free(sandbox_dir);

        // Create sandbox directory
        try std.fs.cwd().makePath(sandbox_dir);

        self.* = Self{
            .allocator = allocator,
            .plugin_name = try allocator.dupe(u8, plugin_name),
            .capabilities = try allocator.dupe(plugin.Capability, capabilities),
            .requirements = requirements,
            .config = config,
            .sandbox_dir = sandbox_dir,
            .is_noop = false,
            .process_ids = ArrayList(std.posix.pid_t).empty,
            .start_time = std.time.timestamp(),
        };

        // Set up isolation mechanisms
        try self.setupIsolation();

        return self;
    }

    /// Create a no-op sandbox (when sandboxing is disabled)
    pub fn createNoop(allocator: Allocator, plugin_name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .plugin_name = try allocator.dupe(u8, plugin_name),
            .capabilities = &[_]plugin.Capability{},
            .requirements = plugin.ResourceRequirements{},
            .config = SandboxConfig{},
            .sandbox_dir = "",
            .is_noop = true,
            .process_ids = ArrayList(std.posix.pid_t).empty,
            .start_time = std.time.timestamp(),
        };
        return self;
    }

    pub fn destroy(self: *Self) void {
        if (!self.is_noop) {
            self.cleanupIsolation();
            
            // Remove sandbox directory
            std.fs.cwd().deleteTree(self.sandbox_dir) catch |err| {
                std.log.warn("Failed to cleanup sandbox directory {s}: {}", .{ self.sandbox_dir, err });
            };
            
            self.allocator.free(self.sandbox_dir);
            self.allocator.free(self.capabilities);
            
            if (self.cgroup_path) |path| {
                self.allocator.free(path);
            }
        }
        
        self.process_ids.deinit(self.allocator);
        self.allocator.free(self.plugin_name);
        self.allocator.destroy(self);
    }

    /// Execute a command within the sandbox
    pub fn executeCommand(self: *Self, args: []const []const u8) !plugin.CommandResult {
        // Validate command arguments
        try validation.validateCommandArgs(args);

        // Check if plugin has permission to execute commands (for both noop and real sandboxes)
        if (!self.hasCapability(.host_command)) {
            return SandboxError.PermissionDenied;
        }

        if (self.is_noop) {
            return self.executeCommandUnsandboxed(args);
        }

        return self.executeCommandSandboxed(args);
    }

    /// Check if sandbox has a specific capability
    pub fn hasCapability(self: *Self, capability: plugin.Capability) bool {
        for (self.capabilities) |cap| {
            if (cap == capability) return true;
        }
        return false;
    }

    /// Get current resource usage
    pub fn getResourceUsage(self: *Self) !ResourceUsage {
        if (self.is_noop) {
            return ResourceUsage{};
        }

        // TODO: Implement actual resource monitoring
        // This would read from cgroups, /proc, etc.
        
        return ResourceUsage{
            .memory_used_mb = 10, // Placeholder
            .cpu_usage_percent = 5.0, // Placeholder
            .open_files = 10, // Placeholder
        };
    }

    /// Validate file access
    pub fn validateFileAccess(self: *Self, path: []const u8, access_type: FileAccessType) !void {
        if (self.is_noop) {
            // Even no-op sandboxes should validate capabilities
            switch (access_type) {
                .read => {
                    if (!self.hasCapability(.filesystem_read)) {
                        return SandboxError.PermissionDenied;
                    }
                },
                .write, .execute => {
                    if (!self.hasCapability(.filesystem_write)) {
                        return SandboxError.PermissionDenied;
                    }
                },
            }
            return;
        }

        // Check capability requirements
        switch (access_type) {
            .read => {
                if (!self.hasCapability(.filesystem_read)) {
                    return SandboxError.PermissionDenied;
                }
            },
            .write, .execute => {
                if (!self.hasCapability(.filesystem_write)) {
                    return SandboxError.PermissionDenied;
                }
            },
        }

        // Validate path is within allowed boundaries
        const resolved_path = try validation.validatePath(path, self.sandbox_dir, self.allocator);
        defer self.allocator.free(resolved_path);

        // Additional access checks based on sandbox configuration
        switch (self.config.filesystem_access) {
            .isolated => {
                if (!std.mem.startsWith(u8, resolved_path, self.sandbox_dir)) {
                    return SandboxError.IsolationViolation;
                }
            },
            .read_only => {
                if (access_type == .write or access_type == .execute) {
                    return SandboxError.PermissionDenied;
                }
            },
            .read_write => {
                // Allow access to specified paths only
                // TODO: Implement path whitelist checking
            },
        }
    }

    /// Network access validation
    pub fn validateNetworkAccess(self: *Self, operation: NetworkOperation) !void {
        if (self.is_noop) {
            // Even no-op sandboxes should validate capabilities
            switch (operation) {
                .connect => {
                    if (!self.hasCapability(.network_client)) {
                        return SandboxError.PermissionDenied;
                    }
                },
                .bind, .listen => {
                    if (!self.hasCapability(.network_server)) {
                        return SandboxError.PermissionDenied;
                    }
                },
            }
            return;
        }

        switch (self.config.network_isolation) {
            .isolated => {
                return SandboxError.PermissionDenied;
            },
            .restricted => {
                // Only allow client connections, no server operations
                switch (operation) {
                    .connect => {
                        if (!self.hasCapability(.network_client)) {
                            return SandboxError.PermissionDenied;
                        }
                    },
                    .bind, .listen => {
                        return SandboxError.PermissionDenied;
                    },
                }
            },
            .none => {
                // Check specific capabilities
                switch (operation) {
                    .connect => {
                        if (!self.hasCapability(.network_client)) {
                            return SandboxError.PermissionDenied;
                        }
                    },
                    .bind, .listen => {
                        if (!self.hasCapability(.network_server)) {
                            return SandboxError.PermissionDenied;
                        }
                    },
                }
            },
        }
    }

    // Private implementation methods

    fn setupIsolation(self: *Self) !void {
        if (self.config.enable_namespace_isolation) {
            try self.setupNamespaces();
        }

        if (self.config.enable_seccomp) {
            try self.setupSeccomp();
        }

        if (self.config.enable_cgroups) {
            try self.setupCgroups();
        }

        if (self.config.enable_chroot) {
            try self.setupChroot();
        }

        std.log.debug("Isolation setup completed for plugin: {s}", .{self.plugin_name});
    }

    fn cleanupIsolation(self: *Self) void {
        // Clean up namespaces
        if (self.namespace_fd) |fd| {
            std.posix.close(fd);
        }

        // Clean up seccomp
        if (self.seccomp_fd) |fd| {
            std.posix.close(fd);
        }

        // Clean up cgroups
        if (self.cgroup_path) |path| {
            // TODO: Remove cgroup
            _ = path;
        }

        std.log.debug("Isolation cleanup completed for plugin: {s}", .{self.plugin_name});
    }

    fn setupNamespaces(self: *Self) !void {
        // TODO: Implement Linux namespace setup using unshare()
        // This would create PID, NET, MNT, USER namespaces as needed
        _ = self;
        std.log.debug("Namespace isolation setup (not implemented)", .{});
    }

    fn setupSeccomp(self: *Self) !void {
        // TODO: Implement seccomp-bpf filtering based on capabilities
        _ = self;
        std.log.debug("Seccomp filtering setup (not implemented)", .{});
    }

    fn setupCgroups(self: *Self) !void {
        // TODO: Implement cgroups v2 setup for resource limits
        const cgroup_name = try std.fmt.allocPrint(
            self.allocator,
            "nexcage-plugin-{s}",
            .{self.plugin_name}
        );
        self.cgroup_path = cgroup_name;
        
        std.log.debug("Cgroups setup for plugin: {s} (not implemented)", .{self.plugin_name});
    }

    fn setupChroot(self: *Self) !void {
        // TODO: Implement chroot jail setup
        _ = self;
        std.log.debug("Chroot setup (not implemented)", .{});
    }

    fn executeCommandUnsandboxed(self: *Self, args: []const []const u8) !plugin.CommandResult {
        const start_time = std.time.milliTimestamp();

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024, // 1MB limit
        });

        const end_time = std.time.milliTimestamp();

        return plugin.CommandResult{
            .exit_code = @intCast(result.term.Exited),
            .stdout = result.stdout,
            .stderr = result.stderr,
            .duration_ms = @intCast(end_time - start_time),
        };
    }

    fn executeCommandSandboxed(self: *Self, args: []const []const u8) !plugin.CommandResult {
        // TODO: Implement sandboxed command execution
        // This would set up the isolated environment and execute the command within it
        return self.executeCommandUnsandboxed(args);
    }
};

/// Test suite
const testing = std.testing;

test "SandboxConfig validation" {
    const valid_config = SandboxConfig{
        .max_open_files = 512,
        .max_memory_mb = 128,
        .max_cpu_percent = 25,
    };
    try testing.expect(valid_config.validate());

    const invalid_config = SandboxConfig{
        .max_open_files = 0, // Invalid
        .max_memory_mb = 128,
        .max_cpu_percent = 25,
    };
    try testing.expect(!invalid_config.validate());
}

test "ResourceUsage limit checking" {
    const usage = ResourceUsage{
        .memory_used_mb = 100,
        .cpu_usage_percent = 15.0,
        .open_files = 50,
    };

    const requirements = plugin.ResourceRequirements{
        .max_memory_mb = 128,
        .max_cpu_percent = 20,
        .max_file_descriptors = 100,
    };

    try testing.expect(usage.isWithinLimits(requirements));

    const excessive_usage = ResourceUsage{
        .memory_used_mb = 200, // Exceeds limit
        .cpu_usage_percent = 15.0,
        .open_files = 50,
    };

    try testing.expect(!excessive_usage.isWithinLimits(requirements));
}

test "PluginSandbox capability checking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const capabilities = [_]plugin.Capability{ .filesystem_read, .logging };
    const sandbox = try PluginSandbox.createNoop(allocator, "test-plugin");
    defer sandbox.destroy();

    // Manually set capabilities for test
    const capabilities_copy = try allocator.dupe(plugin.Capability, &capabilities);
    defer allocator.free(capabilities_copy);
    sandbox.capabilities = capabilities_copy;

    try testing.expect(sandbox.hasCapability(.filesystem_read));
    try testing.expect(sandbox.hasCapability(.logging));
    try testing.expect(!sandbox.hasCapability(.filesystem_write));
}

test "SecuritySandbox initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SandboxConfig{
        .max_open_files = 512,
        .max_memory_mb = 128,
        .max_cpu_percent = 25,
    };

    const sandbox = try SecuritySandbox.init(allocator, config);
    defer sandbox.deinit();

    try testing.expect(sandbox.enabled);
    try testing.expect(sandbox.config.max_open_files == 512);
    try testing.expect(sandbox.active_sandboxes.count() == 0);
}

test "SecuritySandbox plugin sandbox creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SandboxConfig{
        .enable_namespace_isolation = false,
        .enable_seccomp = false,
        .enable_cgroups = false,
    };

    const security_sandbox = try SecuritySandbox.init(allocator, config);
    defer security_sandbox.deinit();

    const capabilities = [_]plugin.Capability{ .filesystem_read, .logging };
    const requirements = plugin.ResourceRequirements{
        .max_memory_mb = 64,
        .max_cpu_percent = 10,
    };

    const plugin_sandbox = try security_sandbox.createSandbox(
        "test-plugin",
        &capabilities,
        requirements
    );
    defer security_sandbox.destroySandbox("test-plugin");

    try testing.expect(plugin_sandbox.hasCapability(.filesystem_read));
    try testing.expect(!plugin_sandbox.hasCapability(.filesystem_write));
}

test "SecuritySandbox invalid configuration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const invalid_config = SandboxConfig{
        .max_open_files = 0, // Invalid
        .max_memory_mb = 128,
        .max_cpu_percent = 25,
    };

    const result = SecuritySandbox.init(allocator, invalid_config);
    try testing.expectError(SandboxError.SandboxCreationFailed, result);
}

test "PluginSandbox no-op creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sandbox = try PluginSandbox.createNoop(allocator, "noop-plugin");
    defer sandbox.destroy();

    try testing.expect(sandbox.is_noop);
    try testing.expect(std.mem.eql(u8, sandbox.plugin_name, "noop-plugin"));
    try testing.expect(sandbox.capabilities.len == 0);
    try testing.expect(sandbox.sandbox_dir.len == 0);
}

test "PluginSandbox file access validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const capabilities = [_]plugin.Capability{ .filesystem_read };
    const sandbox = try PluginSandbox.createNoop(allocator, "test-plugin");
    defer sandbox.destroy();

    // Set capabilities for testing
    const capabilities_copy = try allocator.dupe(plugin.Capability, &capabilities);
    defer allocator.free(capabilities_copy);
    sandbox.capabilities = capabilities_copy;

    // Test read access (should succeed)
    try sandbox.validateFileAccess("/tmp/test.txt", .read);

    // Test write access (should fail - no capability)
    try testing.expectError(SandboxError.PermissionDenied, 
        sandbox.validateFileAccess("/tmp/test.txt", .write)
    );
}

test "PluginSandbox network access validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const capabilities = [_]plugin.Capability{ .network_client };
    const sandbox = try PluginSandbox.createNoop(allocator, "test-plugin");
    defer sandbox.destroy();

    // Set capabilities for testing
    const capabilities_copy = try allocator.dupe(plugin.Capability, &capabilities);
    defer allocator.free(capabilities_copy);
    sandbox.capabilities = capabilities_copy;

    // Test client connections (should succeed)
    try sandbox.validateNetworkAccess(.connect);

    // Test server operations (should fail - no capability)
    try testing.expectError(SandboxError.PermissionDenied, 
        sandbox.validateNetworkAccess(.bind)
    );
}

test "SecuritySandbox resource monitoring" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SandboxConfig{};
    const security_sandbox = try SecuritySandbox.init(allocator, config);
    defer security_sandbox.deinit();

    // Test empty monitoring
    var usage_map = try security_sandbox.monitorResourceUsage();
    defer usage_map.deinit();
    
    try testing.expect(usage_map.count() == 0);
}

test "SecuritySandbox security violations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SandboxConfig{};
    const security_sandbox = try SecuritySandbox.init(allocator, config);
    defer security_sandbox.deinit();

    // Test initial state
    const violations = try security_sandbox.getSecurityViolations(allocator);
    defer {
        for (violations) |*v| {
            v.deinit(allocator);
        }
        allocator.free(violations);
    }
    try testing.expect(violations.len == 0);

    // Test clearing violations
    security_sandbox.clearSecurityViolations();
    try testing.expect(security_sandbox.security_violations.items.len == 0);
}

test "SandboxConfig filesystem access modes" {
    const config = SandboxConfig{
        .filesystem_access = .isolated,
        .network_isolation = .restricted,
    };

    try testing.expect(config.filesystem_access == .isolated);
    try testing.expect(config.network_isolation == .restricted);
    try testing.expect(config.validate());
}

test "SecurityViolation record creation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var violation = SecurityViolation{
        .timestamp = std.time.timestamp(),
        .plugin_name = try allocator.dupe(u8, "test-plugin"),
        .violation_type = .capability_violation,
        .description = try allocator.dupe(u8, "Test violation"),
        .severity = .high,
    };
    defer violation.deinit(allocator);

    try testing.expect(violation.severity == .high);
    try testing.expect(violation.violation_type == .capability_violation);
    try testing.expect(std.mem.eql(u8, violation.plugin_name, "test-plugin"));
}

test "PluginSandbox command execution capability check" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create sandbox without host_command capability
    const capabilities = [_]plugin.Capability{ .logging };
    const sandbox = try PluginSandbox.createNoop(allocator, "test-plugin");
    defer sandbox.destroy();

    const capabilities_copy = try allocator.dupe(plugin.Capability, &capabilities);
    defer allocator.free(capabilities_copy);
    sandbox.capabilities = capabilities_copy;

    // Test command execution (should fail - no capability)
    const args = [_][]const u8{ "echo", "test" };
    try testing.expectError(SandboxError.PermissionDenied, 
        sandbox.executeCommand(&args)
    );
}

test "PluginSandbox resource usage reporting" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sandbox = try PluginSandbox.createNoop(allocator, "test-plugin");
    defer sandbox.destroy();

    // Test resource usage for no-op sandbox
    const usage = try sandbox.getResourceUsage();
    try testing.expect(usage.memory_used_mb == 0);
    try testing.expect(usage.cpu_usage_percent == 0.0);
    try testing.expect(usage.open_files == 0);
}

test "Multiple PluginSandbox instances" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = SandboxConfig{};
    const security_sandbox = try SecuritySandbox.init(allocator, config);
    defer security_sandbox.deinit();

    const capabilities = [_]plugin.Capability{ .logging };
    const requirements = plugin.ResourceRequirements{};

    // Create multiple sandboxes
    _ = try security_sandbox.createSandbox(
        "plugin-one",
        &capabilities,
        requirements
    );
    
    _ = try security_sandbox.createSandbox(
        "plugin-two",
        &capabilities,
        requirements
    );

    // Verify they exist independently
    try testing.expect(security_sandbox.getSandbox("plugin-one") != null);
    try testing.expect(security_sandbox.getSandbox("plugin-two") != null);
    try testing.expect(security_sandbox.active_sandboxes.count() == 2);

    // Clean up
    security_sandbox.destroySandbox("plugin-one");
    security_sandbox.destroySandbox("plugin-two");
    
    try testing.expect(security_sandbox.active_sandboxes.count() == 0);
}