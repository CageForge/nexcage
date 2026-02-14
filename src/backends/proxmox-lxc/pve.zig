const std = @import("std");
const core = @import("core");
const common = @import("common.zig");

pub const PveClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
        };
    }

    /// Get Proxmox VE version using pveversion command
    pub fn getProxmoxVeVersion(self: *const Self) !?[]const u8 {
        const args = [_][]const u8{ "pveversion", "-v" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return null;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "proxmox-ve:")) {
                var version_part = std.mem.trimLeft(u8, line["proxmox-ve:".len..], " \t");
                const space_idx = std.mem.indexOfScalar(u8, version_part, ' ') orelse version_part.len;
                const version_str = version_part[0..space_idx];
                const dot_idx = std.mem.indexOfScalar(u8, version_str, '.') orelse return null;
                const major = version_str[0..dot_idx];
                const minor_start = dot_idx + 1;
                const next_dot_idx = std.mem.indexOfScalar(u8, version_str[minor_start..], '.');
                const minor_end = if (next_dot_idx) |idx| minor_start + idx else version_str.len;
                const minor = version_str[minor_start..minor_end];

                return try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ major, minor });
            }
            if (std.mem.indexOf(u8, line, "pve-manager/") != null) {
                if (std.mem.indexOfScalar(u8, line, '/')) |slash_idx| {
                    const version_part = line[slash_idx + 1 ..];
                    const dash_idx = std.mem.indexOfScalar(u8, version_part, '-') orelse version_part.len;
                    const version_str = version_part[0..dash_idx];
                    const dot_idx = std.mem.indexOfScalar(u8, version_str, '.') orelse return null;
                    const major = version_str[0..dot_idx];
                    const minor_start = dot_idx + 1;
                    const minor_end = std.mem.indexOfScalar(u8, version_str[minor_start..], '-') orelse version_str.len;
                    const minor = version_str[minor_start..minor_end];

                    return try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ major, minor });
                }
            }
        }
        return null;
    }

    /// Check if Proxmox VE version is >= 9.1 (supports OCI Registry pull)
    pub fn supportsOciRegistryPull(self: *const Self) !bool {
        const version_str = try self.getProxmoxVeVersion();
        if (version_str) |ver| {
            defer self.allocator.free(ver);
            const dot_idx = std.mem.indexOfScalar(u8, ver, '.') orelse return false;
            const major_str = ver[0..dot_idx];
            const minor_str = ver[dot_idx + 1 ..];
            const major = std.fmt.parseInt(u32, major_str, 10) catch return false;
            const minor = std.fmt.parseInt(u32, minor_str, 10) catch return false;
            return major > 9 or (major == 9 and minor >= 1);
        }
        return false;
    }

    /// Get Proxmox node name (hostname)
    pub fn getNodeName(self: *const Self) ![]const u8 {
        const args = [_][]const u8{"hostname"};
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        if (res.exit_code != 0) return error.NodeNameDetectionFailed;
        const node_name = std.mem.trim(u8, res.stdout, " \t\r\n");
        return try self.allocator.dupe(u8, node_name);
    }

    /// Pull OCI image from registry using pvesh command
    pub fn pullOciImage(self: *const Self, image_ref: []const u8, storage: []const u8) ![]const u8 {
        if (self.logger) |log| try log.info("Pulling OCI image from registry: {s}", .{image_ref});

        const node_name = try self.getNodeName();
        defer self.allocator.free(node_name);

        const path = try std.fmt.allocPrint(self.allocator, "/nodes/{s}/storage/{s}/oci-registry-pull", .{ node_name, storage });
        defer self.allocator.free(path);

        const args = [_][]const u8{ "pvesh", "create", path, "--reference", image_ref };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        const template_exists = res.exit_code == 25 and std.mem.indexOf(u8, res.stderr, "refusing to override existing file") != null;
        if (res.exit_code != 0 and !template_exists) {
            if (self.logger) |log| try log.err("Failed to pull OCI image {s}: {s}", .{ image_ref, res.stderr });
            return core.Error.OperationFailed;
        }

        // Extract template name (constructed)
        const colon_idx = std.mem.lastIndexOfScalar(u8, image_ref, ':') orelse image_ref.len;
        const image_part = image_ref[0..colon_idx];
        const tag_part = if (colon_idx < image_ref.len) image_ref[colon_idx + 1 ..] else "latest";
        const slash_idx = std.mem.lastIndexOfScalar(u8, image_part, '/');
        const image_name = if (slash_idx) |idx| image_part[idx + 1 ..] else image_part;

        return try std.fmt.allocPrint(self.allocator, "{s}:vztmpl/{s}_{s}.tar", .{ storage, image_name, tag_part });
    }

    /// Generate numeric VMID from container name
    pub fn generateVmid(self: *const Self, name: []const u8) ![]u8 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(name);
        const vmid_num: u32 = @truncate(hasher.final());
        const vmid_calc: u32 = (vmid_num % 900000) + 100; // 100..900099
        return try std.fmt.allocPrint(self.allocator, "{d}", .{vmid_calc});
    }

    /// Check if VMID already exists in Proxmox
    pub fn vmidExists(self: *const Self, vmid: []const u8) !bool {
        const args = [_][]const u8{ "pct", "list" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return false;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        _ = lines.next(); // Skip header
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len < 10) continue;
            const vmid_str = std.mem.trim(u8, trimmed[0..10], " \t");
            if (std.mem.eql(u8, vmid_str, vmid)) return true;
        }
        return false;
    }

    /// Get VMID by container name
    pub fn getVmidByName(self: *const Self, name: []const u8) ![]u8 {
        const args = [_][]const u8{ "pct", "list" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.NotFound;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        _ = lines.next(); // Skip header
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len < 34) continue;
            const vmid_str = std.mem.trim(u8, trimmed[0..10], " \t");
            const name_str = std.mem.trim(u8, trimmed[33..], " \t");
            if (std.mem.eql(u8, name_str, name)) return try self.allocator.dupe(u8, vmid_str);
        }
        return core.Error.NotFound;
    }

    /// Map pct command errors to core errors
    pub fn mapPctError(self: *const Self, stderr: []const u8) core.Error {
        const s = stderr;
        if (self.logger) |log| log.err("pct command failed: {s}", .{stderr}) catch {};

        if (std.mem.indexOf(u8, s, "already exists") != null) return core.Error.OperationFailed;
        if (std.mem.indexOf(u8, s, "No such file or directory") != null or
            std.mem.indexOf(u8, s, "does not exist") != null or
            std.mem.indexOf(u8, s, "not found") != null) return core.Error.NotFound;
        if (std.mem.indexOf(u8, s, "Permission denied") != null) return core.Error.PermissionDenied;
        if (std.mem.indexOf(u8, s, "timeout") != null) return core.Error.Timeout;

        return core.Error.OperationFailed;
    }

    /// List containers
    pub fn list(self: *const Self, allocator: std.mem.Allocator) ![]core.ContainerInfo {
        const args = [_][]const u8{ "pct", "list" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.OperationFailed;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        errdefer {
            for (containers.items) |*c| c.deinit();
            containers.deinit(self.allocator);
        }

        _ = lines.next(); // Skip header
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
            const vmid_str = it.next() orelse continue;
            const status_str = it.next() orelse "unknown";
            const name_str = it.next() orelse "unknown";

            try containers.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, vmid_str),
                .name = try allocator.dupe(u8, name_str),
                .status = try allocator.dupe(u8, status_str),
                .backend_type = try allocator.dupe(u8, "proxmox-lxc"),
                .runtime = try allocator.dupe(u8, "pct"),
            });
        }
        return try containers.toOwnedSlice(self.allocator);
    }

    /// Start container
    pub fn start(self: *const Self, vmid: []const u8) !void {
        const args = [_][]const u8{ "pct", "start", vmid };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Stop container
    pub fn stop(self: *const Self, vmid: []const u8) !void {
        const args = [_][]const u8{ "pct", "stop", vmid };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Destroy container
    pub fn delete(self: *const Self, vmid: []const u8) !void {
        const args = [_][]const u8{ "pct", "destroy", vmid };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return self.mapPctError(res.stderr);
    }

    /// Get PID 1 inside container
    pub fn getInitPid(self: *const Self, vmid: []const u8) ?i32 {
        const args = [_][]const u8{ "pct", "exec", vmid, "--", "cat", "/proc/1/stat" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return null;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return null;
        const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
        var it = std.mem.splitScalar(u8, trimmed, ' ');
        if (it.next()) |first| {
            return std.fmt.parseInt(i32, first, 10) catch return null;
        }
        return null;
    }

    /// Send signal to container
    pub fn kill(self: *const Self, vmid: []const u8, signal: []const u8) !void {
        // Try multiple ways to send SIG to PID 1 inside container
        const kill_cmds = [_][]const u8{ "kill", "/bin/kill", "/usr/bin/kill" };
        for (kill_cmds) |cmd| {
            const args = [_][]const u8{ "pct", "exec", vmid, "--", cmd, "-s", signal, "1" };
            const res = try common.runCommand(self.allocator, self.logger, &args);
            defer {
                self.allocator.free(res.stdout);
                self.allocator.free(res.stderr);
            }
            if (res.exit_code == 0) return;
        }
        return core.Error.OperationFailed;
    }

    /// Find an available template in Proxmox
    pub fn findAvailableTemplate(self: *const Self) ![]const u8 {
        const args = [_][]const u8{ "pveam", "list", "local" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return core.Error.NotFound;

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.indexOf(u8, trimmed, ".tar.zst") != null) {
                var it = std.mem.splitScalar(u8, trimmed, ' ');
                if (it.next()) |tmpl| {
                    if (std.mem.indexOf(u8, tmpl, ":vztmpl/") != null) {
                        return try self.allocator.dupe(u8, tmpl);
                    }
                    return try std.fmt.allocPrint(self.allocator, "local:vztmpl/{s}", .{tmpl});
                }
            }
        }
        return core.Error.NotFound;
    }
};
