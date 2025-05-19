const std = @import("std");
const types = @import("types");
const container = @import("container");
const Config = @import("config").Config;

pub const OCIRuntime = struct {
    allocator: std.mem.Allocator,
    config: *Config,

    pub fn init(allocator: std.mem.Allocator, config: *Config) !*OCIRuntime {
        var runtime = try allocator.create(OCIRuntime);
        runtime.* = OCIRuntime{
            .allocator = allocator,
            .config = config,
        };
        return runtime;
    }

    pub fn deinit(self: *OCIRuntime) void {
        self.allocator.destroy(self);
    }

    pub fn createContainer(self: *OCIRuntime, config: *types.ContainerConfig) !*container.Container {
        var container_config = container.ContainerConfig{
            .allocator = self.allocator,
            .id = try self.allocator.dupe(u8, config.id),
            .name = try self.allocator.dupe(u8, config.name),
            .image = try self.allocator.dupe(u8, config.image),
            .command = try self.allocator.dupe([]const u8, config.command),
            .env = try self.allocator.dupe([]const u8, config.env),
            .working_dir = try self.allocator.dupe(u8, config.working_dir),
            .user = try self.allocator.dupe(u8, config.user),
            .type = undefined, // Will be set by createContainer
        };

        return try container.createContainer(self.allocator, self.config, container_config);
    }
};
