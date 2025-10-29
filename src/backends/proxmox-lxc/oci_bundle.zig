const std = @import("std");
const core = @import("core");

/// OCI Bundle parser for Proxmox LXC backend
/// Parses OCI bundle (config.json + rootfs) and converts to LXC configuration
pub const OciBundleParser = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) OciBundleParser {
        return OciBundleParser{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Parse OCI bundle and extract configuration
    pub fn parseBundle(self: *OciBundleParser, bundle_path: []const u8) !OciBundleConfig {
        if (self.logger) |log| {
            try log.info("Parsing OCI bundle from: {s}", .{bundle_path});
        }

        const config_path = try std.fs.path.join(self.allocator, &[_][]const u8{ bundle_path, "config.json" });
        defer self.allocator.free(config_path);

        const rootfs_path = try std.fs.path.join(self.allocator, &[_][]const u8{ bundle_path, "rootfs" });
        defer self.allocator.free(rootfs_path);

        // Check if files exist
        const config_file = std.fs.cwd().openFile(config_path, .{}) catch |err| {
            if (self.logger) |log| {
                try log.err("Failed to open config.json: {}", .{err});
            }
            return error.ConfigFileNotFound;
        };
        defer config_file.close();

        // Check if rootfs directory exists
        var rootfs_dir = std.fs.cwd().openDir(rootfs_path, .{}) catch |err| {
            if (self.logger) |log| {
                try log.err("Failed to open rootfs directory: {}", .{err});
            }
            return error.RootfsNotFound;
        };
        defer rootfs_dir.close();

        // Read and parse config.json
        const content = try config_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        var bundle_config = try self.parseOciConfig(&parsed.value, rootfs_path);
        
        // Try to parse metadata.json if it exists
        const metadata_path = try std.fs.path.join(self.allocator, &[_][]const u8{ bundle_path, "metadata.json" });
        defer self.allocator.free(metadata_path);
        
        if (std.fs.cwd().openFile(metadata_path, .{})) |metadata_file| {
            defer metadata_file.close();
            
            const metadata_content = metadata_file.readToEndAlloc(self.allocator, 1024 * 1024) catch |err| {
                if (self.logger) |log| {
                    try log.warn("Failed to read metadata.json: {}", .{err});
                }
                return bundle_config;
            };
            defer self.allocator.free(metadata_content);
            
            const metadata_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, metadata_content, .{
                .allocate = .alloc_always,
                .ignore_unknown_fields = true,
            }) catch |err| {
                if (self.logger) |log| {
                    try log.warn("Failed to parse metadata.json: {}", .{err});
                }
                return bundle_config;
            };
            defer metadata_parsed.deinit();
            
            try self.parseMetadata(&metadata_parsed.value, &bundle_config);
        } else |_| {
            if (self.logger) |log| {
                try log.info("No metadata.json found in bundle, using config.json only", .{});
            }
        }
        
        return bundle_config;
    }

    /// Parse OCI config.json and extract relevant fields
    fn parseOciConfig(self: *OciBundleParser, config: *const std.json.Value, rootfs_path: []const u8) !OciBundleConfig {
        var bundle_config = OciBundleConfig{
            .allocator = self.allocator,
            .rootfs_path = try self.allocator.dupe(u8, rootfs_path),
            .hostname = null,
            .process_args = null,
            .environment = null,
            .mounts = null,
            .memory_limit = null,
            .cpu_limit = null,
            .capabilities = null,
            .seccomp_profile = null,
        };

        if (config.* != .object) {
            return error.InvalidConfigFormat;
        }

        const obj = config.object;

        // Parse hostname
        if (obj.get("hostname")) |hostname_val| {
            if (hostname_val == .string) {
                bundle_config.hostname = try self.allocator.dupe(u8, hostname_val.string);
            }
        }

        // Parse process
        if (obj.get("process")) |process_val| {
            if (process_val == .object) {
                const process_obj = process_val.object;

                // Parse args (command to run)
                if (process_obj.get("args")) |args_val| {
                    if (args_val == .array) {
                        const args_array = args_val.array;
                        var process_args = try self.allocator.alloc([]const u8, args_array.items.len);
                        for (args_array.items, 0..) |arg_val, i| {
                            if (arg_val == .string) {
                                process_args[i] = try self.allocator.dupe(u8, arg_val.string);
                            }
                        }
                        bundle_config.process_args = process_args;
                    }
                }

                // Parse environment variables
                if (process_obj.get("env")) |env_val| {
                    if (env_val == .array) {
                        const env_array = env_val.array;
                        var environment = try self.allocator.alloc([]const u8, env_array.items.len);
                        for (env_array.items, 0..) |env_val_item, i| {
                            if (env_val_item == .string) {
                                environment[i] = try self.allocator.dupe(u8, env_val_item.string);
                            }
                        }
                        bundle_config.environment = environment;
                    }
                }

                // Parse capabilities
                if (process_obj.get("capabilities")) |caps_val| {
                    if (caps_val == .object) {
                        // TODO: Parse capabilities and convert to LXC format
                        if (self.logger) |log| {
                            try log.info("Capabilities found in OCI config, will be converted to LXC format", .{});
                        }
                    }
                }
            }
        }

        // Parse mounts
        if (obj.get("mounts")) |mounts_val| {
            if (mounts_val == .array) {
                const mounts_array = mounts_val.array;
                var mounts = try self.allocator.alloc(MountConfig, mounts_array.items.len);
                for (mounts_array.items, 0..) |mount_val, i| {
                    if (mount_val == .object) {
                        const mount_obj = mount_val.object;
                        mounts[i] = MountConfig{
                            .allocator = self.allocator,
                            .source = if (mount_obj.get("source")) |s| 
                                if (s == .string) try self.allocator.dupe(u8, s.string) else null
                            else null,
                            .destination = if (mount_obj.get("destination")) |d| 
                                if (d == .string) try self.allocator.dupe(u8, d.string) else null
                            else null,
                            .type = if (mount_obj.get("type")) |t| 
                                if (t == .string) try self.allocator.dupe(u8, t.string) else null
                            else null,
                            .options = null, // TODO: Parse mount options
                        };
                    }
                }
                bundle_config.mounts = mounts;
            }
        }

        // Parse Linux resources
        if (obj.get("linux")) |linux_val| {
            if (linux_val == .object) {
                const linux_obj = linux_val.object;

                // Parse memory limit
                if (linux_obj.get("resources")) |resources_val| {
                    if (resources_val == .object) {
                        const resources_obj = resources_val.object;

                        if (resources_obj.get("memory")) |memory_val| {
                            if (memory_val == .object) {
                                const memory_obj = memory_val.object;
                                if (memory_obj.get("limit")) |limit_val| {
                                    if (limit_val == .integer) {
                                        bundle_config.memory_limit = @as(u64, @intCast(limit_val.integer));
                                    }
                                }
                            }
                        }

                        // Parse CPU limit
                        if (resources_obj.get("cpu")) |cpu_val| {
                            if (cpu_val == .object) {
                                const cpu_obj = cpu_val.object;
                                if (cpu_obj.get("shares")) |shares_val| {
                                    if (shares_val == .integer) {
                                        bundle_config.cpu_limit = @as(f64, @floatFromInt(shares_val.integer));
                                    }
                                }
                            }
                        }
                    }
                }

                // Parse seccomp profile
                if (linux_obj.get("seccomp")) |seccomp_val| {
                    if (seccomp_val == .object) {
                        const seccomp_obj = seccomp_val.object;
                        if (seccomp_obj.get("defaultAction")) |action_val| {
                            if (action_val == .string) {
                                bundle_config.seccomp_profile = try self.allocator.dupe(u8, action_val.string);
                            }
                        }
                    }
                }
            }
        }

        if (self.logger) |log| {
            try log.info("Successfully parsed OCI bundle configuration", .{});
        }

        return bundle_config;
    }
    
    /// Parse metadata.json and extract image information
    fn parseMetadata(self: *OciBundleParser, metadata: *const std.json.Value, config: *OciBundleConfig) !void {
        if (metadata.* != .object) {
            return;
        }
        
        const obj = metadata.object;
        
        // Parse image name and tag from metadata.json
        if (obj.get("image")) |image_val| {
            if (image_val == .string) {
                const image_str = image_val.string;
                
                // Split image:tag format if colon is present
                if (std.mem.indexOf(u8, image_str, ":")) |colon_pos| {
                    config.image_name = try self.allocator.dupe(u8, image_str[0..colon_pos]);
                    config.image_tag = try self.allocator.dupe(u8, image_str[colon_pos + 1..]);
                } else {
                    config.image_name = try self.allocator.dupe(u8, image_str);
                }
                
                if (self.logger) |log| {
                    try log.info("Parsed image from metadata: {s}", .{image_str});
                }
            }
        }
        
        // Parse ENTRYPOINT from metadata.json
        if (obj.get("entrypoint")) |entrypoint_val| {
            if (entrypoint_val == .array) {
                const entrypoint_array = entrypoint_val.array;
                var entrypoint = try self.allocator.alloc([]const u8, entrypoint_array.items.len);
                
                for (entrypoint_array.items, 0..) |ep_val, i| {
                    if (ep_val == .string) {
                        entrypoint[i] = try self.allocator.dupe(u8, ep_val.string);
                    }
                }
                
                config.entrypoint = entrypoint;
                
                if (self.logger) |log| {
                    try log.info("Parsed ENTRYPOINT from metadata: {d} args", .{entrypoint_array.items.len});
                }
            }
        }
        
        // Parse CMD from metadata.json
        if (obj.get("cmd")) |cmd_val| {
            if (cmd_val == .array) {
                const cmd_array = cmd_val.array;
                var cmd = try self.allocator.alloc([]const u8, cmd_array.items.len);
                
                for (cmd_array.items, 0..) |cmd_item, i| {
                    if (cmd_item == .string) {
                        cmd[i] = try self.allocator.dupe(u8, cmd_item.string);
                    }
                }
                
                config.cmd = cmd;
                
                if (self.logger) |log| {
                    try log.info("Parsed CMD from metadata: {d} args", .{cmd_array.items.len});
                }
            }
        }
        
        // Parse working directory from metadata.json
        if (obj.get("workingDir")) |workdir_val| {
            if (workdir_val == .string) {
                config.working_directory = try self.allocator.dupe(u8, workdir_val.string);
                
                if (self.logger) |log| {
                    try log.info("Parsed working directory from metadata: {s}", .{workdir_val.string});
                }
            }
        }
    }
};

