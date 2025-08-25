# CRI Integration Implementation Plan - Phase 2

## 🎯 **Phase 2: CRI Integration Implementation - DETAILED PLAN**

**Date**: August 25, 2025  
**Time**: 6 hours (planned)  
**Status**: 📋 **PLANNING** - Ready to Start  
**Dependencies**: Phase 1 (Current Implementation Analysis) - ✅ **COMPLETED**

## 🚀 **Overview**

### **Objective**
Implement proper CRI (Container Runtime Interface) integration for the CreateContainer command, including CreateContainerRequest handling, PodSandbox validation, and configuration validation.

### **Scope**
- Create CRI request structures
- Implement PodSandbox validation
- Add configuration validation
- Update CLI argument parsing
- Integrate with existing CreateContainer logic

### **Success Criteria**
- [ ] CRI request handling working correctly
- [ ] PodSandbox validation implemented and tested
- [ ] Configuration validation working
- [ ] CLI integration completed
- [ ] All acceptance criteria met

## 🔧 **Technical Architecture**

### **CRI Request Flow**
```
Kubernetes API → CRI → CreateContainerRequest → PodSandbox Validation → Configuration Validation → Container Creation
```

### **Data Structures**
```zig
// CRI CreateContainerRequest
CreateContainerRequest {
    pod_sandbox_id: []const u8,
    config: ContainerConfig,
    sandbox_config: SandboxConfig,
}

// Container Configuration
ContainerConfig {
    metadata: ContainerMetadata,
    image: ImageSpec,
    command: []const []const u8,
    args: []const []const u8,
    working_dir: []const u8,
    envs: []const KeyValue,
    mounts: []const Mount,
    devices: []const Device,
    labels: StringMap,
    annotations: StringMap,
    log_path: []const u8,
    stdin: bool,
    stdin_once: bool,
    tty: bool,
    privileged: bool,
    security_context: SecurityContext,
    stdin_drain: bool,
}

// Sandbox Configuration
SandboxConfig {
    metadata: PodSandboxMetadata,
    hostname: []const u8,
    log_directory: []const u8,
    dns_config: DNSConfig,
    port_mappings: []const PortMapping,
    labels: StringMap,
    annotations: StringMap,
    linux: LinuxPodSandboxConfig,
    windows: ?WindowsPodSandboxConfig,
}
```

## 📋 **Step-by-Step Implementation Plan**

### **Step 1: Create CRI Request Structures (1.5 hours)**

#### **1.1 Create CRI Types Module**
**File**: `src/cri/types.zig`
**Purpose**: Define all CRI-specific data structures

