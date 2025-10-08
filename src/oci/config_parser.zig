const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const logger_mod = @import("logger");
const types = @import("types");

/// OCI config.json parser for LXC container creation
pub const ConfigParser = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) ConfigParser {
        return ConfigParser{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Parse OCI config.json from bundle
    pub fn parseConfig(self: *ConfigParser, bundle_path: []const u8) !types.OciSpec {
        const config_path = try fs.path.join(self.allocator, &[_][]const u8{ bundle_path, "config.json" });
        defer self.allocator.free(config_path);

        try self.logger.debug("Parsing config from: {s}", .{config_path});

        const file = try fs.cwd().openFile(config_path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        const parsed = try std.json.parseFromSlice(types.OciSpec, self.allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        // Deep copy the parsed spec
        return try self.deepCopySpec(&parsed.value);
    }

    /// Deep copy OCI spec
    fn deepCopySpec(self: *ConfigParser, spec: *const types.OciSpec) !types.OciSpec {
        return types.OciSpec{
            .ociVersion = try self.allocator.dupe(u8, spec.ociVersion),
            .process = if (spec.process) |*p| try self.deepCopyProcess(p) else null,
            .root = if (spec.root) |*r| try self.deepCopyRoot(r) else null,
            .hostname = if (spec.hostname) |h| try self.allocator.dupe(u8, h) else null,
            .mounts = if (spec.mounts) |mounts| try self.deepCopyMounts(mounts) else null,
            .hooks = null, // TODO: Implement hooks copy
            .annotations = null, // TODO: Implement annotations copy
            .linux = if (spec.linux) |*l| try self.deepCopyLinux(l) else null,
            .windows = null,
            .vm = null,
        };
    }

    fn deepCopyProcess(self: *ConfigParser, process: *const types.Process) !types.Process {
        return types.Process{
            .terminal = process.terminal,
            .consoleSize = process.consoleSize,
            .user = types.User{
                .uid = process.user.uid,
                .gid = process.user.gid,
                .additionalGids = if (process.user.additionalGids) |gids| 
                    try self.allocator.dupe(u32, gids) 
                else null,
            },
            .args = if (process.args) |args| try self.deepCopyStringArray(args) else null,
            .env = if (process.env) |env| try self.deepCopyStringArray(env) else null,
            .cwd = try self.allocator.dupe(u8, process.cwd),
            .capabilities = null, // TODO: Copy capabilities
            .rlimits = null, // TODO: Copy rlimits
            .noNewPrivileges = process.noNewPrivileges,
            .apparmorProfile = if (process.apparmorProfile) |p| try self.allocator.dupe(u8, p) else null,
            .oomScoreAdj = process.oomScoreAdj,
            .selinuxLabel = if (process.selinuxLabel) |l| try self.allocator.dupe(u8, l) else null,
        };
    }

    fn deepCopyRoot(self: *ConfigParser, root: *const types.Root) !types.Root {
        return types.Root{
            .path = try self.allocator.dupe(u8, root.path),
            .readonly = root.readonly,
        };
    }

    fn deepCopyMounts(self: *ConfigParser, mounts: []const types.Mount) ![]types.Mount {
        const copied = try self.allocator.alloc(types.Mount, mounts.len);
        for (mounts, 0..) |mount, i| {
            copied[i] = types.Mount{
                .destination = try self.allocator.dupe(u8, mount.destination),
                .type = if (mount.type) |t| try self.allocator.dupe(u8, t) else null,
                .source = if (mount.source) |s| try self.allocator.dupe(u8, s) else null,
                .options = if (mount.options) |opts| try self.deepCopyStringArray(opts) else null,
            };
        }
        return copied;
    }

    fn deepCopyLinux(self: *ConfigParser, linux: *const types.Linux) !types.Linux {
        return types.Linux{
            .namespaces = if (linux.namespaces) |ns| try self.deepCopyNamespaces(ns) else null,
            .uidMappings = null, // TODO: Copy UID mappings
            .gidMappings = null, // TODO: Copy GID mappings
            .devices = null, // TODO: Copy devices
            .cgroupsPath = if (linux.cgroupsPath) |p| try self.allocator.dupe(u8, p) else null,
            .resources = null, // TODO: Copy resources
            .intelRdt = null,
            .sysctl = null, // TODO: Copy sysctl
            .seccomp = null, // TODO: Copy seccomp
            .rootfsPropagation = if (linux.rootfsPropagation) |p| try self.allocator.dupe(u8, p) else null,
            .maskedPaths = if (linux.maskedPaths) |paths| try self.deepCopyStringArray(paths) else null,
            .readonlyPaths = if (linux.readonlyPaths) |paths| try self.deepCopyStringArray(paths) else null,
            .mountLabel = if (linux.mountLabel) |l| try self.allocator.dupe(u8, l) else null,
        };
    }

    fn deepCopyNamespaces(self: *ConfigParser, namespaces: []const types.Namespace) ![]types.Namespace {
        const copied = try self.allocator.alloc(types.Namespace, namespaces.len);
        for (namespaces, 0..) |ns, i| {
            copied[i] = types.Namespace{
                .type = try self.allocator.dupe(u8, ns.type),
                .path = if (ns.path) |p| try self.allocator.dupe(u8, p) else null,
            };
        }
        return copied;
    }

    fn deepCopyStringArray(self: *ConfigParser, array: []const []const u8) ![][]const u8 {
        const copied = try self.allocator.alloc([]const u8, array.len);
        for (array, 0..) |str, i| {
            copied[i] = try self.allocator.dupe(u8, str);
        }
        return copied;
    }

    /// Extract LXC-specific configuration from OCI spec
    pub const LxcConfig = struct {
        hostname: []const u8,
        rootfs_path: []const u8,
        memory_mb: ?u64 = null,
        cpu_cores: ?u32 = null,
        unprivileged: bool = true,
        command: []const []const u8,
        env: []const []const u8,
        mounts: []const types.Mount,
        features: []const []const u8, // nesting, keyctl, etc.

        pub fn deinit(self: *LxcConfig, allocator: Allocator) void {
            allocator.free(self.hostname);
            allocator.free(self.rootfs_path);
            for (self.command) |cmd| {
                allocator.free(cmd);
            }
            allocator.free(self.command);
            for (self.env) |e| {
                allocator.free(e);
            }
            allocator.free(self.env);
            for (self.mounts) |*mount| {
                allocator.free(mount.destination);
                if (mount.type) |t| allocator.free(t);
                if (mount.source) |s| allocator.free(s);
                if (mount.options) |opts| {
                    for (opts) |opt| allocator.free(opt);
                    allocator.free(opts);
                }
            }
            allocator.free(self.mounts);
            for (self.features) |f| {
                allocator.free(f);
            }
            allocator.free(self.features);
        }
    };

    /// Convert OCI spec to LXC configuration
    pub fn toLxcConfig(self: *ConfigParser, spec: *const types.OciSpec, bundle_path: []const u8) !LxcConfig {
        try self.logger.debug("Converting OCI spec to LXC config", .{});

        // Extract hostname
        const hostname = if (spec.hostname) |h|
            try self.allocator.dupe(u8, h)
        else
            try self.allocator.dupe(u8, "container");

        // Extract rootfs path
        const rootfs_path = if (spec.root) |root| blk: {
            const path = try fs.path.join(self.allocator, &[_][]const u8{ bundle_path, root.path });
            break :blk path;
        } else {
            return error.RootfsNotSpecified;
        };

        // Extract command
        const command = if (spec.process) |process| blk: {
            if (process.args) |args| {
                const cmd = try self.allocator.alloc([]const u8, args.len);
                for (args, 0..) |arg, i| {
                    cmd[i] = try self.allocator.dupe(u8, arg);
                }
                break :blk cmd;
            } else {
                const default_cmd = try self.allocator.alloc([]const u8, 1);
                default_cmd[0] = try self.allocator.dupe(u8, "/bin/sh");
                break :blk default_cmd;
            }
        } else {
            const default_cmd = try self.allocator.alloc([]const u8, 1);
            default_cmd[0] = try self.allocator.dupe(u8, "/bin/sh");
            break :blk default_cmd;
        };

        // Extract environment variables
        const env = if (spec.process) |process| blk: {
            if (process.env) |e| {
                const env_copy = try self.allocator.alloc([]const u8, e.len);
                for (e, 0..) |env_var, i| {
                    env_copy[i] = try self.allocator.dupe(u8, env_var);
                }
                break :blk env_copy;
            } else {
                break :blk try self.getDefaultEnv();
            }
        } else {
            break :blk try self.getDefaultEnv();
        };

        // Extract mounts
        const mounts = if (spec.mounts) |m|
            try self.deepCopyMounts(m)
        else
            try self.allocator.alloc(types.Mount, 0);

        // Extract resources
        var memory_mb: ?u64 = null;
        var cpu_cores: ?u32 = null;
        if (spec.linux) |linux| {
            if (linux.resources) |resources| {
                if (resources.memory) |mem| {
                    if (mem.limit) |limit| {
                        memory_mb = @as(u64, @intCast(limit / (1024 * 1024))); // Convert bytes to MB
                    }
                }
                if (resources.cpu) |cpu| {
                    if (cpu.quota) |quota| {
                        if (cpu.period) |period| {
                            cpu_cores = @as(u32, @intCast(@divTrunc(quota, period)));
                        }
                    }
                }
            }
        }

        // Determine features (nesting, keyctl, etc.)
        var features = std.ArrayList([]const u8).init(self.allocator);
        defer features.deinit();
        
        // Enable nesting by default for better compatibility
        try features.append(try self.allocator.dupe(u8, "nesting=1"));
        
        // Check if keyctl should be enabled
        if (spec.linux) |linux| {
            if (linux.namespaces) |namespaces| {
                for (namespaces) |ns| {
                    if (std.mem.eql(u8, ns.type, "user")) {
                        try features.append(try self.allocator.dupe(u8, "keyctl=1"));
                        break;
                    }
                }
            }
        }

        // Determine if container should be unprivileged
        const unprivileged = if (spec.linux) |linux| blk: {
            if (linux.namespaces) |namespaces| {
                for (namespaces) |ns| {
                    if (std.mem.eql(u8, ns.type, "user")) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        } else false;

        return LxcConfig{
            .hostname = hostname,
            .rootfs_path = rootfs_path,
            .memory_mb = memory_mb,
            .cpu_cores = cpu_cores,
            .unprivileged = unprivileged,
            .command = command,
            .env = env,
            .mounts = mounts,
            .features = try features.toOwnedSlice(),
        };
    }

    fn getDefaultEnv(self: *ConfigParser) ![][]const u8 {
        const default_env = [_][]const u8{
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm",
        };
        
        const env = try self.allocator.alloc([]const u8, default_env.len);
        for (default_env, 0..) |e, i| {
            env[i] = try self.allocator.dupe(u8, e);
        }
        return env;
    }
};
