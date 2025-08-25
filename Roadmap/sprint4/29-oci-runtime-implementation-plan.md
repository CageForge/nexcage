# OCI Runtime Implementation Plan - Phase 2 (Corrected)

## 🎯 **Phase 2: OCI Runtime Implementation - CORRECTED PLAN**

**Date**: August 25, 2025  
**Time**: 6 hours (planned)  
**Status**: 📋 **PLANNING** - Ready to Start  
**Dependencies**: Phase 1 (Current Implementation Analysis) - ✅ **COMPLETED**

## 🚀 **Overview**

### **Objective**
Implement proper OCI (Open Container Initiative) runtime functionality for the CreateContainer command, similar to runc or crun, including proper OCI bundle generation, configuration validation, and runtime selection.

### **Scope**
- Create OCI runtime structures (not CRI)
- Implement OCI bundle generation
- Add OCI configuration validation
- Update CLI argument parsing
- Integrate with existing CreateContainer logic

### **Success Criteria**
- [ ] OCI runtime structures created and working
- [ ] OCI bundle generation implemented correctly
- [ ] Configuration validation working
- [ ] CLI integration completed
- [ ] All acceptance criteria met

## 🔧 **Technical Architecture**

### **OCI Runtime Flow**
```
CLI Command → OCI Bundle Validation → Runtime Selection → Container Creation → OCI State Management
```

### **Data Structures**
```zig
// OCI Runtime Spec v1.0.2
pub const OciSpec = struct {
    ociVersion: []const u8,
    process: ?Process,
    root: ?Root,
    hostname: ?[]const u8,
    mounts: ?[]const Mount,
    hooks: ?Hooks,
    annotations: ?StringMap,
    linux: ?Linux,
    windows: ?Windows,
    vm: ?VM,
};

// Process configuration
pub const Process = struct {
    terminal: ?bool,
    consoleSize: ?Box,
    user: User,
    args: []const []const u8,
    env: ?[]const []const u8,
    cwd: []const u8,
    capabilities: ?LinuxCapabilities,
    rlimits: ?[]const POSIXRlimit,
    noNewPrivileges: bool,
    apparmorProfile: ?[]const u8,
    oomScoreAdj: ?i32,
    selinuxLabel: ?[]const u8,
};

// Root filesystem
pub const Root = struct {
    path: []const u8,
    readonly: bool,
};

// Mount configuration
pub const Mount = struct {
    destination: []const u8,
    type: []const u8,
    source: []const u8,
    options: ?[]const []const u8,
};
```

## 📋 **Step-by-Step Implementation Plan**

### **Step 1: Create OCI Runtime Structures (1.5 hours)**

#### **1.1 Create OCI Types Module**
**File**: `src/oci/runtime_types.zig`
**Purpose**: Define all OCI runtime data structures according to OCI spec v1.0.2

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

// OCI Runtime Spec v1.0.2
pub const OciSpec = struct {
    ociVersion: []const u8,
    process: ?Process,
    root: ?Root,
    hostname: ?[]const u8,
    mounts: ?[]const Mount,
    hooks: ?Hooks,
    annotations: ?StringMap,
    linux: ?Linux,
    windows: ?Windows,
    vm: ?VM,
    
    pub fn validate(self: *const Self) !void {
        // Validate OCI version
        if (!std.mem.eql(u8, self.ociVersion, "1.0.2")) {
            return error.UnsupportedOciVersion;
        }
        
        // Validate process configuration
        if (self.process) |process| {
            try process.validate();
        }
        
        // Validate root filesystem
        if (self.root) |root| {
            try root.validate();
        }
        
        // Validate mounts
        if (self.mounts) |mounts| {
            for (mounts) |mount| {
                try mount.validate();
            }
        }
        
        // Validate Linux-specific configuration
        if (self.linux) |linux| {
            try linux.validate();
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.ociVersion);
        if (self.hostname) |hostname| allocator.free(hostname);
        if (self.process) |process| process.deinit(allocator);
        if (self.root) |root| root.deinit(allocator);
        if (self.mounts) |mounts| {
            for (mounts) |mount| mount.deinit(allocator);
            allocator.free(mounts);
        }
        if (self.hooks) |hooks| hooks.deinit(allocator);
        if (self.annotations) |annotations| annotations.deinit(allocator);
        if (self.linux) |linux| linux.deinit(allocator);
        if (self.windows) |windows| windows.deinit(allocator);
        if (self.vm) |vm| vm.deinit(allocator);
    }
};

