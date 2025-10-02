const std = @import("std");
const types = @import("types");
const logger_mod = @import("logger");
const error_mod = @import("error");
const Error = error_mod.Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ChildProcess = std.process.Child;
const json = std.json;
const fmt = std.fmt;

/// PCT CLI client for Proxmox LXC operations
pub const PCTClient = struct {
    allocator: Allocator,
    pct_path: []const u8,
    node: []const u8,
    logger: *logger_mod.Logger,
    timeout: u64 = 30_000, // 30 seconds default timeout

    pub fn init(allocator: Allocator, pct_path: []const u8, node: []const u8, logger: *logger_mod.Logger) !PCTClient {
        // Check if PCT CLI is available
        if (!try isPCTAvailable(allocator, pct_path)) {
            try logger.err("PCT CLI not available at path: {s}", .{pct_path});
            return Error.PCTNotAvailable;
        }

        const pct_path_copy = try allocator.dupe(u8, pct_path);
        errdefer allocator.free(pct_path_copy);

        const node_copy = try allocator.dupe(u8, node);
        errdefer allocator.free(node_copy);

        try logger.info("PCTClient initialized with PCT path: {s}, node: {s}", .{ pct_path, node });

        return PCTClient{
            .allocator = allocator,
            .pct_path = pct_path_copy,
            .node = node_copy,
            .logger = logger,
        };
    }

    pub fn deinit(self: *PCTClient) void {
        self.allocator.free(self.pct_path);
        self.allocator.free(self.node);
    }

    /// Check if PCT CLI is available at the specified path
    fn isPCTAvailable(allocator: Allocator, pct_path: []const u8) !bool {
        const result = ChildProcess.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ pct_path, "--version" },
        }) catch return false;
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }
        return result.term.Exited == 0;
    }

    /// Execute a PCT CLI command and return the result
    fn executeCommand(self: *PCTClient, args: []const []const u8) !struct {
        stdout: []u8,
        stderr: []u8,
        exit_code: u8,
    } {
        try self.logger.debug("Executing PCT command: {s}", .{std.mem.join(self.allocator, " ", args) catch "error"});

        const result = ChildProcess.run(.{
            .allocator = self.allocator,
            .argv = args,
        }) catch |err| {
            try self.logger.err("Failed to execute PCT command: {s}", .{@errorName(err)});
            return err;
        };

        const exit_code = switch (result.term) {
            .Exited => |code| @as(u8, @intCast(code)),
            .Signal => |sig| {
                try self.logger.err("PCT command terminated by signal: {d}", .{sig});
                return Error.PCTCommandFailed;
            },
            .Stopped => |sig| {
                try self.logger.err("PCT command stopped by signal: {d}", .{sig});
                return Error.PCTCommandFailed;
            },
            .Unknown => {
                try self.logger.err("PCT command terminated with unknown status", .{});
                return Error.PCTCommandFailed;
            },
        };

        if (exit_code != 0) {
            try self.logger.err("PCT command failed with exit code {d}: {s}", .{ exit_code, result.stderr });
        }

        return .{
            .stdout = result.stdout,
            .stderr = result.stderr,
            .exit_code = exit_code,
        };
    }

    /// Create a new LXC container
    pub fn createContainer(self: *PCTClient, vmid: u32, config: types.LXCConfig) !void {
        try self.logger.info("Creating LXC container with VMID: {d}", .{vmid});

        var args = ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(self.pct_path);
        try args.append("create");
        
        const vmid_str = try fmt.allocPrint(self.allocator, "{d}", .{vmid});
        defer self.allocator.free(vmid_str);
        try args.append(vmid_str);

        // Add template
        if (config.ostemplate) |template| {
            try args.append(template);
        } else {
            try args.append("local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.gz");
        }

        // Add configuration options
        try args.append("--hostname");
        try args.append(config.hostname);

        try args.append("--memory");
        const memory_str = try fmt.allocPrint(self.allocator, "{d}", .{config.memory});
        defer self.allocator.free(memory_str);
        try args.append(memory_str);

        try args.append("--cores");
        const cores_str = try fmt.allocPrint(self.allocator, "{d}", .{config.cores});
        defer self.allocator.free(cores_str);
        try args.append(cores_str);

        try args.append("--rootfs");
        try args.append(config.rootfs);

        if (config.unprivileged) {
            try args.append("--unprivileged");
        }

        if (config.onboot) {
            try args.append("--onboot");
        }

        const result = try self.executeCommand(args.items);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to create container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        try self.logger.info("Successfully created container {d}", .{vmid});
    }

    /// Start an LXC container
    pub fn startContainer(self: *PCTClient, vmid: u32) !void {
        try self.logger.info("Starting LXC container: {d}", .{vmid});

        const args = [_][]const u8{
            self.pct_path,
            "start",
            try fmt.allocPrint(self.allocator, "{d}", .{vmid}),
        };
        defer self.allocator.free(args[2]);

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to start container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        try self.logger.info("Successfully started container {d}", .{vmid});
    }

    /// Stop an LXC container
    pub fn stopContainer(self: *PCTClient, vmid: u32) !void {
        try self.logger.info("Stopping LXC container: {d}", .{vmid});

        const args = [_][]const u8{
            self.pct_path,
            "stop",
            try fmt.allocPrint(self.allocator, "{d}", .{vmid}),
        };
        defer self.allocator.free(args[2]);

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to stop container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        try self.logger.info("Successfully stopped container {d}", .{vmid});
    }

    /// Delete an LXC container
    pub fn deleteContainer(self: *PCTClient, vmid: u32) !void {
        try self.logger.info("Deleting LXC container: {d}", .{vmid});

        const args = [_][]const u8{
            self.pct_path,
            "destroy",
            try fmt.allocPrint(self.allocator, "{d}", .{vmid}),
        };
        defer self.allocator.free(args[2]);

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to delete container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        try self.logger.info("Successfully deleted container {d}", .{vmid});
    }

    /// List all LXC containers
    pub fn listContainers(self: *PCTClient) ![]types.LXCContainer {
        try self.logger.info("Listing LXC containers", .{});

        const args = [_][]const u8{
            self.pct_path,
            "list",
            "--output-format", "json",
        };

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to list containers: {s}", .{result.stderr});
            return Error.PCTOperationFailed;
        }

        return try self.parseContainerList(result.stdout);
    }

    /// Get container status
    pub fn getContainerStatus(self: *PCTClient, vmid: u32) !types.LXCStatus {
        try self.logger.debug("Getting status for container: {d}", .{vmid});

        const args = [_][]const u8{
            self.pct_path,
            "status",
            try fmt.allocPrint(self.allocator, "{d}", .{vmid}),
        };
        defer self.allocator.free(args[2]);

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to get status for container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        return try self.parseContainerStatus(result.stdout);
    }

    /// Get container configuration
    pub fn getContainerConfig(self: *PCTClient, vmid: u32) !types.LXCConfig {
        try self.logger.debug("Getting configuration for container: {d}", .{vmid});

        const args = [_][]const u8{
            self.pct_path,
            "config",
            try fmt.allocPrint(self.allocator, "{d}", .{vmid}),
        };
        defer self.allocator.free(args[2]);

        const result = try self.executeCommand(&args);
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.exit_code != 0) {
            try self.logger.err("Failed to get config for container {d}: {s}", .{ vmid, result.stderr });
            return Error.PCTOperationFailed;
        }

        return try self.parseContainerConfig(result.stdout);
    }

    /// Parse container list from JSON output
    fn parseContainerList(self: *PCTClient, json_output: []const u8) ![]types.LXCContainer {
        var parsed = try json.parseFromSlice(json.Value, self.allocator, json_output, .{});
        defer parsed.deinit();

        if (parsed.value != .array) {
            try self.logger.err("Invalid JSON format for container list", .{});
            return Error.ProxmoxInvalidResponse;
        }

        var containers = ArrayList(types.LXCContainer).init(self.allocator);
        errdefer {
            for (containers.items) |*container| {
                container.deinit(self.allocator);
            }
            containers.deinit();
        }

        for (parsed.value.array.items) |container_obj| {
            if (container_obj != .object) continue;

            const obj = container_obj.object;
            const vmid = @as(u32, @intCast(obj.get("vmid").?.integer));
            const name = obj.get("name").?.string;
            const status_str = obj.get("status").?.string;

            const container = types.LXCContainer{
                .vmid = vmid,
                .name = try self.allocator.dupe(u8, name),
                .status = try self.parseStatusString(status_str),
                .config = try self.getContainerConfig(vmid),
            };

            try containers.append(container);
        }

        return try containers.toOwnedSlice();
    }

    /// Parse container status from string
    fn parseContainerStatus(self: *PCTClient, status_output: []const u8) !types.LXCStatus {
        // PCT status output is typically a single line with status information
        // We need to extract the status from the output
        var lines = std.mem.splitScalar(u8, status_output, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "status")) |status_pos| {
                const status_part = line[status_pos..];
                var parts = std.mem.splitScalar(u8, status_part, ' ');
                if (parts.next()) |_| { // Skip "status"
                    if (parts.next()) |status_str| {
                        return self.parseStatusString(status_str);
                    }
                }
            }
        }

        try self.logger.warn("Could not parse status from output: {s}", .{status_output});
        return types.LXCStatus.unknown;
    }

    /// Parse status string to ContainerStatus enum
    fn parseStatusString(_: *PCTClient, status_str: []const u8) !types.LXCStatus {
        if (std.mem.eql(u8, status_str, "running")) {
            return types.LXCStatus.running;
        } else if (std.mem.eql(u8, status_str, "stopped")) {
            return types.LXCStatus.stopped;
        } else if (std.mem.eql(u8, status_str, "paused")) {
            return types.LXCStatus.paused;
        } else {
            return types.LXCStatus.unknown;
        }
    }

    /// Parse container configuration from PCT config output
    fn parseContainerConfig(self: *PCTClient, config_output: []const u8) !types.LXCConfig {
        // PCT config output is in key=value format
        var config = types.LXCConfig{
            .hostname = try self.allocator.dupe(u8, "unknown"),
            .ostype = try self.allocator.dupe(u8, "ubuntu"),
            .memory = 512,
            .swap = 0,
            .cores = 1,
            .rootfs = try self.allocator.dupe(u8, "local-lvm:8"),
            .net0 = types.NetworkConfig{
                .name = try self.allocator.dupe(u8, "eth0"),
                .bridge = try self.allocator.dupe(u8, "vmbr0"),
                .ip = try self.allocator.dupe(u8, "dhcp"),
                .allocator = self.allocator,
            },
            .onboot = false,
            .protection = false,
            .start = true,
            .template = false,
            .unprivileged = true,
            .features = .{},
        };

        var lines = std.mem.splitScalar(u8, config_output, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = std.mem.trim(u8, line[0..eq_pos], " \t");
                const value = std.mem.trim(u8, line[eq_pos + 1..], " \t");

                if (std.mem.eql(u8, key, "hostname")) {
                    self.allocator.free(config.hostname);
                    config.hostname = try self.allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "memory")) {
                    config.memory = std.fmt.parseInt(u32, value, 10) catch 512;
                } else if (std.mem.eql(u8, key, "cores")) {
                    config.cores = std.fmt.parseInt(u32, value, 10) catch 1;
                } else if (std.mem.eql(u8, key, "rootfs")) {
                    self.allocator.free(config.rootfs);
                    config.rootfs = try self.allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "onboot")) {
                    config.onboot = std.mem.eql(u8, value, "1");
                } else if (std.mem.eql(u8, key, "unprivileged")) {
                    config.unprivileged = std.mem.eql(u8, value, "1");
                }
            }
        }

        return config;
    }
};