```zig
// CRI v1.0.2 types
pub const CreateContainerRequest = struct {
    pod_sandbox_id: []const u8,
    config: ContainerConfig,
    sandbox_config: SandboxConfig,
    
    pub fn validate(self: *const Self) !void {
        // Validate request parameters
        if (self.pod_sandbox_id.len == 0) return error.InvalidPodSandboxId;
        try self.config.validate();
        try self.sandbox_config.validate();
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.pod_sandbox_id);
        self.config.deinit(allocator);
        self.sandbox_config.deinit(allocator);
    }
};

pub const ContainerConfig = struct {
    metadata: ContainerMetadata,
    image: ImageSpec,
    command: []const []const u8,
    args: []const []const u8,
    working_dir: []const u8,
    envs: []const KeyValue,
    mounts: []const Mount,
    devices: []const Device,
    labels: StringMap,
    annotations: StringMap,
    log_path: []const u8,
    stdin: bool,
    stdin_once: bool,
    tty: bool,
    privileged: bool,
    security_context: SecurityContext,
    stdin_drain: bool,
    
    pub fn validate(self: *const Self) !void {
        // Validate required fields
        try self.metadata.validate();
        try self.image.validate();
        
        // Validate command and args
        if (self.command.len == 0 and self.args.len == 0) {
            return error.MissingCommandOrArgs;
        }
        
        // Validate working directory
        if (self.working_dir.len > 0) {
            if (!std.mem.startsWith(u8, self.working_dir, "/")) {
                return error.InvalidWorkingDirectory;
            }
        }
        
        // Validate environment variables
        for (self.envs) |env| {
            try env.validate();
        }
        
        // Validate mounts
        for (self.mounts) |mount| {
            try mount.validate();
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.metadata.deinit(allocator);
        self.image.deinit(allocator);
        
        for (self.command) |cmd| allocator.free(cmd);
        allocator.free(self.command);
        
        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);
        
        allocator.free(self.working_dir);
        
        for (self.envs) |env| env.deinit(allocator);
        allocator.free(self.envs);
        
        for (self.mounts) |mount| mount.deinit(allocator);
        allocator.free(self.mounts);
        
        for (self.devices) |device| device.deinit(allocator);
        allocator.free(self.devices);
        
        self.labels.deinit(allocator);
        self.annotations.deinit(allocator);
        allocator.free(self.log_path);
        self.security_context.deinit(allocator);
    }
};

pub const SandboxConfig = struct {
    metadata: PodSandboxMetadata,
    hostname: []const u8,
    log_directory: []const u8,
    dns_config: DNSConfig,
    port_mappings: []const PortMapping,
    labels: StringMap,
    annotations: StringMap,
    linux: LinuxPodSandboxConfig,
    windows: ?WindowsPodSandboxConfig,
    
    pub fn validate(self: *const Self) !void {
        try self.metadata.validate();
        
        // Validate hostname
        if (self.hostname.len > 0) {
            if (self.hostname.len > 63) return error.HostnameTooLong;
            // Check for valid hostname characters
            for (self.hostname) |char| {
                if (!std.ascii.isAlphanumeric(char) and char != '-') {
                    return error.InvalidHostnameCharacter;
                }
            }
        }
        
        // Validate log directory
        if (self.log_directory.len > 0) {
            if (!std.mem.startsWith(u8, self.log_directory, "/")) {
                return error.InvalidLogDirectory;
            }
        }
        
        try self.dns_config.validate();
        
        // Validate port mappings
        for (self.port_mappings) |port| {
            try port.validate();
        }
        
        self.labels.validate();
        self.annotations.validate();
        try self.linux.validate();
        
        if (self.windows) |windows| {
            try windows.validate();
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.metadata.deinit(allocator);
        allocator.free(self.hostname);
        allocator.free(self.log_directory);
        self.dns_config.deinit(allocator);
        
        for (self.port_mappings) |port| port.deinit(allocator);
        allocator.free(self.port_mappings);
        
        self.labels.deinit(allocator);
        self.annotations.deinit(allocator);
        self.linux.deinit(allocator);
        
        if (self.windows) |windows| {
            windows.deinit(allocator);
        }
    }
};
```

#### **1.2 Create Supporting Types**
**File**: `src/cri/types.zig` (continued)

