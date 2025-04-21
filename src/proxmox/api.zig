const std = @import("std");
const types = @import("types");
const error = @import("error");
const logger = @import("logger");

pub const ProxmoxApi = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    token: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16, token: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .token = try allocator.dupe(u8, token),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.host);
        self.allocator.free(self.token);
        self.allocator.destroy(self);
    }

    pub fn createContainer(self: *Self, config: types.ContainerConfig) !types.ContainerId {
        _ = config;
        _ = self;
        return error.NotImplemented;
    }

    pub fn deleteContainer(self: *Self, id: types.ContainerId) !void {
        _ = id;
        _ = self;
        return error.NotImplemented;
    }

    pub fn startContainer(self: *Self, id: types.ContainerId) !void {
        _ = id;
        _ = self;
        return error.NotImplemented;
    }

    pub fn stopContainer(self: *Self, id: types.ContainerId) !void {
        _ = id;
        _ = self;
        return error.NotImplemented;
    }

    pub fn getContainerStatus(self: *Self, id: types.ContainerId) !types.ContainerStatus {
        _ = id;
        _ = self;
        return error.NotImplemented;
    }

    pub fn listContainers(self: *Self) ![]types.ContainerId {
        _ = self;
        return error.NotImplemented;
    }
}; 