pub const Process = struct {
    terminal: ?bool,
    consoleSize: ?Box,
    user: User,
    args: []const []const u8,
    env: ?[]const []const u8,
    cwd: []const u8,
    capabilities: ?LinuxCapabilities,
    rlimits: ?[]const POSIXRlimit,
    noNewPrivileges: bool,
    apparmorProfile: ?[]const u8,
    oomScoreAdj: ?i32,
    selinuxLabel: ?[]const u8,
    
    pub fn validate(self: *const Self) !void {
        // Validate user configuration
        try self.user.validate();
        
        // Validate arguments
        if (self.args.len == 0) {
            return error.MissingProcessArgs;
        }
        
        // Validate working directory
        if (!std.mem.startsWith(u8, self.cwd, "/")) {
            return error.InvalidWorkingDirectory;
        }
        
        // Validate environment variables
        if (self.env) |env| {
            for (env) |env_var| {
                if (env_var.len == 0) return error.EmptyEnvironmentVariable;
            }
        }
        
        // Validate capabilities if present
        if (self.capabilities) |caps| {
            try caps.validate();
        }
        
        // Validate resource limits if present
        if (self.rlimits) |limits| {
            for (limits) |limit| {
                try limit.validate();
            }
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.user.deinit(allocator);
        
        for (self.args) |arg| allocator.free(arg);
        allocator.free(self.args);
        
        if (self.env) |env| {
            for (env) |env_var| allocator.free(env_var);
            allocator.free(env);
        }
        
        allocator.free(self.cwd);
        
        if (self.capabilities) |caps| caps.deinit(allocator);
        
        if (self.rlimits) |limits| {
            for (limits) |limit| limit.deinit(allocator);
            allocator.free(limits);
        }
        
        if (self.apparmorProfile) |profile| allocator.free(profile);
        if (self.selinuxLabel) |label| allocator.free(label);
    }
};

pub const Root = struct {
    path: []const u8,
    readonly: bool,
    
    pub fn validate(self: *const Self) !void {
        if (self.path.len == 0) {
            return error.MissingRootPath;
        }
        
        // Path must be absolute
        if (!std.mem.startsWith(u8, self.path, "/")) {
            return error.InvalidRootPath;
        }
        
        // Path must not contain ".." for security
        if (std.mem.indexOf(u8, self.path, "..") != null) {
            return error.InvalidRootPath;
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.path);
    }
};

pub const Mount = struct {
    destination: []const u8,
    type: []const u8,
    source: []const u8,
    options: ?[]const []const u8,
    
    pub fn validate(self: *const Self) !void {
        if (self.destination.len == 0) {
            return error.MissingMountDestination;
        }
        
        if (self.type.len == 0) {
            return error.MissingMountType;
        }
        
        if (self.source.len == 0) {
            return error.MissingMountSource;
        }
        
        // Destination must be absolute path
        if (!std.mem.startsWith(u8, self.destination, "/")) {
            return error.InvalidMountDestination;
        }
        
        // Source must be absolute path
        if (!std.mem.startsWith(u8, self.source, "/")) {
            return error.InvalidMountSource;
        }
        
        // Validate mount type
        const valid_types = [_][]const u8{ "bind", "proc", "sysfs", "tmpfs", "devpts", "devtmpfs", "overlay" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, self.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidMountType;
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.destination);
        allocator.free(self.type);
        allocator.free(self.source);
        
        if (self.options) |options| {
            for (options) |option| allocator.free(option);
            allocator.free(options);
        }
    }
};
```

#### **1.2 Create Supporting OCI Types**
**File**: `src/oci/runtime_types.zig` (continued)

```zig
pub const User = struct {
    uid: i32,
    gid: i32,
    additionalGids: ?[]const i32,
    
    pub fn validate(self: *const Self) !void {
        if (self.uid < 0) return error.InvalidUID;
        if (self.gid < 0) return error.InvalidGID;
        
        if (self.additionalGids) |gids| {
            for (gids) |gid| {
                if (gid < 0) return error.InvalidAdditionalGID;
            }
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.additionalGids) |gids| {
            allocator.free(gids);
        }
    }
};

pub const LinuxCapabilities = struct {
    bounding: ?[]const []const u8,
    effective: ?[]const []const u8,
    inheritable: ?[]const []const u8,
    permitted: ?[]const []const u8,
    ambient: ?[]const []const u8,
    
    pub fn validate(self: *const Self) !void {
        // Validate capability names
        if (self.bounding) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.effective) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.permitted) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
        if (self.ambient) |caps| {
            for (caps) |cap| {
                try self.validateCapabilityName(cap);
            }
        }
    }
    
    fn validateCapabilityName(self: *const Self, cap: []const u8) !void {
        // Basic capability name validation
        if (cap.len == 0) return error.EmptyCapabilityName;
        if (cap.len > 64) return error.CapabilityNameTooLong;
        
        // Check for valid characters
        for (cap) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '_') {
                return error.InvalidCapabilityName;
            }
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.bounding) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.effective) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.inheritable) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.permitted) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
        if (self.ambient) |caps| {
            for (caps) |cap| allocator.free(cap);
            allocator.free(caps);
        }
    }
};