/// OCI Bundle configuration extracted from config.json
pub const OciBundleConfig = struct {
    allocator: std.mem.Allocator,
    rootfs_path: []const u8,
    hostname: ?[]const u8 = null,
    process_args: ?[]const []const u8 = null,
    environment: ?[]const []const u8 = null,
    mounts: ?[]const MountConfig = null,
    memory_limit: ?u64 = null,
    cpu_limit: ?f64 = null,
    capabilities: ?[]const u8 = null,
    seccomp_profile: ?[]const u8 = null,
    
    // Extended OCI fields
    annotations: ?std.json.ObjectMap = null,
    user: ?UserConfig = null,
    working_dir: ?[]const u8 = null,
    rlimits: ?[]const RlimitConfig = null,
    devices: ?[]const DeviceConfig = null,
    namespaces: ?[]const NamespaceConfig = null,
    cgroups_path: ?[]const u8 = null,
    apparmor_profile: ?[]const u8 = null,
    selinux_label: ?[]const u8 = null,
    no_new_privileges: ?bool = null,
    oom_score_adj: ?i32 = null,
    root_readonly: ?bool = null,
    
    // Metadata.json fields extracted from OCI image metadata
    image_name: ?[]const u8 = null,
    image_tag: ?[]const u8 = null,
    entrypoint: ?[]const []const u8 = null,
    cmd: ?[]const []const u8 = null,
    working_directory: ?[]const u8 = null,

    pub fn deinit(self: *OciBundleConfig) void {
        self.allocator.free(self.rootfs_path);
        if (self.hostname) |h| self.allocator.free(h);
        if (self.process_args) |args| {
            for (args) |arg| self.allocator.free(arg);
            self.allocator.free(args);
        }
        if (self.environment) |env| {
            for (env) |e| self.allocator.free(e);
            self.allocator.free(env);
        }
        if (self.mounts) |mounts| {
            for (mounts) |mount| {
                var m = mount;
                m.deinit();
            }
            self.allocator.free(mounts);
        }
        if (self.capabilities) |caps| self.allocator.free(caps);
        if (self.seccomp_profile) |profile| self.allocator.free(profile);
        
        // Extended fields cleanup
        if (self.annotations) |*annotations| annotations.deinit();
        if (self.user) |*user| user.deinit();
        if (self.working_dir) |wd| self.allocator.free(wd);
        if (self.rlimits) |rlimits| {
            for (rlimits) |rlimit| {
                var r = rlimit;
                r.deinit();
            }
            self.allocator.free(rlimits);
        }
        if (self.devices) |devices| {
            for (devices) |device| {
                var d = device;
                d.deinit();
            }
            self.allocator.free(devices);
        }
        if (self.namespaces) |namespaces| {
            for (namespaces) |namespace| {
                var n = namespace;
                n.deinit();
            }
            self.allocator.free(namespaces);
        }
        if (self.cgroups_path) |path| self.allocator.free(path);
        if (self.apparmor_profile) |profile| self.allocator.free(profile);
        if (self.selinux_label) |label| self.allocator.free(label);
        
        // Cleanup metadata.json fields
        if (self.image_name) |name| self.allocator.free(name);
        if (self.image_tag) |tag| self.allocator.free(tag);
        if (self.entrypoint) |ep| {
            for (ep) |arg| self.allocator.free(arg);
            self.allocator.free(ep);
        }
        if (self.cmd) |cmd| {
            for (cmd) |arg| self.allocator.free(arg);
            self.allocator.free(cmd);
        }
        if (self.working_directory) |wd| self.allocator.free(wd);
    }
};

