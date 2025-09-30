const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const runtime_types = @import("runtime_types");

pub const OciValidator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) OciValidator {
        return OciValidator{
            .allocator = allocator,
            .logger = logger,
        };
    }
    
    pub fn validateOciSpec(self: *OciValidator, spec: *const runtime_types.OciSpec) !void {
        try self.logger.info("Validating OCI specification");
        
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
        
        try self.logger.info("OCI specification validation completed successfully");
    }
    
    fn validateOciVersion(self: *OciValidator, version: []const u8) !void {
        if (!std.mem.eql(u8, version, "1.0.2")) {
            try self.logger.error("Unsupported OCI version: {s}", .{version});
            return error.UnsupportedOciVersion;
        }
        try self.logger.debug("OCI version validated: {s}", .{version});
    }
    
    fn validateProcess(self: *OciValidator, process: *const runtime_types.Process) !void {
        try self.logger.debug("Validating process configuration");
        
        // Validate user configuration
        try self.validateUser(process.user);
        
        // Validate arguments
        if (process.args.len == 0) {
            try self.logger.error("Process must have at least one argument");
            return error.MissingProcessArgs;
        }
        
        // Validate working directory
        if (!std.mem.startsWith(u8, process.cwd, "/")) {
            try self.logger.error("Working directory must be absolute path: {s}", .{process.cwd});
            return error.InvalidWorkingDirectory;
        }
        
        // Validate environment variables
        if (process.env) |env| {
            try self.validateEnvironmentVariables(env);
        }
        
        // Validate capabilities if present
        if (process.capabilities) |caps| {
            try self.validateCapabilities(caps);
        }
        
        // Validate resource limits if present
        if (process.rlimits) |limits| {
            try self.validateResourceLimits(limits);
        }
        
        try self.logger.debug("Process configuration validation completed");
    }
    
    fn validateUser(self: *OciValidator, user: runtime_types.User) !void {
        if (user.uid < 0) {
            try self.logger.error("Invalid UID: {d}", .{user.uid});
            return error.InvalidUID;
        }
        
        if (user.gid < 0) {
            try self.logger.error("Invalid GID: {d}", .{user.gid});
            return error.InvalidGID;
        }
        
        if (user.additionalGids) |gids| {
            for (gids, 0..) |gid, i| {
                if (gid < 0) {
                    try self.logger.error("Invalid additional GID at index {d}: {d}", .{i, gid});
                    return error.InvalidAdditionalGID;
                }
            }
        }
        
        try self.logger.debug("User configuration validated: UID={d}, GID={d}", .{user.uid, user.gid});
    }
    
    fn validateEnvironmentVariables(self: *OciValidator, env: []const []const u8) !void {
        for (env, 0..) |env_var, i| {
            if (env_var.len == 0) {
                try self.logger.error("Empty environment variable at index {d}", .{i});
                return error.EmptyEnvironmentVariable;
            }
            
            // Check for basic format (KEY=VALUE)
            if (std.mem.indexOf(u8, env_var, "=") == null) {
                try self.logger.warn("Environment variable at index {d} does not contain '=': {s}", .{i, env_var});
            }
        }
        
        try self.logger.debug("Environment variables validation completed: {d} variables", .{env.len});
    }
    
    fn validateCapabilities(self: *OciValidator, caps: *const runtime_types.LinuxCapabilities) !void {
        try self.logger.debug("Validating Linux capabilities");
        
        // Validate each capability set
        if (caps.bounding) |bounding| {
            try self.validateCapabilitySet(bounding, "bounding");
        }
        if (caps.effective) |effective| {
            try self.validateCapabilitySet(effective, "effective");
        }
        if (caps.inheritable) |inheritable| {
            try self.validateCapabilitySet(inheritable, "inheritable");
        }
        if (caps.permitted) |permitted| {
            try self.validateCapabilitySet(permitted, "permitted");
        }
        if (caps.ambient) |ambient| {
            try self.validateCapabilitySet(ambient, "ambient");
        }
        
        try self.logger.debug("Linux capabilities validation completed");
    }
    
    fn validateCapabilitySet(self: *OciValidator, caps: []const []const u8, set_name: []const u8) !void {
        for (caps, 0..) |cap, i| {
            if (cap.len == 0) {
                try self.logger.error("Empty capability name in {s} set at index {d}", .{set_name, i});
                return error.EmptyCapabilityName;
            }
            
            if (cap.len > 64) {
                try self.logger.error("Capability name too long in {s} set at index {d}: {s}", .{set_name, i, cap});
                return error.CapabilityNameTooLong;
            }
            
            // Check for valid characters
            for (cap) |char| {
                if (!std.ascii.isAlphanumeric(char) and char != '_') {
                    try self.logger.error("Invalid character in capability name in {s} set at index {d}: {s}", .{set_name, i, cap});
                    return error.InvalidCapabilityName;
                }
            }
        }
        
        try self.logger.debug("Capability set '{s}' validation completed: {d} capabilities", .{set_name, caps.len});
    }
    
    fn validateResourceLimits(self: *OciValidator, limits: []const runtime_types.POSIXRlimit) !void {
        try self.logger.debug("Validating resource limits");
        
        for (limits, 0..) |limit, i| {
            if (limit.hard < limit.soft) {
                try self.logger.error("Invalid resource limit at index {d}: hard limit ({d}) < soft limit ({d})", .{i, limit.hard, limit.soft});
                return error.InvalidRlimitValues;
            }
        }
        
        try self.logger.debug("Resource limits validation completed: {d} limits", .{limits.len});
    }
    
    fn validateRoot(self: *OciValidator, root: *const runtime_types.Root) !void {
        try self.logger.debug("Validating root filesystem configuration");
        
        if (root.path.len == 0) {
            try self.logger.error("Root path is empty");
            return error.MissingRootPath;
        }
        
        // Path must be absolute
        if (!std.mem.startsWith(u8, root.path, "/")) {
            try self.logger.error("Root path must be absolute: {s}", .{root.path});
            return error.InvalidRootPath;
        }
        
        // Path must not contain ".." for security
        if (std.mem.indexOf(u8, root.path, "..") != null) {
            try self.logger.error("Root path contains forbidden '..': {s}", .{root.path});
            return error.InvalidRootPath;
        }
        
        try self.logger.debug("Root filesystem validation completed: {s}", .{root.path});
    }
    
    fn validateHostname(self: *OciValidator, hostname: []const u8) !void {
        if (hostname.len > 63) {
            try self.logger.error("Hostname too long: {d} characters", .{hostname.len});
            return error.HostnameTooLong;
        }
        
        // Check for valid characters (RFC 1123)
        for (hostname) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '-') {
                try self.logger.error("Invalid character in hostname: {c}", .{char});
                return error.InvalidHostnameCharacter;
            }
        }
        
        // Hostname cannot start or end with hyphen
        if (hostname.len > 0 and (hostname[0] == '-' or hostname[hostname.len - 1] == '-')) {
            try self.logger.error("Hostname cannot start or end with hyphen: {s}", .{hostname});
            return error.InvalidHostnameFormat;
        }
        
        try self.logger.debug("Hostname validation completed: {s}", .{hostname});
    }
    
    fn validateMounts(self: *OciValidator, mounts: []const runtime_types.Mount) !void {
        try self.logger.debug("Validating mount configurations");
        
        for (mounts, 0..) |mount, i| {
            try self.validateMount(mount, i);
        }
        
        try self.logger.debug("Mount configurations validation completed: {d} mounts", .{mounts.len});
    }
    
    fn validateMount(self: *OciValidator, mount: runtime_types.Mount, index: usize) !void {
        if (mount.destination.len == 0) {
            try self.logger.error("Mount destination is empty at index {d}", .{index});
            return error.MissingMountDestination;
        }
        
        if (mount.type.len == 0) {
            try self.logger.error("Mount type is empty at index {d}", .{index});
            return error.MissingMountType;
        }
        
        if (mount.source.len == 0) {
            try self.logger.error("Mount source is empty at index {d}", .{index});
            return error.MissingMountSource;
        }
        
        // Destination must be absolute path
        if (!std.mem.startsWith(u8, mount.destination, "/")) {
            try self.logger.error("Mount destination must be absolute path at index {d}: {s}", .{index, mount.destination});
            return error.InvalidMountDestination;
        }
        
        // Source must be absolute path
        if (!std.mem.startsWith(u8, mount.source, "/")) {
            try self.logger.error("Mount source must be absolute path at index {d}: {s}", .{index, mount.source});
            return error.InvalidMountSource;
        }
        
        // Validate mount type
        const valid_types = [_][]const u8{ "bind", "proc", "sysfs", "tmpfs", "devpts", "devtmpfs", "overlay" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, mount.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            try self.logger.error("Invalid mount type at index {d}: {s}", .{index, mount.type});
            return error.InvalidMountType;
        }
        
        try self.logger.debug("Mount validation completed at index {d}: {s} -> {s} ({s})", .{index, mount.source, mount.destination, mount.type});
    }
    
    fn validateLinux(self: *OciValidator, linux: *const runtime_types.Linux) !void {
        try self.logger.debug("Validating Linux-specific configuration");
        
        // Validate namespaces if present
        if (linux.namespaces) |namespaces| {
            try self.validateNamespaces(namespaces);
        }
        
        // Validate devices if present
        if (linux.devices) |devices| {
            try self.validateDevices(devices);
        }
        
        // Validate cgroups path if present
        if (linux.cgroupsPath) |path| {
            try self.validateCgroupsPath(path);
        }
        
        // Validate resources if present
        if (linux.resources) |resources| {
            try self.validateLinuxResources(resources);
        }
        
        // Validate seccomp if present
        if (linux.seccomp) |seccomp| {
            try self.validateSeccomp(seccomp);
        }
        
        try self.logger.debug("Linux configuration validation completed");
    }
    
    fn validateNamespaces(self: *OciValidator, namespaces: []const runtime_types.LinuxNamespace) !void {
        try self.logger.debug("Validating Linux namespaces");
        
        for (namespaces, 0..) |ns, i| {
            try self.validateNamespace(ns, i);
        }
        
        try self.logger.debug("Linux namespaces validation completed: {d} namespaces", .{namespaces.len});
    }
    
    fn validateNamespace(self: *OciValidator, ns: runtime_types.LinuxNamespace, index: usize) !void {
        const valid_types = [_][]const u8{ "pid", "network", "ipc", "uts", "mount", "user", "cgroup" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, ns.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            try self.logger.error("Invalid namespace type at index {d}: {s}", .{index, ns.type});
            return error.InvalidNamespaceType;
        }
        
        try self.logger.debug("Namespace validation completed at index {d}: {s}", .{index, ns.type});
    }
    
    fn validateDevices(self: *OciValidator, devices: []const runtime_types.LinuxDevice) !void {
        try self.logger.debug("Validating Linux devices");
        
        for (devices, 0..) |device, i| {
            try self.validateDevice(device, i);
        }
        
        try self.logger.debug("Linux devices validation completed: {d} devices", .{devices.len});
    }
    
    fn validateDevice(self: *OciValidator, device: runtime_types.LinuxDevice, index: usize) !void {
        if (device.path.len == 0) {
            try self.logger.error("Device path is empty at index {d}", .{index});
            return error.MissingDevicePath;
        }
        
        if (device.type.len == 0) {
            try self.logger.error("Device type is empty at index {d}", .{index});
            return error.MissingDeviceType;
        }
        
        // Validate device type
        const valid_types = [_][]const u8{ "c", "b", "u", "p" };
        var valid = false;
        for (valid_types) |valid_type| {
            if (std.mem.eql(u8, device.type, valid_type)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            try self.logger.error("Invalid device type at index {d}: {s}", .{index, device.type});
            return error.InvalidDeviceType;
        }
        
        // Validate major/minor numbers
        if (device.major < 0) {
            try self.logger.error("Invalid major number at index {d}: {d}", .{index, device.major});
            return error.InvalidMajorNumber;
        }
        if (device.minor < 0) {
            try self.logger.error("Invalid minor number at index {d}: {d}", .{index, device.minor});
            return error.InvalidMinorNumber;
        }
        
        try self.logger.debug("Device validation completed at index {d}: {s} ({s}:{d},{d})", .{index, device.path, device.type, device.major, device.minor});
    }
    
    fn validateCgroupsPath(self: *OciValidator, path: []const u8) !void {
        if (path.len > 0 and !std.mem.startsWith(u8, path, "/")) {
            try self.logger.error("Invalid cgroups path: {s}", .{path});
            return error.InvalidCgroupsPath;
        }
        
        try self.logger.debug("Cgroups path validation completed: {s}", .{path});
    }
    
    fn validateLinuxResources(self: *OciValidator, resources: *const runtime_types.LinuxResources) !void {
        try self.logger.debug("Validating Linux resources");
        
        if (resources.devices) |devices| {
            try self.validateDeviceCgroups(devices);
        }
        if (resources.memory) |memory| {
            try self.validateMemory(resources.memory);
        }
        if (resources.cpu) |cpu| {
            try self.validateCPU(cpu);
        }
        if (resources.pids) |pids| {
            try self.validatePids(pids);
        }
        if (resources.network) |network| {
            try self.validateNetwork(network);
        }
        if (resources.hugepageLimits) |limits| {
            try self.validateHugepageLimits(limits);
        }
        if (resources.blockIO) |block_io| {
            try self.validateBlockIO(block_io);
        }
        
        try self.logger.debug("Linux resources validation completed");
    }
    
    fn validateDeviceCgroups(self: *OciValidator, devices: []const runtime_types.LinuxDeviceCgroup) !void {
        for (devices, 0..) |device, i| {
            try self.validateDeviceCgroup(device, i);
        }
    }
    
    fn validateDeviceCgroup(self: *OciValidator, device: runtime_types.LinuxDeviceCgroup, index: usize) !void {
        if (device.type.len == 0) {
            try self.logger.error("Device cgroup type is empty at index {d}", .{index});
            return error.MissingDeviceType;
        }
        if (device.access.len == 0) {
            try self.logger.error("Device cgroup access is empty at index {d}", .{index});
            return error.MissingDeviceAccess;
        }
    }
    
    fn validateMemory(self: *OciValidator, memory: *const runtime_types.LinuxMemory) !void {
        if (memory.limit) |limit| {
            if (limit < 0) {
                try self.logger.error("Invalid memory limit: {d}", .{limit});
                return error.InvalidMemoryLimit;
            }
        }
        if (memory.reservation) |reservation| {
            if (reservation < 0) {
                try self.logger.error("Invalid memory reservation: {d}", .{reservation});
                return error.InvalidMemoryReservation;
            }
        }
    }
    
    fn validateCPU(self: *OciValidator, cpu: *const runtime_types.LinuxCPU) !void {
        if (cpu.quota) |quota| {
            if (quota < 0) {
                try self.logger.error("Invalid CPU quota: {d}", .{quota});
                return error.InvalidCPUQuota;
            }
        }
        if (cpu.period) |period| {
            if (period <= 0) {
                try self.logger.error("Invalid CPU period: {d}", .{period});
                return error.InvalidCPUPeriod;
            }
        }
    }
    
    fn validatePids(self: *OciValidator, pids: *const runtime_types.LinuxPids) !void {
        if (pids.limit < 0) {
            try self.logger.error("Invalid PIDs limit: {d}", .{pids.limit});
            return error.InvalidPidsLimit;
        }
    }
    
    fn validateNetwork(self: *OciValidator, network: *const runtime_types.LinuxNetwork) !void {
        if (network.priorities) |priorities| {
            for (priorities, 0..) |priority, i| {
                try self.validateInterfacePriority(priority, i);
            }
        }
    }
    
    fn validateInterfacePriority(self: *OciValidator, priority: runtime_types.LinuxInterfacePriority, index: usize) !void {
        if (priority.name.len == 0) {
            try self.logger.error("Interface name is empty at index {d}", .{index});
            return error.MissingInterfaceName;
        }
    }
    
    fn validateHugepageLimits(self: *OciValidator, limits: []const runtime_types.LinuxHugepageLimit) !void {
        for (limits, 0..) |limit, i| {
            try self.validateHugepageLimit(limit, i);
        }
    }
    
    fn validateHugepageLimit(self: *OciValidator, limit: runtime_types.LinuxHugepageLimit, index: usize) !void {
        if (limit.pageSize.len == 0) {
            try self.logger.error("Page size is empty at index {d}", .{index});
            return error.MissingPageSize;
        }
        if (limit.limit == 0) {
            try self.logger.error("Hugepage limit is zero at index {d}", .{index});
            return error.InvalidHugepageLimit;
        }
    }
    
    fn validateBlockIO(self: *OciValidator, block_io: *const runtime_types.LinuxBlockIO) !void {
        if (block_io.weight) |weight| {
            if (weight > 1000) {
                try self.logger.error("Invalid block IO weight: {d}", .{weight});
                return error.InvalidBlockIOWeight;
            }
        }
        if (block_io.leafWeight) |leaf_weight| {
            if (leaf_weight > 1000) {
                try self.logger.error("Invalid block IO leaf weight: {d}", .{leaf_weight});
                return error.InvalidBlockIOLeafWeight;
            }
        }
    }
    
    fn validateSeccomp(self: *OciValidator, seccomp: *const runtime_types.LinuxSeccomp) !void {
        try self.logger.debug("Validating seccomp configuration");
        
        const valid_actions = [_][]const u8{ "SCMP_ACT_KILL", "SCMP_ACT_TRAP", "SCMP_ACT_ERRNO", "SCMP_ACT_TRACE", "SCMP_ACT_ALLOW" };
        var valid = false;
        for (valid_actions) |action| {
            if (std.mem.eql(u8, seccomp.defaultAction, action)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            try self.logger.error("Invalid seccomp action: {s}", .{seccomp.defaultAction});
            return error.InvalidSeccompAction;
        }
        
        try self.logger.debug("Seccomp validation completed: {s}", .{seccomp.defaultAction});
    }
};
