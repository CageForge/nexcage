const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types");
const routing = @import("routing");

pub const PauseConfig = struct {
    allocator: Allocator,
    id: []const u8,
    name: []const u8,
    image: []const u8,
    command: []const []const u8,
    env: []const []const u8,
    working_dir: []const u8,
    user: []const u8,
    hostname: []const u8,
    mounts: []const types.Mount,
    resources: types.Resources,
    namespaces: []const routing.NamespaceConfig,

    pub fn init(allocator: Allocator) !PauseConfig {
        return PauseConfig{
            .allocator = allocator,
            .id = try allocator.dupe(u8, "pause-1"),
            .name = try allocator.dupe(u8, "pause"),
            .image = try allocator.dupe(u8, "pause:latest"),
            .command = &[_][]const u8{"/pause"},
            .env = &[_][]const u8{},
            .working_dir = try allocator.dupe(u8, "/"),
            .user = try allocator.dupe(u8, "root"),
            .hostname = try allocator.dupe(u8, "pause"),
            .mounts = &[_]types.Mount{},
            .resources = .{
                .cpu_shares = 2,
                .memory_limit = 10 * 1024 * 1024, // 10MB
                .memory_swap = 0,
                .cpu_period = 100000,
                .cpu_quota = 50000,
            },
            .namespaces = &[_]routing.NamespaceConfig{
                .{ .name = "network", .value = "host" },
                .{ .name = "pid", .value = "private" },
            },
        };
    }

    pub fn deinit(self: *PauseConfig) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.image);
        self.allocator.free(self.working_dir);
        self.allocator.free(self.user);
        self.allocator.free(self.hostname);
    }
}; 