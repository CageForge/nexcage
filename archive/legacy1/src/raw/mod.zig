/// Raw module placeholder
///
/// This module provides raw file operations for containers.
const std = @import("std");
const core = @import("core");

/// Raw image placeholder
pub const RawImage = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
    }
};

/// Raw file operations
pub const RawFileOps = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Copy file
    pub fn copyFile(self: *Self, src: []const u8, dst: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Copying file: {s} -> {s}", .{ src, dst });
        }

        try std.fs.cwd().copyFile(src, std.fs.cwd(), dst, .{});

        if (self.logger) |log| {
            try log.info("Successfully copied file: {s} -> {s}", .{ src, dst });
        }
    }

    /// Create directory
    pub fn createDir(self: *Self, path: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Creating directory: {s}", .{path});
        }

        try std.fs.cwd().makePath(path);

        if (self.logger) |log| {
            try log.info("Successfully created directory: {s}", .{path});
        }
    }

    /// Remove file or directory
    pub fn remove(self: *Self, path: []const u8) !void {
        if (self.logger) |log| {
            try log.info("Removing: {s}", .{path});
        }

        const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };

        if (stat.kind == .directory) {
            std.fs.cwd().deleteTree(path) catch |err| switch (err) {
                error.FileNotFound => return,
                else => return err,
            };
        } else {
            std.fs.cwd().deleteFile(path) catch |err| switch (err) {
                error.FileNotFound => return,
                else => return err,
            };
        }

        if (self.logger) |log| {
            try log.info("Successfully removed: {s}", .{path});
        }
    }
};
