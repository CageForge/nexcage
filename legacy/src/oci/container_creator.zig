const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const runtime_types = @import("runtime_types");
const bundle_mod = @import("bundle");
const validator_mod = @import("validator");
const cli_mod = @import("cli");

pub const OciContainerCreator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,
    cli_args: *cli_mod.OciCliArgs,
    bundle: *bundle_mod.OciBundle,
    validator: *validator_mod.OciValidator,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, cli_args: *cli_mod.OciCliArgs) !OciContainerCreator {
        const bundle = try bundle_mod.OciBundle.init(allocator, logger, cli_args.bundle_path.?, cli_args.container_id.?);
        const validator = try validator_mod.OciValidator.init(allocator, logger);
        
        return OciContainerCreator{
            .allocator = allocator,
            .logger = logger,
            .cli_args = cli_args,
            .bundle = &bundle,
            .validator = &validator,
        };
    }
    
    pub fn createContainer(self: *OciContainerCreator) !void {
        try self.logger.info("Creating OCI container: {s}", .{self.cli_args.container_id.?});
        
        // Step 1: Create OCI bundle
        try self.createOciBundle();
        
        // Step 2: Validate OCI configuration
        try self.validateOciConfiguration();
        
        // Step 3: Select and execute runtime
        try self.executeRuntime();
        
        try self.logger.info("OCI container created successfully: {s}", .{self.cli_args.container_id.?});
    }
    
    fn createOciBundle(self: *OciContainerCreator) !void {
        try self.logger.info("Creating OCI bundle for container: {s}", .{self.cli_args.container_id.?});
        
        // Create the bundle directory structure
        try self.bundle.createBundle();
        
        // Validate the created bundle
        try self.bundle.validateBundle();
        
        try self.logger.info("OCI bundle created and validated: {s}", .{self.cli_args.bundle_path.?});
    }
    
    fn validateOciConfiguration(self: *OciContainerCreator) !void {
        try self.logger.info("Validating OCI configuration for container: {s}", .{self.cli_args.container_id.?});
        
        // Load and parse the generated config.json
        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.cli_args.bundle_path.?, "config.json" });
        defer self.allocator.free(config_path);
        
        const config_content = try std.fs.cwd().readFileAlloc(self.allocator, config_path, 1024 * 1024);
        defer self.allocator.free(config_content);
        
        // Parse JSON configuration
        var parsed = try std.json.parseFromSlice(runtime_types.OciSpec, self.allocator, config_content, .{});
        defer parsed.deinit();
        
        // Validate the OCI specification
        try self.validator.validateOciSpec(parsed.value);
        
        try self.logger.info("OCI configuration validation completed successfully");
    }
    
    fn executeRuntime(self: *OciContainerCreator) !void {
        try self.logger.info("Executing runtime for container: {s}", .{self.cli_args.container_id.?});
        
        if (self.cli_args.use_crun) {
            try self.executeCrunRuntime();
        } else if (self.cli_args.use_proxmox_lxc) {
            try self.executeProxmoxLxcRuntime();
        } else {
            return error.NoRuntimeSelected;
        }
    }
    
    fn executeCrunRuntime(self: *OciContainerCreator) !void {
        try self.logger.info("Using crun runtime for container: {s}", .{self.cli_args.container_id.?});
        
        // Build crun command
        var cmd = std.ArrayList([]const u8).init(self.allocator);
        defer cmd.deinit();
        
        try cmd.append("crun");
        try cmd.append("create");
        try cmd.append("--bundle");
        try cmd.append(self.cli_args.bundle_path.?);
        
        // Add OCI-specific options
        if (self.cli_args.no_pivot) {
            try cmd.append("--no-pivot");
        }
        if (self.cli_args.no_new_keyring) {
            try cmd.append("--no-new-keyring");
        }
        if (self.cli_args.preserve_fds) |fds| {
            try cmd.append("--preserve-fds");
            const fd_string = try self.formatFdList(fds);
            defer self.allocator.free(fd_string);
            try cmd.append(fd_string);
        }
        
        try cmd.append(self.cli_args.container_id.?);
        
        // Execute crun command
        try self.executeCommand(cmd.items, "crun");
    }
    
    fn executeProxmoxLxcRuntime(self: *OciContainerCreator) !void {
        try self.logger.info("Using Proxmox LXC runtime for container: {s}", .{self.cli_args.container_id.?});
        
        // Build Proxmox LXC command
        var cmd = std.ArrayList([]const u8).init(self.allocator);
        defer cmd.deinit();
        
        try cmd.append("pct");
        try cmd.append("create");
        try cmd.append(self.cli_args.container_id.?);
        try cmd.append("local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz");
        
        // Add LXC-specific options
        try cmd.append("--hostname");
        try cmd.append(self.cli_args.container_id.?);
        try cmd.append("--memory");
        try cmd.append("512");
        try cmd.append("--cores");
        try cmd.append("1");
        try cmd.append("--rootfs");
        try cmd.append("local-lvm:8");
        
        // Execute Proxmox LXC command
        try self.executeCommand(cmd.items, "Proxmox LXC");
    }
    
    fn executeCommand(self: *OciContainerCreator, cmd: []const []const u8, runtime_name: []const u8) !void {
        try self.logger.debug("Executing {s} command: {any}", .{runtime_name, cmd});
        
        // Create child process
        const child = std.ChildProcess.init(cmd, self.allocator);
        defer child.deinit();
        
        // Set up pipes for stdout and stderr
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        // Spawn the process
        try child.spawn();
        
        // Read output
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);
        
        const stderr = try child.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);
        
        // Wait for completion
        const term = try child.wait();
        
        // Log output
        if (stdout.len > 0) {
            try self.logger.debug("{s} stdout: {s}", .{runtime_name, stdout});
        }
        if (stderr.len > 0) {
            try self.logger.debug("{s} stderr: {s}", .{runtime_name, stderr});
        }
        
        // Check exit status
        switch (term.Exited) {
            0 => {
                try self.logger.info("{s} command executed successfully", .{runtime_name});
            },
            else => |code| {
                try self.logger.error("{s} command failed with exit code: {d}", .{runtime_name, code});
                return error.RuntimeExecutionFailed;
            },
        }
    }
    
    fn formatFdList(self: *OciContainerCreator, fds: []const u32) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();
        
        for (fds, 0..) |fd, i| {
            if (i > 0) {
                try result.append(',');
            }
            const fd_str = try std.fmt.allocPrint(self.allocator, "{d}", .{fd});
            defer self.allocator.free(fd_str);
            try result.appendSlice(fd_str);
        }
        
        return result.toOwnedSlice();
    }
    
    pub fn cleanupContainer(self: *OciContainerCreator) !void {
        try self.logger.info("Cleaning up container: {s}", .{self.cli_args.container_id.?});
        
        // Clean up bundle
        try self.bundle.cleanupBundle();
        
        try self.logger.info("Container cleanup completed: {s}", .{self.cli_args.container_id.?});
    }
    
    pub fn deinit(self: *OciContainerCreator) void {
        self.bundle.cleanupBundle() catch {};
    }
};

// Error types
pub const ContainerCreatorError = error{
    NoRuntimeSelected,
    RuntimeExecutionFailed,
    BundleCreationFailed,
    ConfigurationValidationFailed,
    CommandExecutionFailed,
};
