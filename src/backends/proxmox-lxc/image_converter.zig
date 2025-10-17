const std = @import("std");
const core = @import("core");
const oci_bundle = @import("oci_bundle.zig");

/// Image converter for transforming OCI bundles into LXC rootfs and Proxmox templates
pub const ImageConverter = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Convert OCI bundle to LXC rootfs directory
    pub fn convertOciToLxcRootfs(self: *Self, oci_bundle_path: []const u8, output_dir: []const u8) !void {
        if (self.logger) |log| try log.info("Converting OCI bundle to LXC rootfs: {s} -> {s}", .{ oci_bundle_path, output_dir });

        // Parse OCI bundle configuration
        var parser = oci_bundle.OciBundleParser.init(self.allocator, self.logger);
        var config = try parser.parseBundle(oci_bundle_path);
        defer config.deinit();

        // Create output directory
        try std.fs.cwd().makePath(output_dir);

        // Extract rootfs from OCI bundle
        const rootfs_source = try self.getRootfsPath(oci_bundle_path, &config);
        defer self.allocator.free(rootfs_source);
        try self.extractRootfs(rootfs_source, output_dir);

        // Apply LXC-specific configurations
        try self.applyLxcConfigurations(output_dir, &config);

        if (self.logger) |log| try log.info("Successfully converted OCI bundle to LXC rootfs", .{});
    }

    /// Create Proxmox LXC template from rootfs directory
    pub fn createProxmoxTemplate(self: *Self, rootfs_dir: []const u8, template_name: []const u8, storage: []const u8) !void {
        if (self.logger) |log| try log.info("Creating Proxmox LXC template: {s} from {s}", .{ template_name, rootfs_dir });

        // Create template archive
        const archive_path = try self.createTemplateArchive(rootfs_dir, template_name);
        defer self.allocator.free(archive_path);

        // Upload to Proxmox storage
        try self.uploadTemplateToStorage(archive_path, template_name, storage);

        if (self.logger) |log| try log.info("Successfully created Proxmox LXC template: {s}", .{template_name});
    }

    /// Convert OCI bundle directly to Proxmox LXC template
    pub fn convertOciToProxmoxTemplate(self: *Self, oci_bundle_path: []const u8, template_name: []const u8, storage: []const u8) !void {
        const temp_rootfs = try std.fmt.allocPrint(self.allocator, "/tmp/lxc-rootfs-{s}", .{template_name});
        defer self.allocator.free(temp_rootfs);

        // Convert OCI to LXC rootfs
        try self.convertOciToLxcRootfs(oci_bundle_path, temp_rootfs);

        // Create Proxmox template
        try self.createProxmoxTemplate(temp_rootfs, template_name, storage);

        // Cleanup
        try self.cleanupDirectory(temp_rootfs);
    }

    /// Get rootfs path from OCI bundle
    fn getRootfsPath(self: *Self, bundle_path: []const u8, config: *const oci_bundle.OciBundleConfig) ![]const u8 {
        // Use rootfs_path from config
        return try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ bundle_path, config.rootfs_path });
    }

    /// Extract rootfs from source to destination
    fn extractRootfs(self: *Self, source_path: []const u8, dest_path: []const u8) !void {
        if (self.logger) |log| try log.info("Extracting rootfs: {s} -> {s}", .{ source_path, dest_path });

        // Check if source is a directory or archive
        if (self.logger) |log| try log.info("Attempting to open source path: {s}", .{source_path});
        var source_dir = std.fs.cwd().openDir(source_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                if (self.logger) |log| try log.info("Source path not found as directory, trying as archive: {s}", .{source_path});
                // Try as archive
                return self.extractArchive(source_path, dest_path);
            },
            else => {
                if (self.logger) |log| try log.err("Failed to open source path: {s} ({})", .{ source_path, err });
                return err;
            },
        };
        defer source_dir.close();

        // Copy directory contents
        try self.copyDirectoryRecursive(source_dir, dest_path);
    }

    /// Extract archive (tar, tar.gz, tar.zst) to destination
    fn extractArchive(self: *Self, archive_path: []const u8, dest_path: []const u8) !void {
        if (self.logger) |log| try log.info("Extracting archive: {s} -> {s}", .{ archive_path, dest_path });

        // Determine archive type and extract accordingly
        if (std.mem.endsWith(u8, archive_path, ".tar.zst")) {
            try self.extractTarZst(archive_path, dest_path);
        } else if (std.mem.endsWith(u8, archive_path, ".tar.gz")) {
            try self.extractTarGz(archive_path, dest_path);
        } else if (std.mem.endsWith(u8, archive_path, ".tar")) {
            try self.extractTar(archive_path, dest_path);
        } else {
            // If not an archive, treat as directory and copy contents
            if (self.logger) |log| try log.info("Treating as directory: {s}", .{archive_path});
            var source_dir = std.fs.cwd().openDir(archive_path, .{}) catch |err| {
                if (self.logger) |log| try log.err("Cannot open directory: {s} ({})", .{ archive_path, err });
                return err;
            };
            defer source_dir.close();
            try self.copyDirectoryRecursive(source_dir, dest_path);
        }
    }

    /// Extract tar.zst archive
    fn extractTarZst(self: *Self, archive_path: []const u8, dest_path: []const u8) !void {
        const args = [_][]const u8{ "tar", "--zstd", "-xf", archive_path, "-C", dest_path };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to extract tar.zst: {s}", .{result.stderr});
            return error.ExtractionFailed;
        }
    }

    /// Extract tar.gz archive
    fn extractTarGz(self: *Self, archive_path: []const u8, dest_path: []const u8) !void {
        const args = [_][]const u8{ "tar", "-zxf", archive_path, "-C", dest_path };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to extract tar.gz: {s}", .{result.stderr});
            return error.ExtractionFailed;
        }
    }

    /// Extract tar archive
    fn extractTar(self: *Self, archive_path: []const u8, dest_path: []const u8) !void {
        const args = [_][]const u8{ "tar", "-xf", archive_path, "-C", dest_path };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to extract tar: {s}", .{result.stderr});
            return error.ExtractionFailed;
        }
    }

    /// Copy directory recursively
    fn copyDirectoryRecursive(self: *Self, source_dir: std.fs.Dir, dest_path: []const u8) !void {
        var iterator = source_dir.iterate();
        while (try iterator.next()) |entry| {
            const source_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dest_path, entry.name });
            defer self.allocator.free(source_path);

            switch (entry.kind) {
                .directory => {
                    try std.fs.cwd().makePath(source_path);
                    var subdir = try source_dir.openDir(entry.name, .{});
                    defer subdir.close();
                    try self.copyDirectoryRecursive(subdir, source_path);
                },
                .file => {
                    const source_file = try source_dir.openFile(entry.name, .{});
                    defer source_file.close();
                    const dest_file = try std.fs.cwd().createFile(source_path, .{});
                    defer dest_file.close();
                    _ = try source_file.copyRangeAll(0, dest_file, 0, std.math.maxInt(u64));
                },
                .sym_link => {
                    const link_target = try source_dir.readLink(entry.name, &[_]u8{});
                    try std.fs.cwd().symLink(link_target, source_path, .{});
                },
                else => {
                    if (self.logger) |log| try log.warn("Skipping unsupported entry type: {s}", .{entry.name});
                },
            }
        }
    }

    /// Apply LXC-specific configurations to rootfs
    fn applyLxcConfigurations(self: *Self, rootfs_path: []const u8, config: *const oci_bundle.OciBundleConfig) !void {
        if (self.logger) |log| try log.info("Applying LXC configurations to rootfs: {s}", .{rootfs_path});

        // Create essential LXC directories
        try self.createLxcDirectories(rootfs_path);

        // Configure hostname if specified
        if (config.hostname) |hostname| {
            try self.setHostname(rootfs_path, hostname);
        }

        // Configure network interfaces
        try self.configureNetwork(rootfs_path, config);

        // Set up init system
        try self.setupInitSystem(rootfs_path, config);
    }

    /// Create essential LXC directories
    fn createLxcDirectories(self: *Self, rootfs_path: []const u8) !void {
        const dirs = [_][]const u8{
            "dev", "proc", "sys", "tmp", "var/tmp", "var/log", "var/cache", "var/lib", "var/run",
            "etc", "etc/init.d", "etc/rc.d", "etc/systemd", "etc/systemd/system",
            "root", "home", "opt", "usr/local", "mnt", "media"
        };

        for (dirs) |dir| {
            const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rootfs_path, dir });
            defer self.allocator.free(full_path);
            std.fs.cwd().makePath(full_path) catch |err| switch (err) {
                error.PathAlreadyExists => continue,
                else => return err,
            };
        }
    }

    /// Set hostname in rootfs
    fn setHostname(self: *Self, rootfs_path: []const u8, hostname: []const u8) !void {
        const hostname_path = try std.fmt.allocPrint(self.allocator, "{s}/etc/hostname", .{rootfs_path});
        defer self.allocator.free(hostname_path);

        const file = try std.fs.cwd().createFile(hostname_path, .{});
        defer file.close();
        try file.writeAll(hostname);
        try file.writeAll("\n");
    }

    /// Configure network interfaces
    fn configureNetwork(self: *Self, rootfs_path: []const u8, config: *const oci_bundle.OciBundleConfig) !void {
        _ = config;
        // Create basic network configuration
        const network_path = try std.fmt.allocPrint(self.allocator, "{s}/etc/network/interfaces", .{rootfs_path});
        defer self.allocator.free(network_path);

        const file = try std.fs.cwd().createFile(network_path, .{});
        defer file.close();
        
        const network_config = 
            \\auto lo
            \\iface lo inet loopback
            \\
            \\auto eth0
            \\iface eth0 inet dhcp
            \\
        ;
        try file.writeAll(network_config);
    }

    /// Set up init system
    fn setupInitSystem(self: *Self, rootfs_path: []const u8, config: *const oci_bundle.OciBundleConfig) !void {
        _ = config;
        // Create basic init script for LXC
        const init_path = try std.fmt.allocPrint(self.allocator, "{s}/sbin/init", .{rootfs_path});
        defer self.allocator.free(init_path);

        const file = try std.fs.cwd().createFile(init_path, .{});
        defer file.close();
        
        const init_script = 
            \\#!/bin/sh
            \\# LXC init script
            \\
            \\# Mount essential filesystems
            \\mount -t proc proc /proc
            \\mount -t sysfs sysfs /sys
            \\mount -t devtmpfs devtmpfs /dev
            \\
            \\# Start essential services
            \\if [ -x /etc/init.d/rcS ]; then
            \\    /etc/init.d/rcS
            \\fi
            \\
            \\# Keep container running
            \\while true; do
            \\    sleep 3600
            \\done
            \\
        ;
        try file.writeAll(init_script);
        
        // Note: chmod would be needed here in a real implementation
    }

    /// Create template archive from rootfs
    fn createTemplateArchive(self: *Self, rootfs_dir: []const u8, template_name: []const u8) ![]const u8 {
        const archive_name = try std.fmt.allocPrint(self.allocator, "{s}.tar.zst", .{template_name});
        const archive_path = try std.fmt.allocPrint(self.allocator, "/tmp/{s}", .{archive_name});
        defer self.allocator.free(archive_name);

        if (self.logger) |log| try log.info("Creating template archive: {s}", .{archive_path});

        const args = [_][]const u8{ "tar", "--zstd", "-cf", archive_path, "-C", rootfs_dir, "." };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to create template archive: {s}", .{result.stderr});
            return error.ArchiveCreationFailed;
        }

        return archive_path;
    }

    /// Upload template to Proxmox storage
    fn uploadTemplateToStorage(self: *Self, archive_path: []const u8, template_name: []const u8, storage: []const u8) !void {
        _ = storage;
        const storage_path = try std.fmt.allocPrint(self.allocator, "/var/lib/vz/template/cache/{s}.tar.zst", .{template_name});
        defer self.allocator.free(storage_path);

        if (self.logger) |log| try log.info("Uploading template to storage: {s} -> {s}", .{ archive_path, storage_path });

        // Copy archive to Proxmox template storage
        const args = [_][]const u8{ "cp", archive_path, storage_path };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to upload template: {s}", .{result.stderr});
            return error.UploadFailed;
        }

        // Set proper permissions
        const chmod_args = [_][]const u8{ "chmod", "644", storage_path };
        const chmod_result = try self.runCommand(&chmod_args);
        defer self.allocator.free(chmod_result.stdout);
        defer self.allocator.free(chmod_result.stderr);
    }

    /// Cleanup directory
    fn cleanupDirectory(self: *Self, dir_path: []const u8) !void {
        if (self.logger) |log| try log.info("Cleaning up directory: {s}", .{dir_path});
        
        const args = [_][]const u8{ "rm", "-rf", dir_path };
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
    }

    /// Run shell command
    fn runCommand(self: *Self, args: []const []const u8) !CommandResult {
        var child = std.process.Child.init(args, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        const stdout = try child.stdout.?.readToEndAlloc(self.allocator, 1024 * 1024);
        const stderr = try child.stderr.?.readToEndAlloc(self.allocator, 1024 * 1024);
        
        const term = try child.wait();
        
        return CommandResult{
            .stdout = stdout,
            .stderr = stderr,
            .exit_code = switch (term) {
                .Exited => |code| @intCast(code),
                else => 1,
            },
        };
    }
};

/// Command execution result
const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};