```zig
pub const ContainerMetadata = struct {
    name: []const u8,
    attempt: u32,
    
    pub fn validate(self: *const Self) !void {
        if (self.name.len == 0) return error.MissingContainerName;
        if (self.name.len > 63) return error.ContainerNameTooLong;
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

pub const ImageSpec = struct {
    image: []const u8,
    
    pub fn validate(self: *const Self) !void {
        if (self.image.len == 0) return error.MissingImageSpec;
        
        // Validate image format (name:tag or name@digest)
        if (std.mem.indexOf(u8, self.image, ":") == null and 
            std.mem.indexOf(u8, self.image, "@") == null) {
            return error.InvalidImageFormat;
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.image);
    }
};

pub const KeyValue = struct {
    key: []const u8,
    value: []const u8,
    
    pub fn validate(self: *const Self) !void {
        if (self.key.len == 0) return error.MissingKey;
        if (self.key.len > 63) return error.KeyTooLong;
        if (self.value.len > 4096) return error.ValueTooLong;
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.key);
        allocator.free(self.value);
    }
};

pub const Mount = struct {
    container_path: []const u8,
    host_path: []const u8,
    read_only: bool,
    selinux_relabel: bool,
    propagation: MountPropagation,
    
    pub fn validate(self: *const Self) !void {
        if (self.container_path.len == 0) return error.MissingContainerPath;
        if (self.host_path.len == 0) return error.MissingHostPath;
        
        // Validate container path is absolute
        if (!std.mem.startsWith(u8, self.container_path, "/")) {
            return error.InvalidContainerPath;
        }
        
        // Validate host path is absolute
        if (!std.mem.startsWith(u8, self.host_path, "/")) {
            return error.InvalidHostPath;
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.container_path);
        allocator.free(self.host_path);
    }
};

pub const SecurityContext = struct {
    privileged: bool,
    readonly_rootfs: bool,
    run_as_user: ?Int64Value,
    run_as_group: ?Int64Value,
    run_as_username: []const u8,
    namespace_options: ?NamespaceOption,
    supplemental_groups: []const i64,
    apparmor_profile: []const u8,
    seccomp_profile_path: []const u8,
    no_new_privs: bool,
    masked_paths: []const []const u8,
    readonly_paths: []const []const u8,
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.run_as_username.len > 0) allocator.free(self.run_as_username);
        if (self.apparmor_profile.len > 0) allocator.free(self.apparmor_profile);
        if (self.seccomp_profile_path.len > 0) allocator.free(self.seccomp_profile_path);
        
        for (self.masked_paths) |path| allocator.free(path);
        allocator.free(self.masked_paths);
        
        for (self.readonly_paths) |path| allocator.free(path);
        allocator.free(self.readonly_paths);
        
        allocator.free(self.supplemental_groups);
    }
};
```

### **Step 2: Implement PodSandbox Validation (1.5 hours)**

#### **2.1 Create PodSandbox Module**
**File**: `src/cri/pod_sandbox.zig`
**Purpose**: Handle PodSandbox validation and management

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const proxmox = @import("proxmox");

pub const PodSandbox = struct {
    id: []const u8,
    metadata: PodSandboxMetadata,
    state: PodSandboxState,
    created_at: i64,
    network: ?PodSandboxNetworkStatus,
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.id);
        self.metadata.deinit(allocator);
        if (self.network) |network| {
            network.deinit(allocator);
        }
    }
};

pub const PodSandboxState = enum {
    sandbox_ready,
    sandbox_notready,
};

pub const PodSandboxNetworkStatus = struct {
    ip: []const u8,
    additional_ips: []const []const u8,
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.ip);
        for (self.additional_ips) |additional_ip| {
            allocator.free(additional_ip);
        }
        allocator.free(self.additional_ips);
    }
};

