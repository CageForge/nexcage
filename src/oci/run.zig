// Run command implementation
// This module provides the run command functionality that creates and starts a container

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");
const crun = @import("crun.zig");
const image = @import("image");
const zfs = @import("zfs");
const proxmox = @import("proxmox");

pub const RunError = error{
    InvalidArguments,
    ContainerNotFound,
    ContainerAlreadyExists,
    RuntimeNotAvailable,
    BundleNotFound,
    InvalidConfig,
    InvalidRootfs,
    ContainerExists,
    RuntimeNotImplemented,
    NotImplemented,
};

pub const RunOptions = struct {
    container_id: []const u8,
    bundle_path: []const u8,
    runtime_type: ?[]const u8 = null,
    allocator: Allocator,

    pub fn deinit(self: *RunOptions, allocator: Allocator) void {
        allocator.free(self.container_id);
        allocator.free(self.bundle_path);
        if (self.runtime_type) |rt| {
            allocator.free(rt);
        }
    }
};

/// Parse run command arguments
pub fn parseRunArgs(allocator: Allocator, args: []const []const u8) !RunOptions {
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: run requires --bundle and container-id arguments\n");
        return RunError.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
    var runtime_type: ?[]const u8 = null;
    var i: usize = 1;

    // Parse arguments similar to create command
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--bundle=")) {
            bundle_path = try allocator.dupe(u8, arg[9..]); // Skip "--bundle="
        } else if (std.mem.startsWith(u8, arg, "-b=")) {
            bundle_path = try allocator.dupe(u8, arg[3..]); // Skip "-b="
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --bundle requires a path argument\n");
                return RunError.InvalidArguments;
            }
            bundle_path = try allocator.dupe(u8, args[i + 1]);
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--runtime=")) {
            runtime_type = try allocator.dupe(u8, arg[10..]); // Skip "--runtime="
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --runtime requires a type argument\n");
                return RunError.InvalidArguments;
            }
            runtime_type = try allocator.dupe(u8, args[i + 1]);
            i += 1;
        } else if (!std.mem.eql(u8, arg, "run")) {
            // This should be the container ID
            if (container_id == null) {
                container_id = try allocator.dupe(u8, arg);
            }
        }
    }

    if (bundle_path == null) {
        try std.io.getStdErr().writer().writeAll("Error: --bundle argument is required\n");
        return RunError.InvalidArguments;
    }

    if (container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: container-id argument is required\n");
        return RunError.InvalidArguments;
    }

    return RunOptions{
        .container_id = container_id.?,
        .bundle_path = bundle_path.?,
        .runtime_type = runtime_type,
        .allocator = allocator,
    };
}

/// Execute run command - creates and starts a container
pub fn executeRun(allocator: Allocator, args: []const []const u8, logger: *logger_mod.Logger) !void {
    var run_options = parseRunArgs(allocator, args) catch |err| {
        return err;
    };
    defer run_options.deinit(allocator);

    try logger.info("Running container: {s} with bundle: {s}", .{ run_options.container_id, run_options.bundle_path });

    // Step 1/2: Create container
    try logger.info("Step 1/2: Creating container...", .{});
    try createContainer(allocator, &run_options, logger);

    // Step 2/2: Start container
    try logger.info("Step 2/2: Starting container...", .{});
    try startContainer(allocator, run_options.container_id, logger);

    try logger.info("Successfully ran container: {s}", .{run_options.container_id});
}

/// Create container using the specified options
fn createContainer(allocator: Allocator, options: *RunOptions, logger: *logger_mod.Logger) !void {
    try logger.info("Creating container: {s} with bundle: {s}", .{ options.container_id, options.bundle_path });

    // Determine runtime type (currently we only support crun)
    if (options.runtime_type) |rt| {
        if (std.mem.eql(u8, rt, "lxc") or std.mem.eql(u8, rt, "proxmox-lxc")) {
            try logger.warn("LXC runtime requested but not yet fully implemented, using crun", .{});
        } else if (std.mem.eql(u8, rt, "vm")) {
            try logger.warn("VM runtime requested but not yet implemented, using crun", .{});
        }
    }

    // Create crun manager for container operations
    var crun_manager = try crun.CrunManager.init(allocator, logger);
    defer crun_manager.deinit();

    // Execute create
    try crun_manager.createContainer(options.container_id, options.bundle_path, null);
    try logger.info("Successfully created container: {s}", .{options.container_id});
}

/// Start container by ID
fn startContainer(allocator: Allocator, container_id: []const u8, logger: *logger_mod.Logger) !void {
    try logger.info("Starting container: {s}", .{container_id});

    // Create crun manager
    var crun_manager = try crun.CrunManager.init(allocator, logger);
    defer crun_manager.deinit();

    // Start container using crun
    try crun_manager.startContainer(container_id);
    try logger.info("Successfully started container: {s}", .{container_id});
}
