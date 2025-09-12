// Crun module - Zig bindings for the crun OCI runtime
// This module provides Zig bindings for the crun OCI runtime

const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const types = @import("types");

/// Crun container handle
pub const CrunContainer = struct {
    const Self = @This();
    
    allocator: Allocator,
    logger: *logger_mod.Logger,
    container_id: []const u8,
    crun_path: []const u8,
    
    pub fn init(allocator: Allocator, logger: *logger_mod.Logger, container_id: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .logger = logger,
            .container_id = try allocator.dupe(u8, container_id),
            .crun_path = "/usr/bin/crun",
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.container_id);
    }
    
    /// Check if crun is available
    pub fn isAvailable(self: *const Self) bool {
        _ = self;
        // Check if crun binary exists
        if (std.fs.accessAbsolute("/usr/bin/crun", .{})) {
            return true;
        } else |_| {
            if (std.fs.accessAbsolute("/usr/local/bin/crun", .{})) {
                return true;
            } else |_| {
                return false;
            }
        }
    }
    
    /// Create container
    pub fn create(self: *Self, bundle_path: []const u8, config_path: []const u8) !void {
        _ = config_path;
        try self.logger.info("Creating crun container: {s} with bundle: {s}", .{ self.container_id, bundle_path });
        
        // Use system crun binary
        const args = [_][]const u8{
            self.crun_path,
            "create",
            self.container_id,
            "--bundle", bundle_path,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to create crun container: {s}", .{result.stderr});
            return error.CrunCreateFailed;
        }
        
        try self.logger.info("Successfully created crun container: {s}", .{self.container_id});
    }
    
    /// Start container
    pub fn start(self: *Self) !void {
        try self.logger.info("Starting crun container: {s}", .{self.container_id});
        
        const args = [_][]const u8{
            self.crun_path,
            "start",
            self.container_id,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to start crun container: {s}", .{result.stderr});
            return error.CrunStartFailed;
        }
        
        try self.logger.info("Successfully started crun container: {s}", .{self.container_id});
    }
    
    /// Stop container
    pub fn stop(self: *Self, timeout: ?u32) !void {
        try self.logger.info("Stopping crun container: {s}", .{self.container_id});
        
        _ = timeout;
        const args = [_][]const u8{
            self.crun_path,
            "kill",
            self.container_id,
            "TERM",
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to stop crun container: {s}", .{result.stderr});
            return error.CrunStopFailed;
        }
        
        try self.logger.info("Successfully stopped crun container: {s}", .{self.container_id});
    }
    
    /// Delete container
    pub fn delete(self: *Self) !void {
        try self.logger.info("Deleting crun container: {s}", .{self.container_id});
        
        const args = [_][]const u8{
            self.crun_path,
            "delete",
            self.container_id,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to delete crun container: {s}", .{result.stderr});
            return error.CrunDeleteFailed;
        }
        
        try self.logger.info("Successfully deleted crun container: {s}", .{self.container_id});
    }
    
    /// Get container state
    pub fn getState(self: *Self) !CrunContainerState {
        try self.logger.info("Getting state for crun container: {s}", .{self.container_id});
        
        const args = [_][]const u8{
            self.crun_path,
            "state",
            self.container_id,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to get crun container state: {s}", .{result.stderr});
            return error.CrunGetStateFailed;
        }
        
        // Parse state from output (simplified)
        const status = if (std.mem.indexOf(u8, result.stdout, "running") != null) 
            .running 
        else if (std.mem.indexOf(u8, result.stdout, "created") != null) 
            .created 
        else if (std.mem.indexOf(u8, result.stdout, "stopped") != null) 
            .stopped 
        else 
            .unknown;
        
        return CrunContainerState{
            .id = try self.allocator.dupe(u8, self.container_id),
            .pid = 0, // TODO: Parse PID from output
            .status = status,
            .bundle = null, // TODO: Parse bundle from output
            .allocator = self.allocator,
        };
    }
    
    /// List containers
    pub fn listContainers(self: *Self) ![]CrunContainerState {
        try self.logger.info("Listing crun containers", .{});
        
        const args = [_][]const u8{
            self.crun_path,
            "list",
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to list crun containers: {s}", .{result.stderr});
            return error.CrunListFailed;
        }
        
        // Parse containers from output (simplified)
        const container_states = try self.allocator.alloc(CrunContainerState, 0);
        
        try self.logger.info("Successfully listed {d} crun containers", .{container_states.len});
        return container_states;
    }
    
    /// Pause container
    pub fn pause(self: *Self) !void {
        try self.logger.info("Pausing crun container: {s}", .{self.container_id});
        
        const args = [_][]const u8{
            self.crun_path,
            "pause",
            self.container_id,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to pause crun container: {s}", .{result.stderr});
            return error.CrunPauseFailed;
        }
        
        try self.logger.info("Successfully paused crun container: {s}", .{self.container_id});
    }
    
    /// Resume container
    pub fn resumeContainer(self: *Self) !void {
        try self.logger.info("Resuming crun container: {s}", .{self.container_id});
        
        const args = [_][]const u8{
            self.crun_path,
            "resume",
            self.container_id,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to resume crun container: {s}", .{result.stderr});
            return error.CrunResumeFailed;
        }
        
        try self.logger.info("Successfully resumed crun container: {s}", .{self.container_id});
    }
    
    /// Kill container
    pub fn kill(self: *Self, signal: i32) !void {
        try self.logger.info("Killing crun container: {s} with signal: {}", .{ self.container_id, signal });
        
        const signal_name = switch (signal) {
            9 => "KILL",
            15 => "TERM",
            2 => "INT",
            else => "TERM",
        };
        
        const args = [_][]const u8{
            self.crun_path,
            "kill",
            self.container_id,
            signal_name,
        };
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to kill crun container: {s}", .{result.stderr});
            return error.CrunKillFailed;
        }
        
        try self.logger.info("Successfully killed crun container: {s}", .{self.container_id});
    }
    
    /// Execute command in container
    pub fn exec(self: *Self, command: []const []const u8) !void {
        try self.logger.info("Executing command in crun container: {s}", .{self.container_id});
        
        // Build exec command
        var args = try self.allocator.alloc([]const u8, command.len + 3);
        defer self.allocator.free(args);
        
        args[0] = self.crun_path;
        args[1] = "exec";
        args[2] = self.container_id;
        
        for (command, 0..) |arg, i| {
            args[i + 3] = arg;
        }
        
        const result = std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = args,
        });
        
        if (result.exit_code != 0) {
            try self.logger.err("Failed to exec command in crun container: {s}", .{result.stderr});
            return error.CrunExecFailed;
        }
        
        try self.logger.info("Successfully executed command in crun container: {s}", .{self.container_id});
    }
};

/// Crun container state
pub const CrunContainerState = struct {
    id: []const u8,
    pid: i32,
    status: CrunContainerStatus,
    bundle: ?[]const u8,
    allocator: Allocator,
    
    pub fn deinit(self: *CrunContainerState) void {
        self.allocator.free(self.id);
        if (self.bundle) |bundle| {
            self.allocator.free(bundle);
        }
    }
};

/// Crun container status
pub const CrunContainerStatus = enum {
    created,
    running,
    stopped,
    paused,
    unknown,
};

/// Crun errors
pub const CrunError = error{
    CrunContextInitFailed,
    CrunContextNotInitialized,
    CrunCreateFailed,
    CrunStartFailed,
    CrunStopFailed,
    CrunDeleteFailed,
    CrunGetStateFailed,
    CrunListFailed,
    CrunPauseFailed,
    CrunResumeFailed,
    CrunKillFailed,
    CrunExecFailed,
};

/// Crun constants
pub const SIGTERM = 15;
pub const SIGKILL = 9;
pub const SIGSTOP = 19;
pub const SIGCONT = 18;