pub const PodSandboxValidator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    proxmox_client: *proxmox.ProxmoxClient,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, proxmox_client: *proxmox.ProxmoxClient) PodSandboxValidator {
        return PodSandboxValidator{
            .allocator = allocator,
            .logger = logger,
            .proxmox_client = proxmox_client,
        };
    }
    
    pub fn validatePodSandbox(self: *PodSandboxValidator, pod_sandbox_id: []const u8) !PodSandbox {
        try self.logger.info("Validating PodSandbox: {s}", .{pod_sandbox_id});
        
        // Check if PodSandbox exists
        const sandbox = try self.getPodSandbox(pod_sandbox_id);
        if (sandbox == null) {
            try self.logger.err("PodSandbox not found: {s}", .{pod_sandbox_id});
            return error.PodSandboxNotFound;
        }
        
        // Validate PodSandbox state
        try self.validatePodSandboxState(sandbox.?);
        
        // Validate network configuration
        try self.validatePodSandboxNetwork(sandbox.?);
        
        try self.logger.info("PodSandbox validation successful: {s}", .{pod_sandbox_id});
        return sandbox.?;
    }
    
    fn getPodSandbox(self: *PodSandboxValidator, pod_sandbox_id: []const u8) !?PodSandbox {
        // Query Proxmox for PodSandbox information
        // This would typically involve checking Proxmox LXC containers or VMs
        // For now, we'll implement a basic check
        
        try self.logger.debug("Querying PodSandbox: {s}", .{pod_sandbox_id});
        
        // Check if container exists in Proxmox
        const container_exists = try self.proxmox_client.containerExists(pod_sandbox_id);
        if (!container_exists) {
            return null;
        }
        
        // Get container information
        const container_info = try self.proxmox_client.getContainerInfo(pod_sandbox_id);
        
        // Convert to PodSandbox
        var sandbox = PodSandbox{
            .id = try self.allocator.dupe(u8, pod_sandbox_id),
            .metadata = try self.createPodSandboxMetadata(pod_sandbox_id),
            .state = .sandbox_ready, // Assume ready if exists
            .created_at = container_info.created_at,
            .network = try self.getPodSandboxNetworkStatus(container_info),
        };
        
        return sandbox;
    }
    
    fn validatePodSandboxState(self: *PodSandboxValidator, sandbox: PodSandbox) !void {
        if (sandbox.state != .sandbox_ready) {
            try self.logger.err("PodSandbox not ready: {s}, state: {s}", .{
                sandbox.id,
                @tagName(sandbox.state),
            });
            return error.PodSandboxNotReady;
        }
        
        try self.logger.debug("PodSandbox state validation passed: {s}", .{sandbox.id});
    }
    
    fn validatePodSandboxNetwork(self: *PodSandboxValidator, sandbox: PodSandbox) !void {
        if (sandbox.network) |network| {
            // Validate IP address format
            if (network.ip.len > 0) {
                try self.validateIPAddress(network.ip);
            }
            
            // Validate additional IPs
            for (network.additional_ips) |ip| {
                try self.validateIPAddress(ip);
            }
        }
        
        try self.logger.debug("PodSandbox network validation passed: {s}", .{sandbox.id});
    }
    
    fn validateIPAddress(self: *PodSandboxValidator, ip: []const u8) !void {
        // Basic IP address validation
        if (ip.len == 0) return;
        
        var parts = std.mem.split(u8, ip, ".");
        var part_count: u32 = 0;
        
        while (parts.next()) |part| {
            part_count += 1;
            if (part_count > 4) return error.InvalidIPAddress;
            
            const num = std.fmt.parseInt(u8, part, 10) catch return error.InvalidIPAddress;
            if (num > 255) return error.InvalidIPAddress;
        }
        
        if (part_count != 4) return error.InvalidIPAddress;
    }
    
    fn createPodSandboxMetadata(self: *PodSandboxValidator, pod_sandbox_id: []const u8) !PodSandboxMetadata {
        // Create basic metadata for the PodSandbox
        return PodSandboxMetadata{
            .name = try self.allocator.dupe(u8, pod_sandbox_id),
            .uid = try self.allocator.dupe(u8, "default"),
            .namespace = try self.allocator.dupe(u8, "default"),
            .attempt = 0,
        };
    }
    
    fn getPodSandboxNetworkStatus(self: *PodSandboxValidator, container_info: proxmox.ContainerInfo) !?PodSandboxNetworkStatus {
        // Extract network information from container info
        if (container_info.network) |network| {
            var additional_ips = std.ArrayList([]const u8).init(self.allocator);
            
            // Add additional IPs if available
            if (network.additional_ips) |ips| {
                for (ips) |ip| {
                    try additional_ips.append(try self.allocator.dupe(u8, ip));
                }
            }
            
            return PodSandboxNetworkStatus{
                .ip = try self.allocator.dupe(u8, network.ip orelse ""),
                .additional_ips = additional_ips.toOwnedSlice(),
            };
        }
        
        return null;
    }
};
```

#### **2.2 Add PodSandbox Types**
**File**: `src/cri/types.zig` (continued)

```zig
pub const PodSandboxMetadata = struct {
    name: []const u8,
    uid: []const u8,
    namespace: []const u8,
    attempt: u32,
    
    pub fn validate(self: *const Self) !void {
        if (self.name.len == 0) return error.MissingPodSandboxName;
        if (self.uid.len == 0) return error.MissingPodSandboxUID;
        if (self.namespace.len == 0) return error.MissingPodSandboxNamespace;
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.uid);
        allocator.free(self.namespace);
    }
};
```

### **Step 3: Add Configuration Validation (1.5 hours)**

#### **3.1 Create Configuration Validator**
**File**: `src/cri/validator.zig`
**Purpose**: Validate ContainerConfig and SandboxConfig

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("cri").types;

pub const ConfigurationValidator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) ConfigurationValidator {
        return ConfigurationValidator{
            .allocator = allocator,
            .logger = logger,
        };
    }
    
    pub fn validateContainerConfig(self: *ConfigurationValidator, config: types.ContainerConfig) !void {
        try self.logger.info("Validating ContainerConfig for container: {s}", .{config.metadata.name});
        
        // Validate metadata
        try config.metadata.validate();
        
        // Validate image specification
        try config.image.validate();
        
        // Validate command and arguments
        try self.validateCommandAndArgs(config.command, config.args);
        
        // Validate working directory
        try self.validateWorkingDirectory(config.working_dir);
        
        // Validate environment variables
        try self.validateEnvironmentVariables(config.envs);
        
        // Validate mounts
        try self.validateMounts(config.mounts);
        
        // Validate devices
        try self.validateDevices(config.devices);
        
        // Validate security context
        try self.validateSecurityContext(config.security_context);
        
        try self.logger.info("ContainerConfig validation successful: {s}", .{config.metadata.name});
    }
    
    pub fn validateSandboxConfig(self: *ConfigurationValidator, config: types.SandboxConfig) !void {
        try self.logger.info("Validating SandboxConfig for sandbox: {s}", .{config.metadata.name});
        
        // Validate metadata
        try config.metadata.validate();
        
        // Validate hostname
        try self.validateHostname(config.hostname);
        
        // Validate log directory
        try self.validateLogDirectory(config.log_directory);
        
        // Validate DNS configuration
        try config.dns_config.validate();
        
        // Validate port mappings
        try self.validatePortMappings(config.port_mappings);
        
        // Validate Linux-specific configuration
        try config.linux.validate();
        
        // Validate Windows configuration if present
        if (config.windows) |windows| {
            try windows.validate();
        }
        
        try self.logger.info("SandboxConfig validation successful: {s}", .{config.metadata.name});
    }
    
    fn validateCommandAndArgs(self: *ConfigurationValidator, command: []const []const u8, args: []const []const u8) !void {
        // At least one of command or args must be provided
        if (command.len == 0 and args.len == 0) {
            return error.MissingCommandOrArgs;
        }
        
        // Validate command if provided
        if (command.len > 0) {
            for (command) |cmd| {
                if (cmd.len == 0) return error.EmptyCommand;
                if (cmd.len > 1024) return error.CommandTooLong;
            }
        }
        
        // Validate args if provided
        if (args.len > 0) {
            for (args) |arg| {
                if (arg.len > 1024) return error.ArgumentTooLong;
            }
        }
    }
    
    fn validateWorkingDirectory(self: *ConfigurationValidator, working_dir: []const u8) !void {
        if (working_dir.len == 0) return; // Optional field
        
        // Must be absolute path
        if (!std.mem.startsWith(u8, working_dir, "/")) {
            return error.InvalidWorkingDirectory;
        }
        
        // Must not contain ".." for security
        if (std.mem.indexOf(u8, working_dir, "..") != null) {
            return error.InvalidWorkingDirectory;
        }
        
        // Must not be too long
        if (working_dir.len > 4096) {
            return error.WorkingDirectoryTooLong;
        }
    }
    
    fn validateEnvironmentVariables(self: *ConfigurationValidator, envs: []const types.KeyValue) !void {
        for (envs) |env| {
            try env.validate();
            
            // Check for duplicate keys
            for (envs) |other_env| {
                if (std.mem.eql(u8, env.key, other_env.key) and 
                    &env != &other_env) {
                    return error.DuplicateEnvironmentVariable;
                }
            }
        }
    }
    
    fn validateMounts(self: *ConfigurationValidator, mounts: []const types.Mount) !void {
        for (mounts) |mount| {
            try mount.validate();
            
            // Validate mount paths don't contain ".."
            if (std.mem.indexOf(u8, mount.container_path, "..") != null) {
                return error.InvalidMountPath;
            }
            if (std.mem.indexOf(u8, mount.host_path, "..") != null) {
                return error.InvalidMountPath;
            }
        }
    }
    
    fn validateDevices(self: *ConfigurationValidator, devices: []const types.Device) !void {
        for (devices) |device| {
            try device.validate();
        }
    }
    
    fn validateSecurityContext(self: *ConfigurationValidator, security_context: types.SecurityContext) !void {
        // Validate user/group IDs
        if (security_context.run_as_user) |user| {
            if (user.value < 0) return error.InvalidUserID;
        }
        if (security_context.run_as_group) |group| {
            if (group.value < 0) return error.InvalidGroupID;
        }
        
        // Validate supplemental groups
        for (security_context.supplemental_groups) |group_id| {
            if (group_id < 0) return error.InvalidGroupID;
        }
        
        // Validate profile paths
        if (security_context.apparmor_profile.len > 0) {
            if (!std.mem.startsWith(u8, security_context.apparmor_profile, "/")) {
                return error.InvalidAppArmorProfilePath;
            }
        }
        if (security_context.seccomp_profile_path.len > 0) {
            if (!std.mem.startsWith(u8, security_context.seccomp_profile_path, "/")) {
                return error.InvalidSeccompProfilePath;
            }
        }
    }
    
    fn validateHostname(self: *ConfigurationValidator, hostname: []const u8) !void {
        if (hostname.len == 0) return; // Optional field
        
        // Must not be too long
        if (hostname.len > 63) {
            return error.HostnameTooLong;
        }
        
        // Must contain only valid characters
        for (hostname) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '-') {
                return error.InvalidHostnameCharacter;
            }
        }
        
        // Must not start or end with hyphen
        if (hostname[0] == '-' or hostname[hostname.len - 1] == '-') {
            return error.InvalidHostnameFormat;
        }
    }
    
    fn validateLogDirectory(self: *ConfigurationValidator, log_directory: []const u8) !void {
        if (log_directory.len == 0) return; // Optional field
        
        // Must be absolute path
        if (!std.mem.startsWith(u8, log_directory, "/")) {
            return error.InvalidLogDirectory;
        }
        
        // Must not contain ".." for security
        if (std.mem.indexOf(u8, log_directory, "..") != null) {
            return error.InvalidLogDirectory;
        }
        
        // Must not be too long
        if (log_directory.len > 4096) {
            return error.LogDirectoryTooLong;
        }
    }
    
    fn validatePortMappings(self: *ConfigurationValidator, port_mappings: []const types.PortMapping) !void {
        for (port_mappings) |port| {
            try port.validate();
            
            // Validate port numbers
            if (port.container_port < 1 or port.container_port > 65535) {
                return error.InvalidContainerPort;
            }
            if (port.host_port < 1 or port.host_port > 65535) {
                return error.InvalidHostPort;
            }
        }
    }
};
```

