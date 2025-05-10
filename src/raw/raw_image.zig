const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const errors = @import("error");

pub const RawImage = struct {
    allocator: Allocator,
    path: []const u8,
    size: u64,
    logger: *logger_mod.Logger,

    const Self = @This();

    pub fn init(allocator: Allocator, path: []const u8, size: u64, log: *logger_mod.Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .size = size,
            .logger = log,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self) !void {
        try self.logger.info("Creating raw image at {s} with size {d}", .{ self.path, self.size });
        // TODO: Implement raw image creation
    }

    pub fn delete(self: *Self) !void {
        try self.logger.info("Deleting raw image at {s}", .{self.path});
        // TODO: Implement raw image deletion
    }

    pub fn resize(self: *Self, new_size: u64) !void {
        try self.logger.info("Resizing raw image at {s} to {d}", .{ self.path, new_size });
        // TODO: Implement raw image resizing
    }
};