/// Mount configuration from OCI spec
pub const MountConfig = struct {
    allocator: std.mem.Allocator,
    source: ?[]const u8 = null,
    destination: ?[]const u8 = null,
    type: ?[]const u8 = null,
    options: ?[]const u8 = null,

    pub fn deinit(self: *MountConfig) void {
        if (self.source) |s| self.allocator.free(s);
        if (self.destination) |d| self.allocator.free(d);
        if (self.type) |t| self.allocator.free(t);
        if (self.options) |o| self.allocator.free(o);
    }
};

/// User configuration from OCI spec
pub const UserConfig = struct {
    allocator: std.mem.Allocator,
    uid: ?u32 = null,
    gid: ?u32 = null,
    additional_gids: ?[]const u32 = null,
    username: ?[]const u8 = null,

    pub fn deinit(self: *UserConfig) void {
        if (self.additional_gids) |gids| self.allocator.free(gids);
        if (self.username) |name| self.allocator.free(name);
    }
};

/// Resource limit configuration from OCI spec
pub const RlimitConfig = struct {
    allocator: std.mem.Allocator,
    type: []const u8,
    soft: u64,
    hard: u64,

    pub fn deinit(self: *RlimitConfig) void {
        self.allocator.free(self.type);
    }
};

/// Device configuration from OCI spec
pub const DeviceConfig = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    type: []const u8,
    major: ?i64 = null,
    minor: ?i64 = null,
    file_mode: ?u32 = null,
    uid: ?u32 = null,
    gid: ?u32 = null,

    pub fn deinit(self: *DeviceConfig) void {
        self.allocator.free(self.path);
        self.allocator.free(self.type);
    }
};

/// Namespace configuration from OCI spec
pub const NamespaceConfig = struct {
    allocator: std.mem.Allocator,
    type: []const u8,
    path: ?[]const u8 = null,

    pub fn deinit(self: *NamespaceConfig) void {
        self.allocator.free(self.type);
        if (self.path) |p| self.allocator.free(p);
    }
};
