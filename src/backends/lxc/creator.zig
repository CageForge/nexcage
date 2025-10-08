const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const config_parser = @import("../../oci/config_parser.zig");

/// LXC container creator using pct
pub const LxcCreator = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) LxcCreator {
        return LxcCreator{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Create LXC container from parsed config
    pub fn createContainer(
        self: *LxcCreator,
        vmid: u32,
        lxc_config: *const config_parser.ConfigParser.LxcConfig,
    ) !void {
        try self.logger.info("Creating LXC container with VMID {d}", .{vmid});

        // Build pct create command
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append("pct");
        try args.append("create");
        
        // VMID
        const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid});
        defer self.allocator.free(vmid_str);
        try args.append(vmid_str);

        // Template (use /dev/null as we'll set rootfs directly)
        try args.append("/dev/null");

        // Rootfs
        try args.append("--rootfs");
        const rootfs_arg = try std.fmt.allocPrint(self.allocator, "local:2,mp={s}", .{lxc_config.rootfs_path});
        defer self.allocator.free(rootfs_arg);
        try args.append(rootfs_arg);

        // Hostname
        try args.append("--hostname");
        try args.append(lxc_config.hostname);

        // Memory
        if (lxc_config.memory_mb) |mem| {
            try args.append("--memory");
            const mem_str = try std.fmt.allocPrint(self.allocator, "{d}", .{mem});
            defer self.allocator.free(mem_str);
            try args.append(mem_str);
        }

        // CPU cores
        if (lxc_config.cpu_cores) |cores| {
            try args.append("--cores");
            const cores_str = try std.fmt.allocPrint(self.allocator, "{d}", .{cores});
            defer self.allocator.free(cores_str);
            try args.append(cores_str);
        }

        // Unprivileged
        try args.append("--unprivileged");
        try args.append(if (lxc_config.unprivileged) "1" else "0");

        // Features
        if (lxc_config.features.len > 0) {
            try args.append("--features");
            const features_str = try std.mem.join(self.allocator, ",", lxc_config.features);
            defer self.allocator.free(features_str);
            try args.append(features_str);
        }

        // Network (default bridge)
        try args.append("--net0");
        try args.append("name=eth0,bridge=vmbr0,ip=dhcp");

        // Execute pct create
        const argv = try args.toOwnedSlice();
        defer self.allocator.free(argv);

        try self.logger.debug("Executing: pct create {d} ...", .{vmid});

        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = argv,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            try self.logger.err("pct create failed: {s}", .{result.stderr});
            return error.LxcCreateFailed;
        }

        try self.logger.info("LXC container created successfully: VMID {d}", .{vmid});
    }

    /// Configure environment variables in LXC container
    pub fn configureEnvironment(
        self: *LxcCreator,
        vmid: u32,
        env_vars: []const []const u8,
    ) !void {
        try self.logger.debug("Configuring environment for VMID {d}", .{vmid});

        const vmid_str = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid});
        defer self.allocator.free(vmid_str);

        for (env_vars) |env_var| {
            // Parse KEY=VALUE
            const eq_pos = std.mem.indexOf(u8, env_var, "=") orelse continue;
            const key = env_var[0..eq_pos];
            const value = env_var[eq_pos + 1 ..];

            const lxc_env = try std.fmt.allocPrint(
                self.allocator,
                "lxc.environment.{s}={s}",
                .{ key, value },
            );
            defer self.allocator.free(lxc_env);

            const args = [_][]const u8{
                "pct",
                "set",
                vmid_str,
                "--set",
                lxc_env,
            };

            const result = try std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &args,
            });
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                try self.logger.warn("Failed to set env {s}: {s}", .{ key, result.stderr });
            }
        }

        try self.logger.debug("Environment configured for VMID {d}", .{vmid});
    }

    /// Configure additional mounts
    pub fn configureMounts(
        self: *LxcCreator,
        vmid: u32,
        mounts: []const config_parser.ConfigParser.LxcConfig.Mount,
    ) !void {
        _ = vmid;
        _ = mounts;
        
        try self.logger.debug("Mount configuration not yet implemented", .{});
        // TODO: Implement mount configuration using pct set --mpX
    }
};