### **Step 4: Update CLI Argument Parsing (1 hour)**

#### **4.1 Update CLI Arguments**
**File**: `src/common/cli_args.zig`
**Purpose**: Add CRI-specific command line arguments

```zig
// Add CRI-specific options to RuntimeOptions
pub const RuntimeOptions = struct {
    root: ?[]const u8 = null,
    log: ?[]const u8 = null,
    log_format: ?[]const u8 = null,
    systemd_cgroup: bool = false,
    bundle: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    debug: bool = false,
    
    // CRI-specific options
    pod_sandbox_id: ?[]const u8 = null,
    config_file: ?[]const u8 = null,
    sandbox_config_file: ?[]const u8 = null,
    runtime_type: ?[]const u8 = null,
    
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RuntimeOptions {
        return RuntimeOptions{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *RuntimeOptions) void {
        if (self.root) |root| self.allocator.free(root);
        if (self.log) |log| self.allocator.free(log);
        if (self.log_format) |log_format| self.allocator.free(log_format);
        if (self.bundle) |bundle| self.allocator.free(bundle);
        if (self.pid_file) |pid_file| self.allocator.free(pid_file);
        if (self.console_socket) |console_socket| self.allocator.free(console_socket);
        if (self.pod_sandbox_id) |pod_sandbox_id| self.allocator.free(pod_sandbox_id);
        if (self.config_file) |config_file| self.allocator.free(config_file);
        if (self.sandbox_config_file) |sandbox_config_file| self.allocator.free(sandbox_config_file);
        if (self.runtime_type) |runtime_type| self.allocator.free(runtime_type);
    }
};

// Update argument parsing to handle CRI options
pub fn parseArgsFromArray(allocator: std.mem.Allocator, argv: []const []const u8) !struct {
    command: Command,
    options: RuntimeOptions,
    container_id: ?[]const u8,
} {
    var i: usize = 1; // Skip program name
    var command: ?Command = null;
    var options = RuntimeOptions.init(allocator);
    var container_id: ?[]const u8 = null;
    var has_args = false;
    
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        has_args = true;
        
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            options.debug = true;
        } else if (std.mem.eql(u8, arg, "--systemd-cgroup")) {
            options.systemd_cgroup = true;
        } else if (std.mem.eql(u8, arg, "--root")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.root = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--log")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.log = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--log-format")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.log_format = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.bundle = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--pid-file")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.pid_file = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--console-socket")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.console_socket = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--pod-sandbox-id")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.pod_sandbox_id = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.config_file = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--sandbox-config")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.sandbox_config_file = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--runtime-type")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.runtime_type = try allocator.dupe(u8, argv[i]);
            }
        } else if (command == null) {
            command = parseCommand(arg);
            if (command.? == .unknown) {
                return error.UnknownCommand;
            }
        } else {
            if (container_id == null) {
                container_id = try allocator.dupe(u8, arg);
            }
        }
    }
    
    if (command == null) {
        return error.MissingCommand;
    }
    
    return .{
        .command = command.?,
        .options = options,
        .container_id = container_id,
    };
}
```

