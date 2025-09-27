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
        try std.fs.cwd().makePath(self.bundle_path);
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

    pub fn validateBundle(self: *OciBundle) !void {
        try self.logger.info("Validating OCI bundle: {s}", .{self.bundle_path});

        // Check if bundle directory exists
        const bundle_dir = try std.fs.cwd().openDir(self.bundle_path, .{});
        defer bundle_dir.close();

        // Check if rootfs exists
        try bundle_dir.access("rootfs", .{});

        // Check if config.json exists
        try bundle_dir.access("config.json", .{});

        try self.logger.info("OCI bundle validation successful: {s}", .{self.bundle_path});
    }

    pub fn cleanupBundle(self: *OciBundle) !void {
        try self.logger.info("Cleaning up OCI bundle: {s}", .{self.bundle_path});

        // Remove bundle directory recursively
        try std.fs.cwd().deleteTree(self.bundle_path);

        try self.logger.info("OCI bundle cleanup completed: {s}", .{self.bundle_path});
    }
};