pub const Linux = struct {
    namespaces: ?[]const LinuxNamespace,
    devices: ?[]const LinuxDevice,
    cgroupsPath: ?[]const u8,
    resources: ?LinuxResources,
    seccomp: ?LinuxSeccomp,
    rootfsPropagation: ?[]const u8,
    maskedPaths: ?[]const []const u8,
    readonlyPaths: ?[]const []const u8,
    mountLabel: ?[]const u8,
    intelRdt: ?LinuxIntelRdt,
    
    pub fn validate(self: *const Self) !void {
        // Validate namespaces if present
        if (self.namespaces) |namespaces| {
            for (namespaces) |ns| {
                try ns.validate();
            }
        }
        
        // Validate devices if present
        if (self.devices) |devices| {
            for (devices) |device| {
                try device.validate();
            }
        }
        
        // Validate cgroups path if present
        if (self.cgroupsPath) |path| {
            if (path.len > 0 and !std.mem.startsWith(u8, path, "/")) {
                return error.InvalidCgroupsPath;
            }
        }
        
        // Validate resources if present
        if (self.resources) |resources| {
            try resources.validate();
        }
        
        // Validate seccomp if present
        if (self.seccomp) |seccomp| {
            try seccomp.validate();
        }
    }
    
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.namespaces) |namespaces| {
            for (namespaces) |ns| ns.deinit(allocator);
            allocator.free(namespaces);
        }
        if (self.devices) |devices| {
            for (devices) |device| device.deinit(allocator);
            allocator.free(devices);
        }
        if (self.cgroupsPath) |path| allocator.free(path);
        if (self.resources) |resources| resources.deinit(allocator);
        if (self.seccomp) |seccomp| seccomp.deinit(allocator);
        if (self.rootfsPropagation) |prop| allocator.free(prop);
        if (self.maskedPaths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        if (self.readonlyPaths) |paths| {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        if (self.mountLabel) |label| allocator.free(label);
        if (self.intelRdt) |rdt| rdt.deinit(allocator);
    }
};
```

### **Step 2: Implement OCI Bundle Generation (1.5 hours)**

#### **2.1 Create OCI Bundle Module**
**File**: `src/oci/bundle.zig`
**Purpose**: Handle OCI bundle creation and validation

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const logger_mod = @import("logger");
const runtime_types = @import("runtime_types");

pub const OciBundle = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    bundle_path: []const u8,
    container_id: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, bundle_path: []const u8, container_id: []const u8) OciBundle {
        return OciBundle{
            .allocator = allocator,
            .logger = logger,
            .bundle_path = bundle_path,
            .container_id = container_id,
        };
    }
    
    pub fn createBundle(self: *OciBundle) !void {
        try self.logger.info("Creating OCI bundle for container: {s}", .{self.container_id});
        
        // Create bundle directory structure
        try self.createBundleDirectory();
        
        // Create rootfs directory
        try self.createRootfsDirectory();
        
        // Generate config.json
        try self.generateConfigJson();
        
        try self.logger.info("OCI bundle created successfully: {s}", .{self.container_id});
    }
    
    fn createBundleDirectory(self: *OciBundle) !void {
        const bundle_dir = try std.fs.cwd().makeOpenPath(self.bundle_path, .{});
        defer bundle_dir.close();
        
        try self.logger.debug("Bundle directory created: {s}", .{self.bundle_path});
    }
    
    fn createRootfsDirectory(self: *OciBundle) !void {
        const rootfs_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.bundle_path, "rootfs" });
        defer self.allocator.free(rootfs_path);
        
        try std.fs.cwd().makePath(rootfs_path);
        try self.logger.debug("Rootfs directory created: {s}", .{rootfs_path});
    }
    
    fn generateConfigJson(self: *OciBundle) !void {
        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.bundle_path, "config.json" });
        defer self.allocator.free(config_path);
        
        // Create basic OCI spec
        var spec = runtime_types.OciSpec{
            .ociVersion = try self.allocator.dupe(u8, "1.0.2"),
            .process = try self.createDefaultProcess(),
            .root = try self.createDefaultRoot(),
            .hostname = try self.allocator.dupe(u8, self.container_id),
            .mounts = try self.createDefaultMounts(),
            .hooks = null,
            .annotations = null,
            .linux = try self.createDefaultLinux(),
            .windows = null,
            .vm = null,
        };
        defer spec.deinit(self.allocator);
        
        // Serialize to JSON
        const config_json = try std.json.stringifyAlloc(self.allocator, spec, .{});
        defer self.allocator.free(config_json);
        
        // Write to file
        try std.fs.cwd().writeFile(.{
            .data = config_json,
            .sub_path = config_path,
        });
        
        try self.logger.debug("Config.json generated: {s}", .{config_path});
    }
    
    fn createDefaultProcess(self: *OciBundle) !runtime_types.Process {
        return runtime_types.Process{
            .terminal = false,
            .consoleSize = null,
            .user = runtime_types.User{
                .uid = 0,
                .gid = 0,
                .additionalGids = null,
            },
            .args = try self.createDefaultArgs(),
            .env = try self.createDefaultEnv(),
            .cwd = try self.allocator.dupe(u8, "/"),
            .capabilities = null,
            .rlimits = null,
            .noNewPrivileges = true,
            .apparmorProfile = null,
            .oomScoreAdj = null,
            .selinuxLabel = null,
        };
    }
    
    fn createDefaultArgs(self: *OciBundle) ![]const []const u8 {
        const args = try self.allocator.alloc([]const u8, 1);
        args[0] = try self.allocator.dupe(u8, "/bin/sh");
        return args;
    }
    
    fn createDefaultEnv(self: *OciBundle) ![]const []const u8 {
        const env = try self.allocator.alloc([]const u8, 1);
        env[0] = try self.allocator.dupe(u8, "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
        return env;
    }
    
    fn createDefaultRoot(self: *OciBundle) !runtime_types.Root {
        return runtime_types.Root{
            .path = try self.allocator.dupe(u8, "rootfs"),
            .readonly = false,
        };
    }
    
    fn createDefaultMounts(self: *OciBundle) ![]const runtime_types.Mount {
        const mounts = try self.allocator.alloc(runtime_types.Mount, 3);
        
        // /proc
        mounts[0] = runtime_types.Mount{
            .destination = try self.allocator.dupe(u8, "/proc"),
            .type = try self.allocator.dupe(u8, "proc"),
            .source = try self.allocator.dupe(u8, "proc"),
            .options = null,
        };
        
        // /sys
        mounts[1] = runtime_types.Mount{
            .destination = try self.allocator.dupe(u8, "/sys"),
            .type = try self.allocator.dupe(u8, "sysfs"),
            .source = try self.allocator.dupe(u8, "sysfs"),
            .options = null,
        };
        
        // /dev
        mounts[2] = runtime_types.Mount{
            .destination = try self.allocator.dupe(u8, "/dev"),
            .type = try self.allocator.dupe(u8, "devtmpfs"),
            .source = try self.allocator.dupe(u8, "devtmpfs"),
            .options = null,
        };
        
        return mounts;
    }
    
    fn createDefaultLinux(self: *OciBundle) !runtime_types.Linux {
        return runtime_types.Linux{
            .namespaces = try self.createDefaultNamespaces(),
            .devices = try self.createDefaultDevices(),
            .cgroupsPath = null,
            .resources = null,
            .seccomp = null,
            .rootfsPropagation = null,
            .maskedPaths = null,
            .readonlyPaths = null,
            .mountLabel = null,
            .intelRdt = null,
        };
    }
    
    fn createDefaultNamespaces(self: *OciBundle) ![]const runtime_types.LinuxNamespace {
        const namespaces = try self.allocator.alloc(runtime_types.LinuxNamespace, 6);
        
        // PID namespace
        namespaces[0] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "pid"),
            .path = null,
        };
        
        // Network namespace
        namespaces[1] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "network"),
            .path = null,
        };
        
        // IPC namespace
        namespaces[2] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "ipc"),
            .path = null,
        };
        
        // UTS namespace
        namespaces[3] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "uts"),
            .path = null,
        };
        
        // Mount namespace
        namespaces[4] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "mount"),
            .path = null,
        };
        
        // User namespace
        namespaces[5] = runtime_types.LinuxNamespace{
            .type = try self.allocator.dupe(u8, "user"),
            .path = null,
        };
        
        return namespaces;
    }
    
    fn createDefaultDevices(self: *OciBundle) ![]const runtime_types.LinuxDevice {
        const devices = try self.allocator.alloc(runtime_types.LinuxDevice, 3);
        
        // /dev/null
        devices[0] = runtime_types.LinuxDevice{
            .path = try self.allocator.dupe(u8, "/dev/null"),
            .type = try self.allocator.dupe(u8, "c"),
            .major = 1,
            .minor = 3,
            .fileMode = 0o666,
            .uid = 0,
            .gid = 0,
        };
        
        // /dev/zero
        devices[1] = runtime_types.LinuxDevice{
            .path = try self.allocator.dupe(u8, "/dev/zero"),
            .type = try self.allocator.dupe(u8, "c"),
            .major = 1,
            .minor = 5,
            .fileMode = 0o666,
            .uid = 0,
            .gid = 0,
        };
        
        // /dev/random
        devices[2] = runtime_types.LinuxDevice{
            .path = try self.allocator.dupe(u8, "/dev/random"),
            .type = try self.allocator.dupe(u8, "c"),
            .major = 1,
            .minor = 8,
            .fileMode = 0o666,
            .uid = 0,
            .gid = 0,
        };
        
        return devices;
    }
};
```