### **Step 5: Integrate with CreateContainer Logic (0.5 hours)**

#### **5.1 Update CreateContainer Function**
**File**: `src/oci/create.zig`
**Purpose**: Integrate CRI validation with existing CreateContainer logic

```zig
// Add CRI integration to the main create function
pub fn create(opts: CreateOpts, proxmox_client: *proxmox.ProxmoxClient) !void {
    const logger = logger_mod.Logger.init(opts.allocator, .info, null);
    defer logger.deinit();

    try logger.info("Creating container {s} with bundle {s}", .{ opts.id, opts.bundle_path });

    // CRI Integration: Validate PodSandbox if provided
    if (opts.pod_sandbox_id) |pod_sandbox_id| {
        try logger.info("Validating PodSandbox: {s}", .{pod_sandbox_id});
        
        var pod_sandbox_validator = PodSandboxValidator.init(opts.allocator, &logger, proxmox_client);
        const sandbox = try pod_sandbox_validator.validatePodSandbox(pod_sandbox_id);
        defer sandbox.deinit(opts.allocator);
        
        try logger.info("PodSandbox validation successful: {s}", .{pod_sandbox_id});
    }

    // CRI Integration: Validate configuration if provided
    if (opts.config) |config| {
        try logger.info("Validating ContainerConfig", .{});
        
        var config_validator = ConfigurationValidator.init(opts.allocator, &logger);
        try config_validator.validateContainerConfig(config);
        
        try logger.info("ContainerConfig validation successful", .{});
    }

    // CRI Integration: Validate sandbox configuration if provided
    if (opts.sandbox_config) |sandbox_config| {
        try logger.info("Validating SandboxConfig", .{});
        
        var config_validator = ConfigurationValidator.init(opts.allocator, &logger);
        try config_validator.validateSandboxConfig(sandbox_config);
        
        try logger.info("SandboxConfig validation successful", .{});
    }

    // Continue with existing logic...
    // ... (rest of the existing create function)
}
```

