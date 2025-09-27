const std = @import("std");
const core = @import("core");
const types = @import("types.zig");
const utils = @import("utils");

/// ZFS client for container checkpoint/restore operations
/// ZFS client implementation
pub const ZFSClient = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.alloc(Self, 1);
        self[0] = Self{
            .allocator = allocator,
        };

        // Check if ZFS is available first
        const result = try utils.fs.runCommand(allocator, &[_][]const u8{ "zfs", "version" }, .{});
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self[0].logger) |log| {
                try log.warn("ZFS not available: command 'zfs' not found");
            }
            return types.ZFSError.ZFSNotAvailable;
        }

        return &self[0];
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self);
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Check if ZFS is available on the system
    fn checkZFSAvailability(self: *Self) !void {
        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "zfs", "version" }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.warn("ZFS not available: zfs command failed");
            }
            return types.ZFSError.ZFSNotAvailable;
        }

        if (self.logger) |log| {
            try log.info("ZFS availability confirmed");
        }
    }

    /// Execute ZFS command with error handling
    fn executeZFSCommand(self: *Self, args: []const []const u8) !void {
        if (self.logger) |log| {
            try log.info("Executing ZFS command: zfs {s}", .{std.mem.join(self.allocator, " ", args) catch "N/A"});
        }

        // Build full command with 'zfs' prefix
        var full_args = std.ArrayList([]const u8).init(self.allocator);
        defer full_args.deinit();
        try full_args.append("zfs");
        for (args) |arg| {
            try full_args.append(arg);
        }

        const result = try utils.fs.runCommand(self.allocator, full_args.items, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("ZFS command failed with exit code: {d}", .{result.exit_code});
                if (result.stderr.len > 0) {
                    try log.@"error"("ZFS stderr: {s}", .{result.stderr});
                }
            }
            return types.ZFSError.CommandExecutionFailed;
        }

        if (self.logger) |log| {
            try log.info("ZFS command executed successfully");
            if (result.stdout.len > 0) {
                try log.debug("ZFS stdout: {s}", .{result.stdout});
            }
        }
    }

    /// Check if a dataset exists
    pub fn datasetExists(self: *Self, dataset: []const u8) !bool {
        if (self.logger) |log| {
            try log.info("Checking if dataset exists: {s}", .{dataset});
        }

        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "zfs", "list", "-H", "-o", "name", dataset }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        return result.exit_code == 0;
    }

    /// Create a ZFS snapshot for checkpoint
    pub fn createSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return types.ZFSError.InvalidDataset;
        }

        // Check if dataset exists first
        if (!try self.datasetExists(dataset)) {
            if (self.logger) |log| {
                try log.@"error"("Dataset does not exist: {s}", .{dataset});
            }
            return types.ZFSError.DatasetNotFound;
        }

        // Create full snapshot name: dataset@snapshot
        const full_snapshot = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ dataset, snapshot_name });
        defer self.allocator.free(full_snapshot);

        if (self.logger) |log| {
            try log.info("Creating ZFS snapshot: {s}", .{full_snapshot});
        }

        const args = [_][]const u8{ "snapshot", full_snapshot };
        try self.executeZFSCommand(&args);

        if (self.logger) |log| {
            try log.info("Successfully created ZFS snapshot: {s}", .{full_snapshot});
        }
    }

    /// Restore from a ZFS snapshot
    pub fn restoreFromSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return types.ZFSError.InvalidSnapshot;
        }

        // Create full snapshot name: dataset@snapshot
        const full_snapshot = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ dataset, snapshot_name });
        defer self.allocator.free(full_snapshot);

        if (self.logger) |log| {
            try log.info("Restoring from ZFS snapshot: {s}", .{full_snapshot});
        }

        // Check if snapshot exists
        if (!try self.snapshotExists(dataset, snapshot_name)) {
            if (self.logger) |log| {
                try log.@"error"("Snapshot does not exist: {s}", .{full_snapshot});
            }
            return types.ZFSError.SnapshotNotFound;
        }

        const args = [_][]const u8{ "rollback", full_snapshot };
        try self.executeZFSCommand(&args);

        if (self.logger) |log| {
            try log.info("Successfully restored from ZFS snapshot: {s}", .{full_snapshot});
        }
    }

    /// Check if a snapshot exists
    pub fn snapshotExists(self: *Self, dataset: []const u8, snapshot_name: []const u8) !bool {
        const full_snapshot = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ dataset, snapshot_name });
        defer self.allocator.free(full_snapshot);

        if (self.logger) |log| {
            try log.info("Checking if snapshot exists: {s}", .{full_snapshot});
        }

        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "zfs", "list", "-H", "-t", "snapshot", "-o", "name", full_snapshot }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        return result.exit_code == 0;
    }

    /// List all snapshots for a dataset
    pub fn listSnapshots(self: *Self, dataset: []const u8) ![][]const u8 {
        if (self.logger) |log| {
            try log.info("Listing snapshots for dataset: {s}", .{dataset});
        }

        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "zfs", "list", "-H", "-t", "snapshot", "-o", "name", "-r", dataset }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to list snapshots, exit code: {d}", .{result.exit_code});
            }
            return types.ZFSError.CommandExecutionFailed;
        }

        // Parse the output to extract snapshot names
        var snapshots = std.ArrayList([]const u8).init(self.allocator);
        var lines = std.mem.split(u8, result.stdout, "\n");

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len > 0) {
                // Clone the string to persist beyond arena scope
                const snapshot_name = try self.allocator.dupe(u8, trimmed);
                try snapshots.append(snapshot_name);
            }
        }

        if (self.logger) |log| {
            try log.info("Found {d} snapshots for dataset: {s}", .{ snapshots.items.len, dataset });
        }
        return snapshots.toOwnedSlice();
    }

    /// Delete a ZFS snapshot
    pub fn deleteSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return types.ZFSError.InvalidSnapshot;
        }

        const full_snapshot = try std.fmt.allocPrint(self.allocator, "{s}@{s}", .{ dataset, snapshot_name });
        defer self.allocator.free(full_snapshot);

        if (self.logger) |log| {
            try log.info("Deleting ZFS snapshot: {s}", .{full_snapshot});
        }

        // Check if snapshot exists first
        if (!try self.snapshotExists(dataset, snapshot_name)) {
            if (self.logger) |log| {
                try log.warn("Snapshot does not exist (already deleted?): {s}", .{full_snapshot});
            }
            return;
        }

        const args = [_][]const u8{ "destroy", full_snapshot };
        try self.executeZFSCommand(&args);

        if (self.logger) |log| {
            try log.info("Successfully deleted ZFS snapshot: {s}", .{full_snapshot});
        }
    }

    /// Create a dataset if it doesn't exist
    pub fn createDataset(self: *Self, dataset: []const u8) !void {
        if (dataset.len == 0) {
            return types.ZFSError.InvalidDataset;
        }

        // Check if dataset already exists
        if (try self.datasetExists(dataset)) {
            return;
        }

        const args = [_][]const u8{ "create", dataset };
        try self.executeZFSCommand(&args);
    }

    /// Get the mountpoint of a dataset
    pub fn getDatasetMountpoint(self: *Self, dataset: []const u8) ![]const u8 {
        if (self.logger) |log| {
            try log.info("Getting mountpoint for dataset: {s}", .{dataset});
        }

        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "zfs", "get", "-H", "-o", "value", "mountpoint", dataset }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to get dataset mountpoint, exit code: {d}", .{result.exit_code});
            }
            return types.ZFSError.DatasetNotFound;
        }

        const mountpoint = std.mem.trim(u8, result.stdout, " \t\r\n");
        const owned_mountpoint = try self.allocator.dupe(u8, mountpoint);

        if (self.logger) |log| {
            try log.info("Dataset {s} mountpoint: {s}", .{ dataset, owned_mountpoint });
        }
        return owned_mountpoint;
    }

    /// Copy data from source path to ZFS dataset
    pub fn copyToDataset(self: *Self, source_path: []const u8, dataset: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Copying {s} to ZFS dataset: {s}", .{ source_path, dataset });
        }

        // Get dataset mountpoint
        const mountpoint = try self.getDatasetMountpoint(dataset);
        defer self.allocator.free(mountpoint);

        // Use rsync to copy data efficiently
        const result = try utils.fs.runCommand(self.allocator, &[_][]const u8{ "rsync", "-av", "--delete", source_path, mountpoint }, .{});
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.exit_code != 0) {
            if (self.logger) |log| {
                try log.@"error"("Failed to copy data to dataset, exit code: {d}", .{result.exit_code});
            }
            return types.ZFSError.CommandExecutionFailed;
        }

        if (self.logger) |log| {
            try log.info("Successfully copied data to ZFS dataset: {s}", .{dataset});
        }
    }
};
