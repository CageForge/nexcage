const std = @import("std");
const core = @import("core");
const common = @import("common.zig");

/// One data row of `pct list`. Slices borrow from the command output.
pub const PctListEntry = struct {
    vmid: []const u8,
    status: []const u8,
    lock: []const u8,
    name: []const u8,
};

/// Parses one line of `pct list`; returns null for the header and blank lines.
///
/// pct prints `"%-10s %-10s %-12s %-20s\n"` for VMID, Status, Lock and Name,
/// and Lock is an empty string unless the container is locked. Splitting on
/// whitespace gives three fields normally and four while a lock is held. The
/// fixed column offsets used before broke as soon as a value outgrew its
/// column (the "snapshot-delete" lock is 15 characters), and whitespace
/// tokenising without that rule read the lock as the name. Hostnames cannot
/// contain whitespace, so the name is always the last field.
pub fn parsePctListLine(line: []const u8) ?PctListEntry {
    var fields: [4][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |field| {
        if (count == fields.len) return null;
        fields[count] = field;
        count += 1;
    }
    if (count < 2) return null;
    // The header ("VMID Status Lock Name") and anything else without a numeric id
    _ = std.fmt.parseInt(u32, fields[0], 10) catch return null;

    return switch (count) {
        2 => .{ .vmid = fields[0], .status = fields[1], .lock = "", .name = "" },
        3 => .{ .vmid = fields[0], .status = fields[1], .lock = "", .name = fields[2] },
        else => .{ .vmid = fields[0], .status = fields[1], .lock = fields[2], .name = fields[3] },
    };
}

/// Returns the VMID of the container named `name` in `pct list` output,
/// borrowing from `output`.
pub fn findVmidByName(output: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const entry = parsePctListLine(line) orelse continue;
        if (std.mem.eql(u8, entry.name, name)) return entry.vmid;
    }
    return null;
}

pub const PveVersion = struct {
    major: u32,
    minor: u32,
};

/// Reads the Proxmox VE major.minor version from `pveversion -v` output, or
/// from the single `pve-manager/X.Y.Z/...` line plain `pveversion` prints.
pub fn parsePveVersion(output: []const u8) ?PveVersion {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const rest = if (std.mem.startsWith(u8, line, "proxmox-ve:"))
            std.mem.trimLeft(u8, line["proxmox-ve:".len..], " \t")
        else if (std.mem.indexOf(u8, line, "pve-manager/")) |i|
            line[i + "pve-manager/".len ..]
        else
            continue;
        if (parseMajorMinor(rest)) |version| return version;
    }
    return null;
}

/// "9.1.0 (running kernel: ...)", "8.4.1/2a5fa54a" or "9.0-3" -> major, minor
fn parseMajorMinor(text: []const u8) ?PveVersion {
    const end = std.mem.indexOfAny(u8, text, " /(") orelse text.len;
    var parts = std.mem.tokenizeAny(u8, text[0..end], ".-");
    const major = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    const minor = std.fmt.parseInt(u32, parts.next() orelse return null, 10) catch return null;
    return .{ .major = major, .minor = minor };
}

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

        const version = parsePveVersion(res.stdout) orelse return null;
        return try std.fmt.allocPrint(self.allocator, "{d}.{d}", .{ version.major, version.minor });
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

    /// Ask the cluster for the next free VMID.
    ///
    /// This replaces a hash of the container name, which could land on a VMID
    /// already used by a VM (only `pct list` was checked) or by a container on
    /// another node. Names still resolve through `pct list`, so nothing relied
    /// on the VMID being derivable from the name.
    pub fn nextVmid(self: *const Self) ![]u8 {
        const args = [_][]const u8{ "pvesh", "get", "/cluster/nextid" };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) {
            if (self.logger) |log| log.err("pvesh get /cluster/nextid failed: {s}", .{std.mem.trim(u8, res.stderr, " \t\r\n")}) catch {};
            return core.Error.OperationFailed;
        }

        const vmid = std.mem.trim(u8, res.stdout, " \t\r\n\"");
        _ = std.fmt.parseInt(u32, vmid, 10) catch {
            if (self.logger) |log| log.err("Unexpected VMID from pvesh: '{s}'", .{vmid}) catch {};
            return core.Error.OperationFailed;
        };
        return try self.allocator.dupe(u8, vmid);
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
        while (lines.next()) |line| {
            const entry = parsePctListLine(line) orelse continue;
            if (std.mem.eql(u8, entry.vmid, vmid)) return true;
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
        // A failing `pct list` is not "no such container": create would read
        // that as the name being free.
        if (res.exit_code != 0) return self.mapPctError(res.stderr);

        const vmid = findVmidByName(res.stdout, name) orelse return core.Error.NotFound;
        return try self.allocator.dupe(u8, vmid);
    }

    /// Map pct command errors to core errors
    pub fn mapPctError(self: *const Self, stderr: []const u8) core.Error {
        const s = stderr;
        if (self.logger) |log| log.err("pct command failed: {s}", .{std.mem.trim(u8, stderr, " \t\r\n")}) catch {};

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
        if (res.exit_code != 0) return self.mapPctError(res.stderr);

        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        var containers = std.ArrayListUnmanaged(core.ContainerInfo){};
        errdefer {
            for (containers.items) |*c| c.deinit();
            containers.deinit(self.allocator);
        }

        while (lines.next()) |line| {
            const entry = parsePctListLine(line) orelse continue;
            try containers.append(self.allocator, core.ContainerInfo{
                .allocator = allocator,
                .id = try allocator.dupe(u8, entry.vmid),
                .name = try allocator.dupe(u8, entry.name),
                .status = try allocator.dupe(u8, entry.status),
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

    /// Stop container: a clean shutdown, forced once the timeout expires.
    /// `pct stop` kills every process at once, which is what `kill` is for.
    pub fn stop(self: *const Self, vmid: []const u8) !void {
        const args = [_][]const u8{ "pct", "shutdown", vmid, "--timeout", "60", "--forceStop", "1" };
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

/// Formats a row exactly as pct does: printf "%-10s %-10s %-12s %-20s\n".
fn pctRow(buf: []u8, vmid: []const u8, status: []const u8, lock: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s: <10} {s: <10} {s: <12} {s: <20}", .{ vmid, status, lock, name });
}

test "parsePctListLine reads an unlocked container" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "101", "running", "", "web-1")).?;
    try std.testing.expectEqualStrings("101", entry.vmid);
    try std.testing.expectEqualStrings("running", entry.status);
    try std.testing.expectEqualStrings("", entry.lock);
    try std.testing.expectEqualStrings("web-1", entry.name);
}

test "parsePctListLine does not read a lock as the name" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "102", "stopped", "backup", "db-1")).?;
    try std.testing.expectEqualStrings("backup", entry.lock);
    try std.testing.expectEqualStrings("db-1", entry.name);
}

