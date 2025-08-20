const std = @import("std");

pub const CrunManager = struct {
	allocator: std.mem.Allocator,

	pub fn init(allocator: std.mem.Allocator) CrunManager {
		return .{ .allocator = allocator };
	}

	pub fn deinit(self: *CrunManager) void {
		_ = self;
	}

	pub fn createContainer(self: *CrunManager, _id: []const u8, _bundle: []const u8, _spec: anytype) !void {
		_ = self;
		_ = _id;
		_ = _bundle;
		_ = _spec;
	}

	pub fn startContainer(self: *CrunManager, _id: []const u8) !void {
		_ = self;
		_ = _id;
	}
};