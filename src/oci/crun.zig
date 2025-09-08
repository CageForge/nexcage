const std = @import("std");
const Allocator = std.mem.Allocator;
const Logger = @import("logger").Logger;
const types = @import("types");
const OciSpec = @import("spec.zig").Spec;
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

    const Self = @This();

    pub fn init(allocator: Allocator, logger: *Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .logger = logger,
            .root_path = null,
            .log_path = null,
            .crun_path = "/usr/bin/crun",
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.root_path) |path| self.allocator.free(path);
        if (self.log_path) |path| self.allocator.free(path);
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
    // Note: This requires CRIU (Checkpoint/Restore In Userspace) support
    pub fn checkpointContainer(self: *Self, container_id: []const u8, checkpoint_path: ?[]const u8) !void {
        try self.logger.info("Creating checkpoint for container: {s}", .{container_id});

        if (container_id.len == 0) return CrunError.InvalidContainerId;

        // Check if crun supports checkpoint (requires CRIU)
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
            try self.logger.warn("Checkpoint failed - CRIU support may not be available: {s}", .{@errorName(err)});
            try self.logger.info("Alternative: Consider using LXC checkpoints or manual container state management", .{});
            return err;
        };
        
        try self.logger.info("Successfully created checkpoint for container: {s}", .{container_id});
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
