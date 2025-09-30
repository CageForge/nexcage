const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const logging = core.logging;
// const utils = @import("../../utils/mod.zig"); // Using core.utils instead
const lxc_types = @import("types.zig");

/// LXC backend driver implementation
/// LXC backend driver
pub const LxcDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*logging.LogContext = null,
    config: ?lxc_types.LxcConfig = null,

    pub fn init(allocator: std.mem.Allocator, config: types.SandboxConfig) !*Self {
        const driver = try allocator.create(Self);
        driver.* = Self{
            .allocator = allocator,
        };

        // Convert SandboxConfig to LxcConfig
        driver.config = try driver.convertToLxcConfig(config);

        return driver;
    }

    pub fn deinit(self: *Self) void {
        if (self.config) |*cfg| {
            cfg.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self, config: types.SandboxConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating LXC container: {s}", .{config.name});
        }

        // Convert SandboxConfig to LxcConfig
        var lxc_config = try self.convertToLxcConfig(config);
        defer lxc_config.deinit();

        // Build lxc-create command
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        try args.append("lxc-create");
        try args.append("-n");
        try args.append(lxc_config.name);
        try args.append("-t");
        try args.append(lxc_config.template);
        try args.append("--");
        
        // Add template-specific arguments
        if (lxc_config.arch.len > 0) {
            try args.append("--arch");
            try args.append(lxc_config.arch);
        }
        
        if (lxc_config.dist.len > 0) {
            try args.append("--dist");
            try args.append(lxc_config.dist);
        }
        
        if (lxc_config.release.len > 0) {
            try args.append("--release");
            try args.append(lxc_config.release);
        }

        // Execute lxc-create command
        const result = try self.runCommand(args.items);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to create LXC container: {s}", .{result.stderr});
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("LXC container created successfully: {s}", .{config.name});
        }
    }

    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting LXC container: {s}", .{container_id});
        }

        // Build lxc-start command
        const args = [_][]const u8{
            "lxc-start",
            "-n", container_id,
            "-d", // daemon mode
        };

        // Execute lxc-start command
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-start not found; cannot start {s}", .{container_id});
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| try log.err("Failed to start LXC container {s}: {s}", .{ container_id, result.stderr });
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("LXC container started successfully: {s}", .{container_id});
        }
    }

    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping LXC container: {s}", .{container_id});
        }

        // Build lxc-stop command
        const args = [_][]const u8{
            "lxc-stop",
            "-n", container_id,
        };

        // Execute lxc-stop command
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-stop not found; cannot stop {s}", .{container_id});
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| try log.err("Failed to stop LXC container {s}: {s}", .{ container_id, result.stderr });
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("LXC container stopped successfully: {s}", .{container_id});
        }
    }

    pub fn delete(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting LXC container: {s}", .{container_id});
        }

        // First, try to stop the container if it's running
        self.stop(container_id) catch |err| {
            if (self.logger) |log| {
                try log.warn("Failed to stop container before deletion: {}", .{err});
            }
            // Continue with deletion even if stop fails
        };

        // Build lxc-destroy command
        const args = [_][]const u8{
            "lxc-destroy",
            "-n", container_id,
        };

        // Execute lxc-destroy command
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-destroy not found; cannot delete {s}", .{container_id});
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| try log.err("Failed to delete LXC container {s}: {s}", .{ container_id, result.stderr });
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("LXC container deleted successfully: {s}", .{container_id});
        }
    }

    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]interfaces.ContainerInfo {
        if (self.logger) |log| {
            try log.info("Listing LXC containers", .{});
        }

        // Build lxc-ls command
        const args = [_][]const u8{
            "lxc-ls",
            "--format", "json",
        };

        // Execute lxc-ls command
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-ls not found; returning empty list", .{});
                return allocator.alloc(interfaces.ContainerInfo, 0);
            }
            if (self.logger) |log| try log.err("Failed to list LXC containers: {s}", .{result.stderr});
            return core.Error.RuntimeError;
        }

        // Parse JSON output and convert to ContainerInfo
        // For now, return empty list - full JSON parsing would be complex
        const containers = try allocator.alloc(interfaces.ContainerInfo, 0);
        
        if (self.logger) |log| {
            try log.info("Listed {d} LXC containers", .{containers.len});
        }
        
        return containers;
    }

    pub fn info(self: *Self, container_id: []const u8, allocator: std.mem.Allocator) !interfaces.ContainerInfo {
        if (self.logger) |log| {
            try log.info("Getting info for LXC container: {s}", .{container_id});
        }

        // Build lxc-info command
        const args = [_][]const u8{
            "lxc-info",
            "-n", container_id,
        };

        // Execute lxc-info command
        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to get info for LXC container {s}: {s}", .{ container_id, result.stderr });
            }
            return core.Error.RuntimeError;
        }

        // Parse the output to determine state
        const state = if (std.mem.indexOf(u8, result.stdout, "RUNNING")) |_|
            interfaces.ContainerState.running
        else if (std.mem.indexOf(u8, result.stdout, "STOPPED")) |_|
            interfaces.ContainerState.stopped
        else
            interfaces.ContainerState.unknown;

        const container_info = interfaces.ContainerInfo{
            .allocator = allocator,
            .id = try allocator.dupe(u8, container_id),
            .name = try allocator.dupe(u8, container_id),
            .state = state,
            .runtime_type = .lxc,
        };
        
        return container_info;
    }

    pub fn exec(self: *Self, container_id: []const u8, command: []const []const u8, allocator: std.mem.Allocator) !void {
        if (self.logger) |log| {
            try log.info("Executing command in LXC container {s}: {s}", .{ container_id, command[0] });
        }

        // Build lxc-attach command
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();
        
        try args.append("lxc-attach");
        try args.append("-n");
        try args.append(container_id);
        try args.append("--");
        
        // Add the command to execute
        for (command) |arg| {
            try args.append(arg);
        }

        // Execute lxc-attach command
        const result = try self.runCommand(args.items);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to execute command in LXC container {s}: {s}", .{ container_id, result.stderr });
            }
            return core.Error.RuntimeError;
        }

        // Print the output
        if (result.stdout.len > 0) {
            std.debug.print("{s}", .{result.stdout});
        }

        if (self.logger) |log| {
            try log.info("Command executed successfully in LXC container: {s}", .{container_id});
        }
    }

    fn convertToLxcConfig(self: *Self, config: types.SandboxConfig) !lxc_types.LxcConfig {
        var lxc_config = lxc_types.LxcConfig{
            .allocator = self.allocator,
            .name = try self.allocator.dupe(u8, config.name),
            .template = try self.allocator.dupe(u8, "download"),
            .arch = try self.allocator.dupe(u8, "amd64"),
            .dist = try self.allocator.dupe(u8, "ubuntu"),
            .release = try self.allocator.dupe(u8, "focal"),
        };

        // Convert network configuration
        if (config.network) |net| {
            lxc_config.network = lxc_types.LxcNetworkConfig{
                .allocator = self.allocator,
                .type = try self.allocator.dupe(u8, "veth"),
            };

            if (net.bridge) |bridge| {
                lxc_config.network.?.link = try self.allocator.dupe(u8, bridge);
            }
            if (net.ip) |ip| {
                lxc_config.network.?.ipv4 = try self.allocator.dupe(u8, ip);
            }
        }

        // Convert storage configuration
        if (config.storage) |stor| {
            lxc_config.storage = lxc_types.LxcStorageConfig{
                .allocator = self.allocator,
                .type = try self.allocator.dupe(u8, "dir"),
            };

            if (stor.rootfs) |rootfs| {
                lxc_config.storage.?.source = try self.allocator.dupe(u8, rootfs);
            }
        }

        // Convert security configuration
        if (config.security) |sec| {
            lxc_config.security = lxc_types.LxcSecurityConfig{
                .allocator = self.allocator,
            };

            if (sec.capabilities) |caps| {
                lxc_config.security.?.capabilities = caps;
            }
        }

        // Convert resource limits
        if (config.resources) |res| {
            lxc_config.resources = lxc_types.LxcResourceConfig{
                .allocator = self.allocator,
            };

            if (res.memory) |mem| {
                lxc_config.resources.?.memory = mem;
            }
            if (res.cpu) |cpu| {
                lxc_config.resources.?.cpu_shares = @intFromFloat(cpu * 1024);
            }
        }

        return lxc_config;
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
            else => 255,
        };

        return CommandResult{
            .stdout = res.stdout,
            .stderr = res.stderr,
            .exit_code = exit_code,
        };
    }
};

