const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");

pub const OciCliArgs = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    
    // OCI-specific arguments
    config_file: ?[]const u8,
    runtime_type: ?[]const u8,
    no_pivot: bool,
    no_new_keyring: bool,
    preserve_fds: ?[]const u32,
    bundle_path: ?[]const u8,
    container_id: ?[]const u8,
    
    // Runtime selection
    use_crun: bool,
    use_proxmox_lxc: bool,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) OciCliArgs {
        return OciCliArgs{
            .allocator = allocator,
            .logger = logger,
            .config_file = null,
            .runtime_type = null,
            .no_pivot = false,
            .no_new_keyring = false,
            .preserve_fds = null,
            .bundle_path = null,
            .container_id = null,
            .use_crun = false,
            .use_proxmox_lxc = false,
        };
    }
    
    pub fn parseArgs(self: *OciCliArgs, args: []const []const u8) !void {
        try self.logger.info("Parsing OCI CLI arguments: {d} arguments", .{args.len});
        
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            
            if (std.mem.startsWith(u8, arg, "--")) {
                try self.parseLongOption(arg, if (i + 1 < args.len) args[i + 1] else null, &i);
            } else if (std.mem.startsWith(u8, arg, "-")) {
                try self.parseShortOption(arg, if (i + 1 < args.len) args[i + 1] else null, &i);
            } else {
                // Positional argument - could be bundle path or container ID
                try self.parsePositionalArg(arg);
            }
        }
        
        try self.validateArgs();
        try self.determineRuntimeType();
        
        try self.logger.info("OCI CLI arguments parsing completed");
    }
    
    fn parseLongOption(self: *OciCliArgs, arg: []const u8, next_arg: ?[]const u8, index: *usize) !void {
        if (std.mem.eql(u8, arg, "--config")) {
            if (next_arg) |value| {
                self.config_file = try self.allocator.dupe(u8, value);
                index.* += 1; // Skip next argument
                try self.logger.debug("Config file: {s}", .{value});
            } else {
                return error.MissingConfigFileValue;
            }
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            if (next_arg) |value| {
                self.runtime_type = try self.allocator.dupe(u8, value);
                index.* += 1; // Skip next argument
                try self.logger.debug("Runtime type: {s}", .{value});
            } else {
                return error.MissingRuntimeTypeValue;
            }
        } else if (std.mem.eql(u8, arg, "--bundle")) {
            if (next_arg) |value| {
                self.bundle_path = try self.allocator.dupe(u8, value);
                index.* += 1; // Skip next argument
                try self.logger.debug("Bundle path: {s}", .{value});
            } else {
                return error.MissingBundlePathValue;
            }
        } else if (std.mem.eql(u8, arg, "--no-pivot")) {
            self.no_pivot = true;
            try self.logger.debug("No pivot root enabled");
        } else if (std.mem.eql(u8, arg, "--no-new-keyring")) {
            self.no_new_keyring = true;
            try self.logger.debug("No new keyring enabled");
        } else if (std.mem.eql(u8, arg, "--preserve-fds")) {
            if (next_arg) |value| {
                try self.parsePreserveFds(value);
                index.* += 1; // Skip next argument
            } else {
                return error.MissingPreserveFdsValue;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try self.printHelp();
        } else if (std.mem.eql(u8, arg, "--version")) {
            try self.printVersion();
        } else {
            try self.logger.warn("Unknown long option: {s}", .{arg});
        }
    }
    
    fn parseShortOption(self: *OciCliArgs, arg: []const u8, next_arg: ?[]const u8, index: *usize) !void {
        if (arg.len < 2) {
            try self.logger.warn("Invalid short option: {s}", .{arg});
            return;
        }
        
        const option = arg[1];
        switch (option) {
            'c' => {
                if (next_arg) |value| {
                    self.config_file = try self.allocator.dupe(u8, value);
                    index.* += 1; // Skip next argument
                    try self.logger.debug("Config file: {s}", .{value});
                } else {
                    return error.MissingConfigFileValue;
                }
            },
            'r' => {
                if (next_arg) |value| {
                    self.runtime_type = try self.allocator.dupe(u8, value);
                    index.* += 1; // Skip next argument
                    try self.logger.debug("Runtime type: {s}", .{value});
                } else {
                    return error.MissingRuntimeTypeValue;
                }
            },
            'b' => {
                if (next_arg) |value| {
                    self.bundle_path = try self.allocator.dupe(u8, value);
                    index.* += 1; // Skip next argument
                    try self.logger.debug("Bundle path: {s}", .{value});
                } else {
                    return error.MissingBundlePathValue;
                }
            },
            'h' => {
                try self.printHelp();
            },
            'v' => {
                try self.printVersion();
            },
            else => {
                try self.logger.warn("Unknown short option: {c}", .{option});
            },
        }
    }
    
    fn parsePositionalArg(self: *OciCliArgs, arg: []const u8) !void {
        // If no bundle path is set, this is the bundle path
        if (self.bundle_path == null) {
            self.bundle_path = try self.allocator.dupe(u8, arg);
            try self.logger.debug("Bundle path (positional): {s}", .{arg});
        } else if (self.container_id == null) {
            // If bundle path is set, this is the container ID
            self.container_id = try self.allocator.dupe(u8, arg);
            try self.logger.debug("Container ID (positional): {s}", .{arg});
        } else {
            try self.logger.warn("Unexpected positional argument: {s}", .{arg});
        }
    }
    
    fn parsePreserveFds(self: *OciCliArgs, value: []const u8) !void {
        // Parse comma-separated list of file descriptors
        var iter = std.mem.split(u8, value, ",");
        var fds = std.ArrayList(u32).init(self.allocator);
        defer fds.deinit();
        
        while (iter.next()) |fd_str| {
            const fd = try std.fmt.parseInt(u32, fd_str, 10);
            try fds.append(fd);
        }
        
        self.preserve_fds = fds.toOwnedSlice();
        try self.logger.debug("Preserve FDs: {any}", .{self.preserve_fds});
    }
    
    fn validateArgs(self: *OciCliArgs) !void {
        try self.logger.debug("Validating OCI CLI arguments");
        
        // Check required arguments
        if (self.bundle_path == null) {
            try self.logger.error("Bundle path is required");
            return error.MissingBundlePath;
        }
        
        if (self.container_id == null) {
            try self.logger.error("Container ID is required");
            return error.MissingContainerId;
        }
        
        // Validate bundle path
        if (self.bundle_path) |path| {
            if (!std.mem.startsWith(u8, path, "/")) {
                try self.logger.error("Bundle path must be absolute: {s}", .{path});
                return error.InvalidBundlePath;
            }
        }
        
        // Validate container ID
        if (self.container_id) |id| {
            if (id.len == 0) {
                try self.logger.error("Container ID cannot be empty");
                return error.InvalidContainerId;
            }
            
            // Check for valid characters
            for (id) |char| {
                if (!std.ascii.isAlphanumeric(char) and char != '-' and char != '_') {
                    try self.logger.error("Invalid character in container ID: {c}", .{char});
                    return error.InvalidContainerId;
                }
            }
        }
        
        // Validate runtime type if specified
        if (self.runtime_type) |runtime| {
            const valid_runtimes = [_][]const u8{ "crun", "runc", "proxmox-lxc", "lxc" };
            var valid = false;
            for (valid_runtimes) |valid_runtime| {
                if (std.mem.eql(u8, runtime, valid_runtime)) {
                    valid = true;
                    break;
                }
            }
            if (!valid) {
                try self.logger.error("Invalid runtime type: {s}", .{runtime});
                return error.InvalidRuntimeType;
            }
        }
        
        try self.logger.debug("OCI CLI arguments validation completed");
    }
    
    fn determineRuntimeType(self: *OciCliArgs) !void {
        try self.logger.debug("Determining runtime type");
        
        // If runtime type is explicitly specified, use it
        if (self.runtime_type) |runtime| {
            if (std.mem.eql(u8, runtime, "crun") or std.mem.eql(u8, runtime, "runc")) {
                self.use_crun = true;
                self.use_proxmox_lxc = false;
                try self.logger.info("Using crun/runc runtime");
            } else if (std.mem.eql(u8, runtime, "proxmox-lxc") or std.mem.eql(u8, runtime, "lxc")) {
                self.use_crun = false;
                self.use_proxmox_lxc = true;
                try self.logger.info("Using Proxmox LXC runtime");
            }
        } else {
            // Auto-detect based on container ID pattern
            if (self.container_id) |id| {
                if (std.mem.startsWith(u8, id, "lxc-") or 
                    std.mem.startsWith(u8, id, "db-") or 
                    std.mem.startsWith(u8, id, "vm-")) {
                    self.use_crun = false;
                    self.use_proxmox_lxc = true;
                    try self.logger.info("Auto-detected Proxmox LXC runtime based on container ID: {s}", .{id});
                } else {
                    self.use_crun = true;
                    self.use_proxmox_lxc = false;
                    try self.logger.info("Auto-detected crun/runc runtime based on container ID: {s}", .{id});
                }
            } else {
                // Default to crun
                self.use_crun = true;
                self.use_proxmox_lxc = false;
                try self.logger.info("Using default crun/runc runtime");
            }
        }
    }
    
    fn printHelp(self: *OciCliArgs) !void {
        const help_text = 
            \\OCI Runtime Interface - Container Runtime
            \\
            \\Usage: oci-runtime [OPTIONS] <BUNDLE> <CONTAINER_ID>
            \\
            \\Arguments:
            \\  BUNDLE         Path to the OCI bundle directory
            \\  CONTAINER_ID   Unique identifier for the container
            \\
            \\Options:
            \\  -c, --config <FILE>        Path to the OCI configuration file
            \\  -r, --runtime <TYPE>       Runtime type (crun, runc, proxmox-lxc, lxc)
            \\  -b, --bundle <PATH>        Path to the OCI bundle directory
            \\      --no-pivot             Disable pivot root
            \\      --no-new-keyring      Disable new keyring creation
            \\      --preserve-fds <FDS>   Comma-separated list of file descriptors to preserve
            \\  -h, --help                Show this help message
            \\  -v, --version             Show version information
            \\
            \\Examples:
            \\  oci-runtime /var/lib/containers/test-container test-123
            \\  oci-runtime --runtime crun --bundle /var/lib/containers/test test
            \\  oci-runtime --runtime proxmox-lxc --bundle /var/lib/containers/lxc-test lxc-123
            \\
        ;
        
        try self.logger.info(help_text, .{});
    }
    
    fn printVersion(self: *OciCliArgs) !void {
        const version_text = "OCI Runtime Interface v0.2.0 - Proxmox LXCRI";
        try self.logger.info(version_text, .{});
    }
    
    pub fn deinit(self: *OciCliArgs) void {
        if (self.config_file) |file| self.allocator.free(file);
        if (self.runtime_type) |runtime| self.allocator.free(runtime);
        if (self.bundle_path) |path| self.allocator.free(path);
        if (self.container_id) |id| self.allocator.free(id);
        if (self.preserve_fds) |fds| self.allocator.free(fds);
    }
};

// Error types
pub const OciCliError = error{
    MissingConfigFileValue,
    MissingRuntimeTypeValue,
    MissingBundlePathValue,
    MissingPreserveFdsValue,
    MissingBundlePath,
    MissingContainerId,
    InvalidBundlePath,
    InvalidContainerId,
    InvalidRuntimeType,
};
