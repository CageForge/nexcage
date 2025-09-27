const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const utils = @import("utils");

/// Crun backend driver
/// Crun backend driver
pub const CrunDriver = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: types.CrunBackendConfig,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator, config: types.CrunBackendConfig) !*Self {
        const driver = try allocator.alloc(Self, 1);
        driver[0] = Self{
            .allocator = allocator,
            .config = config,
        };

        return &driver[0];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Create container
    pub fn createContainer(self: *Self, config: types.OciContainerConfig) !void {
        if (self.logger) |log| {
            try log.info("Creating OCI container '{s}' with image '{s}'", .{ config.name, config.image });
        }

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.crun_path);
        try args.append("create");

        if (self.config.debug) {
            try args.append("--debug");
        }

        if (self.config.log_level) |level| {
            try args.append("--log-level");
            try args.append(level);
        }

        if (self.config.runtime_path) |path| {
            try args.append("--runtime-path");
            try args.append(path);
        }

        if (self.config.root_path) |path| {
            try args.append("--root");
            try args.append(path);
        }

        // Add container name
        try args.append("--name");
        try args.append(config.name);

        // Add image
        try args.append(config.image);

        // Add command if specified
        if (config.command) |cmd| {
            try args.append(cmd);
        }

        // Add arguments if specified
        if (config.args) |container_args| {
            for (container_args) |arg| {
                try args.append(arg);
            }
        }

        const result = try utils.fs.runCommand(self.allocator, args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to create container: {s}", .{result.stderr});
            }
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("Successfully created container '{s}'", .{config.name});
        }
    }

    /// Start container
    pub fn startContainer(self: *Self, name: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting container '{s}'", .{name});
        }

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.crun_path);
        try args.append("start");
        try args.append(name);

        const result = try utils.fs.runCommand(self.allocator, args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to start container: {s}", .{result.stderr});
            }
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("Successfully started container '{s}'", .{name});
        }
    }

    /// Stop container
    pub fn stopContainer(self: *Self, name: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping container '{s}'", .{name});
        }

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.crun_path);
        try args.append("kill");
        try args.append(name);
        try args.append("TERM");

        const result = try utils.fs.runCommand(self.allocator, args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to stop container: {s}", .{result.stderr});
            }
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("Successfully stopped container '{s}'", .{name});
        }
    }

    /// Delete container
    pub fn deleteContainer(self: *Self, name: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Deleting container '{s}'", .{name});
        }

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.crun_path);
        try args.append("delete");
        try args.append(name);

        const result = try utils.fs.runCommand(self.allocator, args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to delete container: {s}", .{result.stderr});
            }
            return core.Error.RuntimeError;
        }

        if (self.logger) |log| {
            try log.info("Successfully deleted container '{s}'", .{name});
        }
    }

    /// List containers
    pub fn listContainers(self: *Self) ![]types.ContainerInfo {
        if (self.logger) |log| {
            try log.info("Listing OCI containers");
        }

        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.config.crun_path);
        try args.append("list");
        try args.append("--format");
        try args.append("json");

        const result = try utils.fs.runCommand(self.allocator, args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to list containers: {s}", .{result.stderr});
            }
            return core.Error.RuntimeError;
        }

        // Parse JSON output
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, result.stdout, .{}) catch |err| {
            if (self.logger) |log| {
                try log.@"error"("Failed to parse container list JSON: {s}", .{@errorName(err)});
            }
            return err;
        };
        defer parsed.deinit();

        if (parsed.value.array) |containers| {
            var result_list = try self.allocator.alloc(types.ContainerInfo, containers.items.len);

            for (containers.items, 0..) |container_value, i| {
                if (container_value.object) |container_obj| {
                    result_list[i] = types.ContainerInfo{
                        .allocator = self.allocator,
                        .id = try self.allocator.dupe(u8, container_obj.get("id").?.string.?),
                        .name = try self.allocator.dupe(u8, container_obj.get("name").?.string.?),
                        .image = try self.allocator.dupe(u8, container_obj.get("image").?.string.?),
                        .status = parseContainerStatus(container_obj.get("status").?.string.?),
                        .created = container_obj.get("created").?.integer.?,
                        .started_at = if (container_obj.get("started_at")) |started| @intCast(started.integer.?) else null,
                        .finished_at = if (container_obj.get("finished_at")) |finished| @intCast(finished.integer.?) else null,
                        .exit_code = if (container_obj.get("exit_code")) |exit| @intCast(exit.integer.?) else null,
                        .pid = if (container_obj.get("pid")) |p| @intCast(p.integer.?) else null,
                        .ip_address = null, // TODO: Get IP from container network info
                    };
                }
            }

            if (self.logger) |log| {
                try log.info("Found {d} OCI containers", .{result_list.len});
            }

            return result_list;
        }

        return try self.allocator.alloc(types.ContainerInfo, 0);
    }

    /// Get container information
    pub fn getContainerInfo(self: *Self, name: []const u8) !?types.ContainerInfo {
        const containers = try self.listContainers();
        defer {
            for (containers) |container| {
                container.deinit();
            }
            self.allocator.free(containers);
        }

        for (containers) |container| {
            if (std.mem.eql(u8, container.name, name)) {
                return container;
            }
        }

        return null;
    }

    /// Check if container exists
    pub fn containerExists(self: *Self, name: []const u8) !bool {
        const info = try self.getContainerInfo(name);
        if (info) |container_info| {
            container_info.deinit();
            return true;
        }
        return false;
    }

    /// Parse container status from string
    fn parseContainerStatus(status_str: []const u8) types.ContainerStatus {
        if (std.mem.eql(u8, status_str, "created")) return .created;
        if (std.mem.eql(u8, status_str, "running")) return .running;
        if (std.mem.eql(u8, status_str, "paused")) return .paused;
        if (std.mem.eql(u8, status_str, "restarting")) return .restarting;
        if (std.mem.eql(u8, status_str, "removing")) return .removing;
        if (std.mem.eql(u8, status_str, "exited")) return .exited;
        if (std.mem.eql(u8, status_str, "dead")) return .dead;
        return .unknown;
    }
};
