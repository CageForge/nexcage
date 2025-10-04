const std = @import("std");
const core = @import("core");

/// Crun backend driver for OCI containers
pub const CrunDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Create an OCI container using crun
    pub fn create(self: *Self, config: core.types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating OCI container with crun: {s}", .{config.name});
        }

        // Create OCI bundle directory
        const bundle_path = try std.fmt.allocPrint(self.allocator, "/var/lib/proxmox-lxcri/bundles/{s}", .{config.name});
        defer self.allocator.free(bundle_path);

        // Create bundle directory
        std.fs.cwd().makePath(bundle_path) catch |err| {
            if (self.logger) |log| {
                try log.err("Failed to create bundle directory {s}: {}", .{ bundle_path, err });
            }
            return err;
        };

        // Generate basic OCI config.json
        try self.generateOciConfig(config, bundle_path);

        // Run crun create command
        const args = [_][]const u8{
            "crun",
            "create",
            "--bundle", bundle_path,
            config.name,
        };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.err("Failed to create OCI container with crun: {s}", .{result.stderr});
            }
            return error.CrunCreateFailed;
        }

        if (self.logger) |log| {
            try log.info("Successfully created OCI container with crun: {s}", .{config.name});
        }
    }

    /// Start an OCI container using crun
    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting OCI container with crun: {s}", .{container_id});
        }

        const args = [_][]const u8{
            "crun",
            "start",
            container_id,
        };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.err("Failed to start OCI container with crun: {s}", .{result.stderr});
            }
            return error.CrunStartFailed;
        }

        if (self.logger) |log| {
            try log.info("Successfully started OCI container with crun: {s}", .{container_id});
        }
    }

    /// Stop an OCI container using crun
    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping OCI container with crun: {s}", .{container_id});
        }

        const args = [_][]const u8{
            "crun",
            "kill",
            container_id,
            "TERM",
        };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.err("Failed to stop OCI container with crun: {s}", .{result.stderr});
            }
            return error.CrunStopFailed;
        }

        if (self.logger) |log| {
            try log.info("Successfully stopped OCI container with crun: {s}", .{container_id});
        }
    }

    /// Delete an OCI container using crun
    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting OCI container with crun: {s}", .{container_id});
        }

        const args = [_][]const u8{
            "crun",
            "delete",
            container_id,
        };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.err("Failed to delete OCI container with crun: {s}", .{result.stderr});
            }
            return error.CrunDeleteFailed;
        }

        if (self.logger) |log| {
            try log.info("Successfully deleted OCI container with crun: {s}", .{container_id});
        }
    }

    /// Run a command and return the result
    fn runCommand(self: *Self, args: []const []const u8) !CommandResult {
        const res = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            // Return a synthetic result for missing binaries
            if (err == error.FileNotFound) {
                return CommandResult{
                    .stdout = try self.allocator.dupe(u8, ""),
                    .stderr = try self.allocator.dupe(u8, "command not found"),
                    .exit_code = 127,
                };
            }
            return err;
        };

        const exit_code: u8 = switch (res.term) {
            .Exited => |code| code,
            .Signal => |sig| @as(u8, @intCast(128 + sig)),
            else => 1,
        };

        return CommandResult{
            .stdout = res.stdout,
            .stderr = res.stderr,
            .exit_code = exit_code,
        };
    }

    /// Generate basic OCI config.json
    fn generateOciConfig(self: *Self, config: core.types.SandboxConfig, bundle_path: []const u8) !void {
        _ = config;
        const config_path = try std.fmt.allocPrint(self.allocator, "{s}/config.json", .{bundle_path});
        defer self.allocator.free(config_path);

        const file = try std.fs.cwd().createFile(config_path, .{});
        defer file.close();

        // Minimal OCI config.json
        try file.writeAll("{\"ociVersion\":\"1.0.0\",\"process\":{\"terminal\":true,\"user\":{\"uid\":0,\"gid\":0},\"args\":[\"/bin/sh\"],\"env\":[\"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"]},\"root\":{\"path\":\"rootfs\",\"readonly\":false},\"hostname\":\"container\",\"linux\":{\"namespaces\":[{\"type\":\"pid\"},{\"type\":\"network\"},{\"type\":\"ipc\"},{\"type\":\"uts\"},{\"type\":\"mount\"}]}}");
    }
};

const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};