### **Step 3: Add OCI Configuration Validation (1.5 hours)**

#### **3.1 Create OCI Configuration Validator**
**File**: `src/oci/validator.zig`
**Purpose**: Validate OCI configuration according to spec

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const runtime_types = @import("runtime_types");

pub const OciConfigurationValidator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) OciConfigurationValidator {
        return OciConfigurationValidator{
            .allocator = allocator,
            .logger = logger,
        };
    }
    
    pub fn validateOciSpec(self: *OciConfigurationValidator, spec: runtime_types.OciSpec) !void {
        try self.logger.info("Validating OCI spec", .{});
        
        // Validate OCI version
        try self.validateOciVersion(spec.ociVersion);
        
        // Validate process configuration
        if (spec.process) |process| {
            try self.validateProcess(process);
        }
        
        // Validate root filesystem
        if (spec.root) |root| {
            try self.validateRoot(root);
        }
        
        // Validate hostname
        if (spec.hostname) |hostname| {
            try self.validateHostname(hostname);
        }
        
        // Validate mounts
        if (spec.mounts) |mounts| {
            try self.validateMounts(mounts);
        }
        
        // Validate Linux-specific configuration
        if (spec.linux) |linux| {
            try self.validateLinux(linux);
        }
        
        try self.logger.info("OCI spec validation successful", .{});
    }
    
    fn validateOciVersion(self: *OciConfigurationValidator, version: []const u8) !void {
        if (!std.mem.eql(u8, version, "1.0.2")) {
            try self.logger.err("Unsupported OCI version: {s}", .{version});
            return error.UnsupportedOciVersion;
        }
    }
    
    fn validateProcess(self: *OciConfigurationValidator, process: runtime_types.Process) !void {
        try process.validate();
    }
    
    fn validateRoot(self: *OciConfigurationValidator, root: runtime_types.Root) !void {
        try root.validate();
    }
    
    fn validateHostname(self: *OciConfigurationValidator, hostname: []const u8) !void {
        if (hostname.len > 63) {
            return error.HostnameTooLong;
        }
        
        // Check for valid hostname characters
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
    
    fn validateMounts(self: *OciConfigurationValidator, mounts: []const runtime_types.Mount) !void {
        for (mounts) |mount| {
            try mount.validate();
        }
    }
    
    fn validateLinux(self: *OciConfigurationValidator, linux: runtime_types.Linux) !void {
        try linux.validate();
    }
};
```

### **Step 4: Update CLI Argument Parsing (1 hour)**

#### **4.1 Update CLI Arguments for OCI**
**File**: `src/common/cli_args.zig`
**Purpose**: Add OCI-specific command line arguments

```zig
// Add OCI-specific options to RuntimeOptions
pub const RuntimeOptions = struct {
    root: ?[]const u8 = null,
    log: ?[]const u8 = null,
    log_format: ?[]const u8 = null,
    systemd_cgroup: bool = false,
    bundle: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    debug: bool = false,
    
    // OCI-specific options
    config_file: ?[]const u8 = null,
    runtime_type: ?[]const u8 = null,
    no_pivot: bool = false,
    no_new_keyring: bool = false,
    preserve_fds: u32 = 0,
    
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
        if (self.config_file) |config_file| self.allocator.free(config_file);
        if (self.runtime_type) |runtime_type| self.allocator.free(runtime_type);
    }
};

