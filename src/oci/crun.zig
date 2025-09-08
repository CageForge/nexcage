const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const types = @import("types");
const OciSpec = @import("spec.zig").Spec;
const zfs = @import("zfs");
const process = std.process;
const fs = std.fs;

// Error types for crun operations
pub const CrunError = error{
    ContainerCreateFailed,
    ContainerStartFailed,
    ContainerDeleteFailed,
    ContainerRunFailed,
    ContainerNotFound,
    InvalidConfiguration,
    RuntimeError,
    OutOfMemory,
    InvalidContainerId,
    InvalidBundlePath,
    ContextInitFailed,
    ContainerLoadFailed,
    ContainerLoadError,
    ContainerStateError,
    ContainerKillError,
    CommandExecutionFailed,
    CrunNotFound,
    SnapshotNotFound,
};

// Container state enum
// ContainerState moved to types.zig
pub const ContainerState = types.ContainerState;

// ContainerStatus moved to types.zig
pub const ContainerStatus = types.ContainerStatus;

// Main CrunManager struct
pub const CrunManager = struct {
    allocator: Allocator,
    logger: *Logger,
    root_path: ?[]const u8,
    log_path: ?[]const u8,
    crun_path: []const u8,
    zfs_manager: ?*zfs.ZFSManager,

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger) !*Self {
        const self = try allocator.create(Self);
        
        // Try to initialize ZFS manager (optional)
        const zfs_manager = zfs.ZFSManager.init(allocator, logger) catch |err| blk: {
            try logger.info("ZFS not available, falling back to CRIU-only checkpoint: {s}", .{@errorName(err)});
            break :blk null;
        };
        
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .root_path = null,
            .log_path = null,
            .crun_path = "/usr/bin/crun",
            .zfs_manager = zfs_manager,
        };

        try self.logger.info("CrunManager initialized with crun path: {s}", .{self.crun_path});
        if (self.zfs_manager != null) {
            try self.logger.info("ZFS checkpoint/restore support enabled", .{});
        }
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.root_path) |path| self.allocator.free(path);
        if (self.log_path) |path| self.allocator.free(path);
        if (self.zfs_manager) |zfs_mgr| zfs_mgr.deinit();
        self.allocator.destroy(self);
    }

    // Set root path for containers
    pub fn setRootPath(self: *Self, root_path: []const u8) !void {
        if (self.root_path) |old_path| self.allocator.free(old_path);
        self.root_path = try self.allocator.dupe(u8, root_path);
    }

    // Set log path
    pub fn setLogPath(self: *Self, log_path: []const u8) !void {
        if (self.log_path) |old_path| self.allocator.free(old_path);
        self.log_path = try self.allocator.dupe(u8, log_path);
    }

    // Set crun binary path
    pub fn setCrunPath(self: *Self, crun_path: []const u8) !void {
        self.crun_path = try self.allocator.dupe(u8, crun_path);
    }

    // Check if crun is available
    fn checkCrunAvailable(self: *Self) !void {
        const file = fs.openFileAbsolute(self.crun_path, .{}) catch |err| {
            try self.logger.err("crun not found at {s}: {s}", .{self.crun_path, @errorName(err)});
            return CrunError.CrunNotFound;
        };
        defer file.close();
    }

    // Execute crun command
    fn executeCrunCommand(self: *Self, args: []const []const u8) !void {
        try self.checkCrunAvailable();

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Build command with crun path
        var cmd_args = std.ArrayList([]const u8).init(arena_allocator);
        try cmd_args.append(self.crun_path);
        try cmd_args.appendSlice(args);

        try self.logger.info("Executing crun command: {s}", .{std.mem.join(arena_allocator, " ", cmd_args.items) catch "unknown"});

        // Execute command using Child
        var child = process.Child.init(cmd_args.items, arena_allocator);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        const term = child.spawnAndWait() catch |err| {
            try self.logger.err("Failed to execute crun command: {s}", .{@errorName(err)});
            return CrunError.CommandExecutionFailed;
        };

        if (term.Exited != 0) {
            try self.logger.err("crun command failed with exit code: {d}", .{term.Exited});
            return CrunError.CommandExecutionFailed;
        }

        try self.logger.info("crun command executed successfully", .{});
    }

    // Create a new container
    pub fn createContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, _: ?*const OciSpec) !void {
        try self.logger.info("Creating crun container: {s} in bundle: {s}", .{ container_id, bundle_path });

        // Validate inputs
        if (container_id.len == 0) return CrunError.InvalidContainerId;
        if (bundle_path.len == 0) return CrunError.InvalidBundlePath;

        // Build crun create command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("create");
        
        // Add bundle option
        try args.append("--bundle");
        try args.append(bundle_path);
        
        // Add options to avoid common issues
        try args.append("--no-new-keyring");
        try args.append("--no-pivot");
        try args.append("--console-socket");
        try args.append("/tmp/console.sock");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }
        
        try args.append(container_id);

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully created crun container: {s}", .{container_id});
    }

    // Start a container
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Starting crun container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Build crun start command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("start");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }
        
        try args.append(container_id);

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully started crun container: {s}", .{container_id});
    }

    // Delete a container
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        try self.logger.info("Deleting crun container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Build crun delete command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("delete");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }
        
        try args.append(container_id);

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully deleted crun container: {s}", .{container_id});
    }

    // Run a container (create + start)
    pub fn runContainer(self: *Self, container_id: []const u8, bundle_path: []const u8, _: ?*const OciSpec) !void {
        try self.logger.info("Running crun container: {s} in bundle: {s}", .{ container_id, bundle_path });

        // Create container first
        try self.createContainer(container_id, bundle_path, null);

        // Then start it
        try self.startContainer(container_id);

        try self.logger.info("Successfully ran crun container: {s}", .{container_id});
    }

    // Check if container exists
    pub fn containerExists(self: *Self, container_id: []const u8) !bool {
        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Try to get container state - if it succeeds, container exists
        const state = self.getContainerState(container_id) catch |err| {
            if (err == CrunError.ContainerStateError) {
                return false; // Container doesn't exist
            }
            return err;
        };

        return state != ContainerState.unknown;
    }

    // Get container state
    pub fn getContainerState(self: *Self, container_id: []const u8) !ContainerState {
        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Build crun state command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("state");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }
        
        try args.append(container_id);

        // For now, we'll use a simple approach - try to get state
        // In a real implementation, we'd parse the JSON output
        _ = self.executeCrunCommand(args.items) catch |err| {
            if (err == CrunError.CommandExecutionFailed) {
                return ContainerState.unknown;
            }
            return err;
        };

        // For now, assume container is running if state command succeeds
        // In a real implementation, we'd parse the JSON output to get actual state
        return ContainerState.running;
    }

    // Kill a container
    pub fn killContainer(self: *Self, container_id: []const u8, signal: []const u8) !void {
        try self.logger.info("Killing crun container: {s} with signal: {s}", .{ container_id, signal });

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Build crun kill command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("kill");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }
        
        try args.append(container_id);
        try args.append(signal);

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully killed crun container: {s}", .{container_id});
    }

    // Generate OCI spec
    pub fn generateSpec(self: *Self, bundle_path: []const u8) !void {
        try self.logger.info("Generating OCI spec in bundle: {s}", .{bundle_path});

        if (bundle_path.len == 0) return CrunError.InvalidBundlePath;

        // Build crun spec command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("spec");
        
        // Add bundle option
        try args.append("--bundle");
        try args.append(bundle_path);

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully generated OCI spec in bundle: {s}", .{bundle_path});
    }

    // Create checkpoint of a running container
    // Tries ZFS snapshots first, falls back to CRIU if ZFS unavailable
    pub fn checkpointContainer(self: *Self, container_id: []const u8, checkpoint_path: ?[]const u8) !void {
        try self.logger.info("Creating checkpoint for container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Try ZFS snapshot first if available
        if (self.zfs_manager) |zfs_mgr| {
            return self.checkpointWithZFS(zfs_mgr, container_id, checkpoint_path);
        }

        // Fall back to CRIU-based checkpoint
        return self.checkpointWithCRIU(container_id, checkpoint_path);
    }

    // ZFS-based checkpoint implementation
    fn checkpointWithZFS(self: *Self, zfs_mgr: *zfs.ZFSManager, container_id: []const u8, checkpoint_path: ?[]const u8) !void {
        try self.logger.info("Using ZFS snapshot for checkpoint: {s}", .{container_id});

        // Determine the ZFS dataset for this container
        // This could be configured per container, but for now we'll use a convention
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Default dataset pattern: tank/containers/<container_id>
        // This can be made configurable later
        const dataset = if (checkpoint_path) |path| 
            path 
        else 
            try std.fmt.allocPrint(arena_allocator, "tank/containers/{s}", .{container_id});

        // Generate snapshot name with timestamp
        const timestamp = std.time.timestamp();
        const snapshot_name = try std.fmt.allocPrint(arena_allocator, "checkpoint-{d}", .{timestamp});

        // Note: Should stop the container before taking snapshot (to ensure consistency)
        // TODO: Implement stopContainer method
        try self.logger.info("Note: Container should be stopped manually for consistent checkpoint", .{});

        // Create ZFS snapshot
        try zfs_mgr.createSnapshot(dataset, snapshot_name);
        
        try self.logger.info("Successfully created ZFS checkpoint snapshot: {s}@{s}", .{ dataset, snapshot_name });
    }

    // CRIU-based checkpoint implementation (fallback)
    fn checkpointWithCRIU(self: *Self, container_id: []const u8, checkpoint_path: ?[]const u8) !void {
        try self.logger.info("Using CRIU for checkpoint: {s}", .{container_id});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Try using crun's checkpoint if available (with CRIU support)
        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("checkpoint");
        
        // Add checkpoint path if provided
        if (checkpoint_path) |path| {
            try args.append("--image-path");
            try args.append(path);
        }
        
        try args.append(container_id);

        // Execute checkpoint command and handle potential failure
        self.executeCrunCommand(args.items) catch |err| {
            try self.logger.warn("CRIU checkpoint failed - CRIU support may not be available: {s}", .{@errorName(err)});
            try self.logger.info("Alternative: Use ZFS datasets for checkpoint/restore functionality", .{});
            return err;
        };
        
        try self.logger.info("Successfully created CRIU checkpoint for container: {s}", .{container_id});
    }

    // Restore container from checkpoint
    // Tries ZFS snapshots first, falls back to CRIU if ZFS unavailable
    pub fn restoreContainer(self: *Self, container_id: []const u8, checkpoint_path: ?[]const u8, snapshot_name: ?[]const u8) !void {
        try self.logger.info("Restoring container from checkpoint: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Try ZFS restore first if available
        if (self.zfs_manager) |zfs_mgr| {
            return self.restoreWithZFS(zfs_mgr, container_id, checkpoint_path, snapshot_name);
        }

        // Fall back to CRIU-based restore
        return self.restoreWithCRIU(container_id, checkpoint_path);
    }

    // ZFS-based restore implementation
    fn restoreWithZFS(self: *Self, zfs_mgr: *zfs.ZFSManager, container_id: []const u8, checkpoint_path: ?[]const u8, snapshot_name: ?[]const u8) !void {
        try self.logger.info("Using ZFS snapshot for restore: {s}", .{container_id});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Determine the ZFS dataset for this container
        const dataset = if (checkpoint_path) |path| 
            path 
        else 
            try std.fmt.allocPrint(arena_allocator, "tank/containers/{s}", .{container_id});

        // Determine snapshot name
        const restore_snapshot = if (snapshot_name) |name|
            name
        else blk: {
            // Find the latest checkpoint snapshot
            const snapshots = try zfs_mgr.listSnapshots(dataset);
            defer {
                for (snapshots) |snapshot| {
                    self.allocator.free(snapshot);
                }
                self.allocator.free(snapshots);
            }

            // Filter for checkpoint snapshots and find the latest
            var latest_checkpoint: ?[]const u8 = null;
            var latest_timestamp: i64 = 0;

            for (snapshots) |snapshot| {
                // Extract snapshot name (after the @)
                if (std.mem.indexOf(u8, snapshot, "@")) |at_index| {
                    const snap_name = snapshot[at_index + 1..];
                    if (std.mem.startsWith(u8, snap_name, "checkpoint-")) {
                        if (std.mem.eql(u8, snap_name, "checkpoint-")) continue; // Skip malformed
                        
                        // Extract timestamp
                        const timestamp_str = snap_name[11..]; // Skip "checkpoint-"
                        const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch continue;
                        
                        if (timestamp > latest_timestamp) {
                            latest_timestamp = timestamp;
                            latest_checkpoint = snap_name;
                        }
                    }
                }
            }

            if (latest_checkpoint) |latest| {
                break :blk try self.allocator.dupe(u8, latest);
            } else {
                try self.logger.err("No checkpoint snapshots found for container: {s}", .{container_id});
                return CrunError.SnapshotNotFound;
            }
        };

        // Note: Should stop the container if it's running before restore
        // TODO: Implement stopContainer method  
        try self.logger.info("Note: Container should be stopped manually before restore", .{});

        // Restore from ZFS snapshot
        try zfs_mgr.restoreFromSnapshot(dataset, restore_snapshot);
        
        try self.logger.info("Successfully restored from ZFS snapshot: {s}@{s}", .{ dataset, restore_snapshot });
    }

    // CRIU-based restore implementation (fallback)
    fn restoreWithCRIU(self: *Self, container_id: []const u8, checkpoint_path: ?[]const u8) !void {
        try self.logger.info("Using CRIU for restore: {s}", .{container_id});

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Try using crun's restore if available (with CRIU support)
        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("restore");
        
        // Add checkpoint path if provided
        if (checkpoint_path) |path| {
            try args.append("--image-path");
            try args.append(path);
        }
        
        try args.append(container_id);

        // Execute restore command and handle potential failure
        self.executeCrunCommand(args.items) catch |err| {
            try self.logger.warn("CRIU restore failed - CRIU support may not be available: {s}", .{@errorName(err)});
            try self.logger.info("Alternative: Use ZFS datasets for checkpoint/restore functionality", .{});
            return err;
        };
        
        try self.logger.info("Successfully restored from CRIU checkpoint for container: {s}", .{container_id});
    }

    // List all containers
    pub fn listContainers(self: *Self) !void {
        try self.logger.info("Listing all containers...", .{});

        // Build crun list command
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var args = std.ArrayList([]const u8).init(arena_allocator);
        try args.append("list");
        
        // Add root path if specified
        if (self.root_path) |root| {
            try args.append("--root");
            try args.append(root);
        }

        try self.executeCrunCommand(args.items);
        try self.logger.info("Successfully listed containers", .{});
    }
};