test "parsePctListLine survives a lock wider than its column" {
    var buf: [128]u8 = undefined;
    const entry = parsePctListLine(try pctRow(&buf, "103", "stopped", "snapshot-delete", "cache-1")).?;
    try std.testing.expectEqualStrings("103", entry.vmid);
    try std.testing.expectEqualStrings("snapshot-delete", entry.lock);
    try std.testing.expectEqualStrings("cache-1", entry.name);
}

test "parsePctListLine skips the header and blank lines" {
    var buf: [128]u8 = undefined;
    try std.testing.expect(parsePctListLine(try pctRow(&buf, "VMID", "Status", "Lock", "Name")) == null);
    try std.testing.expect(parsePctListLine("") == null);
    try std.testing.expect(parsePctListLine("   \r") == null);
}

test "findVmidByName matches whole names only" {
    const output =
        \\VMID       Status     Lock         Name
        \\101        running                 web-1
        \\102        stopped    backup       web-10
        \\1000       stopped                 db
        \\
    ;
    try std.testing.expectEqualStrings("101", findVmidByName(output, "web-1").?);
    try std.testing.expectEqualStrings("102", findVmidByName(output, "web-10").?);
    try std.testing.expectEqualStrings("1000", findVmidByName(output, "db").?);
    try std.testing.expect(findVmidByName(output, "web") == null);
    try std.testing.expect(findVmidByName(output, "backup") == null);
}

test "parsePveVersion reads the proxmox-ve line of pveversion -v" {
    const version = parsePveVersion(
        \\proxmox-ve: 9.1.0 (running kernel: 6.14.8-2-pve)
        \\pve-manager: 9.1.1 (running version: 9.1.1/42db4a6cf33dac83)
        \\proxmox-kernel-helper: 9.0.4
    ).?;
    try std.testing.expectEqual(@as(u32, 9), version.major);
    try std.testing.expectEqual(@as(u32, 1), version.minor);
}

test "parsePveVersion reads the pve-manager/ form" {
    // The previous parser cut this line at the first '-' (inside the kernel
    // version) and returned "8.4.1/2a5fa54a8503f96d (running kernel: 6.8.12"
    // as the version, which then failed to parse as a number.
    const version = parsePveVersion("pve-manager/8.4.1/2a5fa54a8503f96d (running kernel: 6.8.12-9-pve)").?;
    try std.testing.expectEqual(@as(u32, 8), version.major);
    try std.testing.expectEqual(@as(u32, 4), version.minor);
}

test "parsePveVersion handles a release suffix and rejects the rest" {
    const version = parsePveVersion("proxmox-ve: 9.0-3").?;
    try std.testing.expectEqual(@as(u32, 9), version.major);
    try std.testing.expectEqual(@as(u32, 0), version.minor);

    try std.testing.expect(parsePveVersion("") == null);
    try std.testing.expect(parsePveVersion("proxmox-ve: unknown") == null);
    try std.testing.expect(parsePveVersion("pve-manager: 9.1.1") == null);
}
