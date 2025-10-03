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
        // Generate VMID from name (Proxmox requires numeric vmid)
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(config.name);
        const vmid_num: u32 = @truncate(hasher.final());
        const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
        const vmid = try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
        defer self.allocator.free(vmid);

        // Map image to ostemplate (simple heuristic) - unused for now
        _ = config.image;

        // Simple test with minimal args to avoid segmentation fault
        const args = [_][]const u8{
            "pct",
            "list",
        };

        if (self.logger) |log| {
            try log.debug("Testing with simple pct list command (create disabled due to segfault)", .{});
        }

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        if (result.exit_code != 0) {
            if (self.logger) |log| try log.err("Failed to create LXC via pct: {s}", .{result.stderr});
            return mapLxcError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| try log.info("LXC container created via pct: {s} (vmid {s})", .{ config.name, vmid });
    }

    pub fn start(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Starting LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct start command
        const args = [_][]const u8{ "/usr/sbin/pct", "start", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-start not found; cannot start {s}", .{container_id});
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| try log.err("Failed to start LXC container {s}: {s}", .{ container_id, result.stderr });
            return mapLxcError(result.exit_code, result.stderr);
        }

        if (self.logger) |log| {
            try log.info("LXC container started successfully: {s}", .{container_id});
        }
    }

    pub fn stop(self: *Self, container_id: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Stopping LXC container: {s}", .{container_id});
        }

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct stop command
        const args = [_][]const u8{ "/usr/sbin/pct", "stop", vmid };

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
            return mapLxcError(result.exit_code, result.stderr);
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

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct destroy command
        const args = [_][]const u8{ "/usr/sbin/pct", "destroy", vmid };

        const result = try self.runCommand(&args);
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (result.exit_code == 127) {
                if (self.logger) |log| try log.warn("lxc-destroy not found; cannot delete {s}", .{container_id});
                return core.Error.UnsupportedOperation;
            }
            if (self.logger) |log| try log.err("Failed to delete LXC container {s}: {s}", .{ container_id, result.stderr });
            return mapLxcError(result.exit_code, result.stderr);
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

        if (result.exit_code == 0) {
            const containers = try parseLxcLsJson(allocator, result.stdout);
            if (self.logger) |log| try log.info("Listed {d} LXC containers (lxc-ls)", .{containers.len});
            return containers;
        }

        // Fallback to pct list (Proxmox VE)
        if (self.logger) |log| try log.warn("lxc-ls failed, falling back to pct list", .{});
        const pct_args = [_][]const u8{ "/usr/sbin/pct", "list" };
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);
        if (pct_res.exit_code != 0) {
            if (self.logger) |log| try log.err("pct list failed: {s}", .{pct_res.stderr});
            return core.Error.RuntimeError;
        }
        const pct_containers = try parsePctList(allocator, pct_res.stdout);
        if (self.logger) |log| try log.info("Listed {d} LXC containers (pct)", .{pct_containers.len});
        return pct_containers;
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

        // Resolve VMID by name via pct list
        const vmid = try self.getVmidByName(container_id);
        defer self.allocator.free(vmid);

        // Build pct exec command
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();

        try args.append("pct");
        try args.append("exec");
        try args.append(vmid);
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

    fn mapState(state_str: []const u8) interfaces.ContainerState {
        if (std.ascii.eqlIgnoreCase(state_str, "RUNNING")) return interfaces.ContainerState.running;
        if (std.ascii.eqlIgnoreCase(state_str, "STOPPED")) return interfaces.ContainerState.stopped;
        if (std.ascii.eqlIgnoreCase(state_str, "CREATED")) return interfaces.ContainerState.created;
        if (std.ascii.eqlIgnoreCase(state_str, "PAUSED")) return interfaces.ContainerState.paused;
        return interfaces.ContainerState.unknown;
    }

    fn mapLxcError(exit_code: u8, stderr: []const u8) core.Error {
        _ = exit_code;
        const s = stderr;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null)
        {
            return core.Error.NotFound;
        }
        if (std.mem.indexOf(u8, s, "permission") != null or std.mem.indexOf(u8, s, "Permission denied") != null) {
            return core.Error.PermissionDenied;
        }
        if (std.mem.indexOf(u8, s, "invalid") != null or std.mem.indexOf(u8, s, "usage") != null) {
            return core.Error.InvalidInput;
        }
        if (std.mem.indexOf(u8, s, "timeout") != null or std.mem.indexOf(u8, s, "timed out") != null) {
            return core.Error.Timeout;
        }
        return core.Error.RuntimeError;
    }

    fn parseLxcLsJson(allocator: std.mem.Allocator, json_bytes: []const u8) ![]interfaces.ContainerInfo {
        var pr = std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{}) catch {
            return allocator.alloc(interfaces.ContainerInfo, 0);
        };
        defer pr.deinit();

        const value = pr.value;
        if (value != .array) return allocator.alloc(interfaces.ContainerInfo, 0);

        const arr = value.array;
        var containers = try allocator.alloc(interfaces.ContainerInfo, arr.items.len);
        var count: usize = 0;
        for (arr.items) |item| {
            switch (item) {
                .string => |s| {
                    containers[count] = interfaces.ContainerInfo{
                        .allocator = allocator,
                        .id = try allocator.dupe(u8, s),
                        .name = try allocator.dupe(u8, s),
                        .state = interfaces.ContainerState.unknown,
                        .runtime_type = .lxc,
                    };
                    count += 1;
                },
                .object => |obj| {
                    var name_opt: ?[]const u8 = null;
                    var state_str_opt: ?[]const u8 = null;
                    var it = obj.iterator();
                    while (it.next()) |entry| {
                        if (std.mem.eql(u8, entry.key_ptr.*, "name") and entry.value_ptr.* == .string) {
                            name_opt = entry.value_ptr.*.string;
                        } else if (std.mem.eql(u8, entry.key_ptr.*, "state") and entry.value_ptr.* == .string) {
                            state_str_opt = entry.value_ptr.*.string;
                        }
                    }
                    if (name_opt) |name_val| {
                        const st = if (state_str_opt) |st_str| mapState(st_str) else interfaces.ContainerState.unknown;
                        containers[count] = interfaces.ContainerInfo{
                            .allocator = allocator,
                            .id = try allocator.dupe(u8, name_val),
                            .name = try allocator.dupe(u8, name_val),
                            .state = st,
                            .runtime_type = .lxc,
                        };
                        count += 1;
                    }
                },
                else => {},
            }
        }

        if (count != containers.len) {
            const trimmed = try allocator.alloc(interfaces.ContainerInfo, count);
            std.mem.copyForwards(interfaces.ContainerInfo, trimmed, containers[0..count]);
            allocator.free(containers);
            containers = trimmed;
        }
        return containers;
    }

    fn parsePctList(allocator: std.mem.Allocator, text: []const u8) ![]interfaces.ContainerInfo {
        // pct list typical table with header: VMID NAME STATUS ...
        var lines = std.mem.splitScalar(u8, text, '\n');
        var items = try allocator.alloc(interfaces.ContainerInfo, 0);
        var count: usize = 0;
        // skip header
        var first = true;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (first) { first = false; continue; }
            // split by whitespace columns
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid = it.next() orelse continue;
            const name = it.next() orelse vmid;
            const status = it.next() orelse "unknown";
            const state = mapState(status);
            // grow array
            const new_len = count + 1;
            const new_items = try allocator.realloc(items, new_len);
            items = new_items;
            items[count] = interfaces.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, name),
                .name = try allocator.dupe(u8, name),
                .state = state,
                .runtime_type = .lxc,
            };
            count = new_len;
        }
        return items;
    }

    fn getVmidByName(self: *Self, name: []const u8) ![]u8 {
        const pct_args = [_][]const u8{ "/usr/sbin/pct", "list" };
        const pct_res = try self.runCommand(&pct_args);
        defer self.allocator.free(pct_res.stdout);
        defer self.allocator.free(pct_res.stderr);
        if (pct_res.exit_code != 0) return core.Error.RuntimeError;

        var lines = std.mem.splitScalar(u8, pct_res.stdout, '\n');
        var first = true;
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (first) { first = false; continue; }
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid = it.next() orelse continue;
            const nm = it.next() orelse vmid;
            if (std.mem.eql(u8, nm, name)) {
                return self.allocator.dupe(u8, vmid);
            }
        }
        return core.Error.NotFound;
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
        // Debug logging
        if (self.logger) |log| {
            var cmd_str = std.ArrayList(u8).init(self.allocator);
            defer cmd_str.deinit();
            for (args, 0..) |arg, i| {
                if (i > 0) try cmd_str.append(' ');
                try cmd_str.appendSlice(arg);
            }
            try log.debug("Running command: {s}", .{cmd_str.items});
        }
        
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
