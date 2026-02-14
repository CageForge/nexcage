const std = @import("std");
const core = @import("core");
const common = @import("common.zig");

pub const ZfsManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext,
    pool_config: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, logger: ?*core.LogContext, pool_config: ?[]const u8) Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .pool_config = pool_config,
        };
    }

    /// Check if ZFS is available (via CLI)
    pub fn isZFSAvailable(self: *const Self) bool {
        const args = [_][]const u8{ "zfs", "version" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        return res.exit_code == 0;
    }

    /// Check if ZFS pool exists
    pub fn poolExists(self: *const Self, pool_name: []const u8) bool {
        const args = [_][]const u8{ "zpool", "list", "-H", "-o", "name", pool_name };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        if (res.exit_code != 0) return false;
        var lines = std.mem.splitScalar(u8, res.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (std.mem.eql(u8, trimmed, pool_name)) {
                return true;
            }
        }
        return false;
    }

    /// Check if ZFS dataset exists
    pub fn datasetExists(self: *const Self, dataset_name: []const u8) bool {
        const args = [_][]const u8{ "zfs", "list", "-H", "-o", "name", dataset_name };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        return res.exit_code == 0 and std.mem.indexOf(u8, res.stdout, dataset_name) != null;
    }

    /// Get parent dataset path from full dataset path
    pub fn getParentDataset(_: *const Self, dataset_name: []const u8) ?[]const u8 {
        if (std.mem.lastIndexOf(u8, dataset_name, "/")) |idx| {
            return dataset_name[0..idx];
        }
        return null;
    }

    /// Check minimal ZFS version compatibility (best-effort)
    pub fn isZfsCompatible(self: *const Self, min_major: u32, min_minor: u32) bool {
        const args = [_][]const u8{ "zfs", "version" };
        const res = common.runCommand(self.allocator, self.logger, &args) catch return false;
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }
        if (res.exit_code != 0) return false;
        var it = std.mem.splitScalar(u8, res.stdout, '\n');
        while (it.next()) |line| {
            if (std.mem.indexOf(u8, line, "zfs-") != null) {
                if (std.mem.indexOfScalar(u8, line, '-')) |dash_idx| {
                    const v = line[dash_idx + 1 ..];
                    var dot = std.mem.splitScalar(u8, v, '.');
                    const maj_s = dot.next() orelse continue;
                    const min_s = dot.next() orelse continue;
                    const maj = std.fmt.parseInt(u32, maj_s, 10) catch continue;
                    const min = std.fmt.parseInt(u32, min_s, 10) catch continue;
                    if (maj > min_major or (maj == min_major and min >= min_minor)) return true;
                }
            }
        }
        return false;
    }

    /// Create ZFS dataset for container
    pub fn createContainerDataset(self: *const Self, container_name: []const u8, vmid: []const u8) !?[]const u8 {
        if (!self.isZFSAvailable() or self.pool_config == null) return null;

        const pool_config = self.pool_config.?;
        const pool_name: []const u8 = if (std.mem.indexOf(u8, pool_config, "/")) |idx| pool_config[0..idx] else pool_config;

        if (!self.poolExists(pool_name)) return null;

        const base_path: []const u8 = if (std.mem.indexOf(u8, pool_config, "/")) |_| pool_config else try std.fmt.allocPrint(self.allocator, "{s}/containers", .{pool_name});
        defer if (base_path.ptr != pool_config.ptr) self.allocator.free(base_path);

        const dataset_name = try std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}", .{ base_path, container_name, vmid });
        errdefer self.allocator.free(dataset_name);

        if (self.datasetExists(dataset_name)) return dataset_name;

        if (self.getParentDataset(dataset_name)) |parent_dataset| {
            if (!self.datasetExists(parent_dataset)) {
                const parent_args = [_][]const u8{ "zfs", "create", "-p", parent_dataset };
                const parent_res = try common.runCommand(self.allocator, self.logger, &parent_args);
                defer {
                    self.allocator.free(parent_res.stdout);
                    self.allocator.free(parent_res.stderr);
                }
                if (parent_res.exit_code != 0) return null;
            }
        }

        const args = [_][]const u8{ "zfs", "create", dataset_name };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer {
            self.allocator.free(res.stdout);
            self.allocator.free(res.stderr);
        }

        if (res.exit_code != 0) return null;

        // Set compression and other properties
        const opts = [_][]const []const u8{
            &.{ "zfs", "set", "compression=lz4", dataset_name },
            &.{ "zfs", "set", "atime=off", dataset_name },
            &.{ "zfs", "set", "sync=disabled", dataset_name },
        };

        for (opts) |opt_args| {
            const opt_res = try common.runCommand(self.allocator, self.logger, opt_args);
            defer {
                self.allocator.free(opt_res.stdout);
                self.allocator.free(opt_res.stderr);
            }
        }

        if (self.logger) |log| try log.info("Successfully created ZFS dataset: {s}", .{dataset_name});

        return dataset_name;
    }

    /// Destroy ZFS dataset for container
    pub fn destroyContainerDataset(self: *const Self, dataset_name: []const u8) !void {
        if (!self.isZFSAvailable()) return;

        if (self.logger) |log| try log.info("Destroying ZFS dataset: {s}", .{dataset_name});

        const args = [_][]const u8{ "zfs", "destroy", "-r", dataset_name };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer self.allocator.free(res.stdout);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) return core.Error.OperationFailed;
    }

    /// Get ZFS dataset mountpoint for container
    pub fn getContainerDatasetMountpoint(self: *const Self, dataset_name: []const u8) !?[]const u8 {
        if (!self.isZFSAvailable()) return null;

        const args = [_][]const u8{ "zfs", "get", "-H", "-o", "value", "mountpoint", dataset_name };
        const res = try common.runCommand(self.allocator, self.logger, &args);
        defer self.allocator.free(res.stderr);
        if (res.exit_code != 0) {
            self.allocator.free(res.stdout);
            return null;
        }
        const trimmed = std.mem.trim(u8, res.stdout, " \t\r\n");
        const mount = try self.allocator.dupe(u8, trimmed);
        self.allocator.free(res.stdout);
        return mount;
    }
};