// Update argument parsing to handle OCI options
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
        } else if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.config_file = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--runtime-type")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.runtime_type = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--no-pivot")) {
            options.no_pivot = true;
        } else if (std.mem.eql(u8, arg, "--no-new-keyring")) {
            options.no_new_keyring = true;
        } else if (std.mem.eql(u8, arg, "--preserve-fds")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.preserve_fds = try std.fmt.parseInt(u32, argv[i], 10);
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
**Purpose**: Integrate OCI validation with existing CreateContainer logic

```zig
// Add OCI integration to the main create function
pub fn create(opts: CreateOpts, proxmox_client: *proxmox.ProxmoxClient) !void {
    const logger = logger_mod.Logger.init(opts.allocator, .info, null);
    defer logger.deinit();

    try logger.info("Creating container {s} with bundle {s}", .{ opts.id, opts.bundle_path });

    // OCI Integration: Validate OCI spec if provided
    if (opts.oci_spec) |spec| {
        try logger.info("Validating OCI spec", .{});
        
        var oci_validator = OciConfigurationValidator.init(opts.allocator, &logger);
        try oci_validator.validateOciSpec(spec);
        
        try logger.info("OCI spec validation successful", .{});
    }

    // OCI Integration: Create OCI bundle if not exists
    if (opts.create_bundle) {
        try logger.info("Creating OCI bundle", .{});
        
        var oci_bundle = OciBundle.init(opts.allocator, &logger, opts.bundle_path, opts.id);
        try oci_bundle.createBundle();
        
        try logger.info("OCI bundle created successfully", .{});
    }

    // Continue with existing logic...
    // ... (rest of the existing create function)
}
```

#### **5.2 Update CreateOpts Structure**
**File**: `src/oci/create.zig**

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
    
    // OCI-specific fields
    oci_spec: ?runtime_types.OciSpec = null,
    create_bundle: bool = false,
    runtime_type: ?oci_types.RuntimeType = null,

    pub fn deinit(self: *CreateOpts, allocator: Allocator) void {
        allocator.free(self.config_path);
        allocator.free(self.id);
        allocator.free(self.bundle_path);
        if (self.pid_file) |pid_file| allocator.free(pid_file);
        if (self.console_socket) |console_socket| allocator.free(console_socket);
        if (self.oci_spec) |spec| spec.deinit(allocator);
    }
};
```

## 📊 **Implementation Timeline**

### **Step 1: Create OCI Runtime Structures (1.5 hours)**
- **1.1**: Create OCI Types Module (1 hour)
- **1.2**: Create Supporting OCI Types (0.5 hours)

### **Step 2: Implement OCI Bundle Generation (1.5 hours)**
- **2.1**: Create OCI Bundle Module (1 hour)
- **2.2**: Add Bundle Generation Logic (0.5 hours)

### **Step 3: Add OCI Configuration Validation (1.5 hours)**
- **3.1**: Create OCI Configuration Validator (1 hour)
- **3.2**: Add Validation Logic (0.5 hours)

### **Step 4: Update CLI Argument Parsing (1 hour)**
- **4.1**: Update CLI Arguments for OCI (1 hour)

### **Step 5: Integrate with CreateContainer Logic (0.5 hours)**
- **5.1**: Update CreateContainer Function (0.3 hours)
- **5.2**: Update CreateOpts Structure (0.2 hours)

## 🏆 **Success Metrics**

### **Phase 2 Completion Criteria**
- [ ] OCI runtime structures created and tested
- [ ] OCI bundle generation implemented and working
- [ ] Configuration validation implemented and working
- [ ] CLI integration completed
- [ ] All acceptance criteria met

### **Testing Requirements**
- [ ] Unit tests for OCI types
- [ ] Unit tests for OCI bundle generation
- [ ] Unit tests for configuration validation
- [ ] Integration tests for CLI parsing
- [ ] End-to-end tests for CreateContainer with OCI

## 🔄 **Risk Assessment**

### **High Risk Items**
- **Complexity**: OCI integration involves multiple components
- **Dependencies**: Requires proper OCI spec v1.0.2 compliance
- **Testing**: Comprehensive testing required for validation logic

### **Mitigation Strategies**
- **Phased Approach**: Break down into manageable steps
- **Unit Testing**: Test each component individually
- **Integration Testing**: Test complete flow end-to-end
- **Documentation**: Document all changes and decisions

## 📋 **Next Steps**

### **Immediate Actions**
1. **Start Step 1**: Create OCI runtime structures
2. **Setup testing**: Prepare test environment
3. **Document progress**: Update issue progress

### **Dependencies**
- Phase 1 completion (✅ **COMPLETED**)
- OCI spec v1.0.2 compliance
- Testing framework setup

---

**Phase 2 Planning Complete! Ready to start OCI runtime implementation.**

**Next Action**: Begin implementing OCI runtime structures (Step 1.1).