#### **5.2 Update CreateOpts Structure**
**File**: `src/oci/create.zig`

```zig
pub const CreateOpts = struct {
    config_path: []const u8,
    id: []const u8,
    bundle_path: []const u8,
    allocator: Allocator,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    detach: bool = false,
    no_pivot: bool = false,
    no_new_keyring: bool = false,
    preserve_fds: u32 = 0,
    
    // CRI-specific fields
    pod_sandbox_id: ?[]const u8 = null,
    config: ?cri_types.ContainerConfig = null,
    sandbox_config: ?cri_types.SandboxConfig = null,
    runtime_type: ?oci_types.RuntimeType = null,

    pub fn deinit(self: *CreateOpts, allocator: Allocator) void {
        allocator.free(self.config_path);
        allocator.free(self.id);
        allocator.free(self.bundle_path);
        if (self.pid_file) |pid_file| allocator.free(pid_file);
        if (self.console_socket) |console_socket| allocator.free(console_socket);
        if (self.pod_sandbox_id) |pod_sandbox_id| allocator.free(pod_sandbox_id);
        if (self.config) |config| config.deinit(allocator);
        if (self.sandbox_config) |sandbox_config| sandbox_config.deinit(allocator);
    }
};
```

## 📊 **Implementation Timeline**

### **Step 1: Create CRI Request Structures (1.5 hours)**
- **1.1**: Create CRI Types Module (1 hour)
- **1.2**: Create Supporting Types (0.5 hours)