/// LXC backend interface implementation
pub const LxcBackend = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    driver: *LxcDriver,

    pub fn init(allocator: std.mem.Allocator, config: types.SandboxConfig) !*Self {
        const backend = try allocator.create(Self);
        backend.* = Self{
            .allocator = allocator,
            .driver = try LxcDriver.init(allocator, config),
        };
        return backend;
    }

    pub fn deinit(self: *Self) void {
        self.driver.deinit();
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self, config: types.SandboxConfig) !void {
        try self.driver.create(config);
    }

    pub fn start(self: *Self, container_id: []const u8) !void {
        try self.driver.start(container_id);
    }

    pub fn stop(self: *Self, container_id: []const u8) !void {
        try self.driver.stop(container_id);
    }

    pub fn delete(self: *Self, container_id: []const u8) !void {
        try self.driver.delete(container_id);
    }

    pub fn list(self: *Self, allocator: std.mem.Allocator) ![]interfaces.ContainerInfo {
        return try self.driver.list(allocator);
    }

    pub fn info(self: *Self, container_id: []const u8, allocator: std.mem.Allocator) !interfaces.ContainerInfo {
        return try self.driver.info(container_id, allocator);
    }

    pub fn exec(self: *Self, container_id: []const u8, command: []const []const u8, allocator: std.mem.Allocator) !void {
        try self.driver.exec(container_id, command, allocator);
    }
};

/// Command execution result
pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};
