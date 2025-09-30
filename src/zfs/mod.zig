// ZFS functionality for container checkpoint/restore
const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");

pub const ZFSError = error{
    CommandExecutionFailed,
    InvalidDataset,
    InvalidSnapshot,
    SnapshotNotFound,
    DatasetNotFound,
    ZFSNotAvailable,
};

pub const ZFSManager = struct {
    allocator: Allocator,
    logger: *logger_mod.Logger,

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *logger_mod.Logger) !*Self {
        // Check if ZFS is available first
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "zfs", "version" },
        }) catch {
            try logger.warn("ZFS not available: command 'zfs' not found", .{});
            return ZFSError.ZFSNotAvailable;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .logger = logger,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    /// Check if ZFS is available on the system
    fn checkZFSAvailability(self: *Self) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "zfs", "version" },
        }) catch {
            try self.logger.warn("ZFS not available: command 'zfs' not found", .{});
            return ZFSError.ZFSNotAvailable;
        };

        if (result.term.Exited != 0) {
            try self.logger.warn("ZFS not available: zfs command failed", .{});
            return ZFSError.ZFSNotAvailable;
        }

        try self.logger.info("ZFS availability confirmed", .{});
    }

    /// Execute ZFS command with error handling
    fn executeZFSCommand(self: *Self, args: []const []const u8) !void {
        try self.logger.info("Executing ZFS command: zfs {s}", .{std.mem.join(self.allocator, " ", args) catch "N/A"});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Build full command with 'zfs' prefix
        var full_args = std.ArrayList([]const u8).init(arena_allocator);
        try full_args.append("zfs");
        for (args) |arg| {
            try full_args.append(arg);
        }

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = full_args.items,
        }) catch |err| {
            try self.logger.err("Failed to execute ZFS command: {s}", .{@errorName(err)});
            return ZFSError.CommandExecutionFailed;
        };

        if (result.term.Exited != 0) {
            try self.logger.err("ZFS command failed with exit code: {d}", .{result.term.Exited});
            if (result.stderr.len > 0) {
                try self.logger.err("ZFS stderr: {s}", .{result.stderr});
            }
            return ZFSError.CommandExecutionFailed;
        }

        try self.logger.info("ZFS command executed successfully", .{});
        if (result.stdout.len > 0) {
            try self.logger.debug("ZFS stdout: {s}", .{result.stdout});
        }
    }

    /// Check if a dataset exists
    pub fn datasetExists(self: *Self, dataset: []const u8) !bool {
        try self.logger.info("Checking if dataset exists: {s}", .{dataset});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "zfs", "list", "-H", "-o", "name", dataset },
        }) catch {
            return false;
        };

        return result.term.Exited == 0;
    }

    /// Create a ZFS snapshot for checkpoint
    pub fn createSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return ZFSError.InvalidDataset;
        }

        // Check if dataset exists first
        if (!try self.datasetExists(dataset)) {
            try self.logger.err("Dataset does not exist: {s}", .{dataset});
            return ZFSError.DatasetNotFound;
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Create full snapshot name: dataset@snapshot
        const full_snapshot = try std.fmt.allocPrint(arena_allocator, "{s}@{s}", .{ dataset, snapshot_name });

        try self.logger.info("Creating ZFS snapshot: {s}", .{full_snapshot});

        const args = [_][]const u8{ "snapshot", full_snapshot };
        try self.executeZFSCommand(&args);

        try self.logger.info("Successfully created ZFS snapshot: {s}", .{full_snapshot});
    }

    /// Restore from a ZFS snapshot
    pub fn restoreFromSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return ZFSError.InvalidSnapshot;
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Create full snapshot name: dataset@snapshot
        const full_snapshot = try std.fmt.allocPrint(arena_allocator, "{s}@{s}", .{ dataset, snapshot_name });

        try self.logger.info("Restoring from ZFS snapshot: {s}", .{full_snapshot});

        // Check if snapshot exists
        if (!try self.snapshotExists(dataset, snapshot_name)) {
            try self.logger.err("Snapshot does not exist: {s}", .{full_snapshot});
            return ZFSError.SnapshotNotFound;
        }

        const args = [_][]const u8{ "rollback", full_snapshot };
        try self.executeZFSCommand(&args);

        try self.logger.info("Successfully restored from ZFS snapshot: {s}", .{full_snapshot});
    }

    /// Check if a snapshot exists
    pub fn snapshotExists(self: *Self, dataset: []const u8, snapshot_name: []const u8) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const full_snapshot = try std.fmt.allocPrint(arena_allocator, "{s}@{s}", .{ dataset, snapshot_name });

        try self.logger.info("Checking if snapshot exists: {s}", .{full_snapshot});

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "zfs", "list", "-H", "-t", "snapshot", "-o", "name", full_snapshot },
        }) catch {
            return false;
        };

        return result.term.Exited == 0;
    }

    /// List all snapshots for a dataset
    pub fn listSnapshots(self: *Self, dataset: []const u8) ![][]const u8 {
        try self.logger.info("Listing snapshots for dataset: {s}", .{dataset});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "zfs", "list", "-H", "-t", "snapshot", "-o", "name", "-r", dataset },
        }) catch |err| {
            try self.logger.err("Failed to list snapshots: {s}", .{@errorName(err)});
            return ZFSError.CommandExecutionFailed;
        };

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to list snapshots, exit code: {d}", .{result.term.Exited});
            return ZFSError.CommandExecutionFailed;
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

        try self.logger.info("Found {d} snapshots for dataset: {s}", .{ snapshots.items.len, dataset });
        return snapshots.toOwnedSlice();
    }

    /// Delete a ZFS snapshot
    pub fn deleteSnapshot(self: *Self, dataset: []const u8, snapshot_name: []const u8) !void {
        if (dataset.len == 0 or snapshot_name.len == 0) {
            return ZFSError.InvalidSnapshot;
        }

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const full_snapshot = try std.fmt.allocPrint(arena_allocator, "{s}@{s}", .{ dataset, snapshot_name });

        try self.logger.info("Deleting ZFS snapshot: {s}", .{full_snapshot});

        // Check if snapshot exists first
        if (!try self.snapshotExists(dataset, snapshot_name)) {
            try self.logger.warn("Snapshot does not exist (already deleted?): {s}", .{full_snapshot});
            return;
        }

        const args = [_][]const u8{ "destroy", full_snapshot };
        try self.executeZFSCommand(&args);

        try self.logger.info("Successfully deleted ZFS snapshot: {s}", .{full_snapshot});
    }

    /// Create a dataset if it doesn't exist
    pub fn createDataset(self: *Self, dataset: []const u8) !void {
        if (dataset.len == 0) {
            return ZFSError.InvalidDataset;
        }

        // Тимчасово відключаємо ZFS logging для діагностики
        // try self.logger.info("Creating ZFS dataset: {s}", .{dataset});

        // Check if dataset already exists
        if (try self.datasetExists(dataset)) {
            // try self.logger.info("Dataset already exists: {s}", .{dataset});
            return;
        }

        const args = [_][]const u8{ "create", dataset };
        try self.executeZFSCommand(&args);

        // try self.logger.info("Successfully created ZFS dataset: {s}", .{dataset});
    }

    /// Get the mountpoint of a dataset
    pub fn getDatasetMountpoint(self: *Self, dataset: []const u8) ![]const u8 {
        try self.logger.info("Getting mountpoint for dataset: {s}", .{dataset});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "zfs", "get", "-H", "-o", "value", "mountpoint", dataset },
        }) catch |err| {
            try self.logger.err("Failed to get dataset mountpoint: {s}", .{@errorName(err)});
            return ZFSError.CommandExecutionFailed;
        };

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to get dataset mountpoint, exit code: {d}", .{result.term.Exited});
            return ZFSError.DatasetNotFound;
        }

        const mountpoint = std.mem.trim(u8, result.stdout, " \t\r\n");
        const owned_mountpoint = try self.allocator.dupe(u8, mountpoint);

        try self.logger.info("Dataset {s} mountpoint: {s}", .{ dataset, owned_mountpoint });
        return owned_mountpoint;
    }

    /// Copy data from source path to ZFS dataset
    pub fn copyToDataset(self: *Self, source_path: []const u8, dataset: []const u8) !void {
        try self.logger.info("Copying {s} to ZFS dataset: {s}", .{ source_path, dataset });

        // Get dataset mountpoint
        const mountpoint = try self.getDatasetMountpoint(dataset);
        defer self.allocator.free(mountpoint);

        // Use rsync to copy data efficiently
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const result = std.process.Child.run(.{
            .allocator = arena_allocator,
            .argv = &[_][]const u8{ "rsync", "-av", "--delete", source_path, mountpoint },
        }) catch |err| {
            try self.logger.err("Failed to copy data to dataset: {s}", .{@errorName(err)});
            return ZFSError.CommandExecutionFailed;
        };

        if (result.term.Exited != 0) {
            try self.logger.err("Failed to copy data to dataset, exit code: {d}", .{result.term.Exited});
            return ZFSError.CommandExecutionFailed;
        }

        try self.logger.info("Successfully copied data to ZFS dataset: {s}", .{dataset});
    }
};