### **Step 2: Implement PodSandbox Validation (1.5 hours)**
- **2.1**: Create PodSandbox Module (1 hour)
- **2.2**: Add PodSandbox Types (0.5 hours)

### **Step 3: Add Configuration Validation (1.5 hours)**
- **3.1**: Create Configuration Validator (1 hour)
- **3.2**: Add Validation Logic (0.5 hours)

### **Step 4: Update CLI Argument Parsing (1 hour)**
- **4.1**: Update CLI Arguments (1 hour)

### **Step 5: Integrate with CreateContainer Logic (0.5 hours)**
- **5.1**: Update CreateContainer Function (0.3 hours)
- **5.2**: Update CreateOpts Structure (0.2 hours)

## 🏆 **Success Metrics**

### **Phase 2 Completion Criteria**
- [ ] CRI request structures created and tested
- [ ] PodSandbox validation implemented and working
- [ ] Configuration validation implemented and working
- [ ] CLI integration completed
- [ ] All acceptance criteria met

### **Testing Requirements**
- [ ] Unit tests for CRI types
- [ ] Unit tests for PodSandbox validation
- [ ] Unit tests for configuration validation
- [ ] Integration tests for CLI parsing
- [ ] End-to-end tests for CreateContainer with CRI

## 🔄 **Risk Assessment**

### **High Risk Items**
- **Complexity**: CRI integration involves multiple components
- **Dependencies**: Requires Proxmox API integration for PodSandbox validation
- **Testing**: Comprehensive testing required for validation logic

### **Mitigation Strategies**
- **Phased Approach**: Break down into manageable steps
- **Unit Testing**: Test each component individually
- **Integration Testing**: Test complete flow end-to-end
- **Documentation**: Document all changes and decisions

## 📋 **Next Steps**

### **Immediate Actions**
1. **Start Step 1**: Create CRI request structures
2. **Setup testing**: Prepare test environment
3. **Document progress**: Update issue progress

### **Dependencies**
- Phase 1 completion (✅ **COMPLETED**)
- Proxmox API access for PodSandbox validation
- Testing framework setup

---

**Phase 2 Planning Complete! Ready to start implementation.**

**Next Action**: Begin implementing CRI request structures (Step 1.1).
