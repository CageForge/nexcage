const std = @import("std");
const spec_mod = @import("spec.zig");
const types = @import("types");
const container = @import("container.zig");

pub const spec = spec_mod;
pub const Process = types.Process;
pub const User = types.User;
pub const Capabilities = types.Capabilities;
pub const RlimitType = types.RlimitType;
pub const Rlimit = types.Rlimit;
pub const Hook = types.Hook;
pub const Hooks = types.Hooks;

pub const create = @import("create.zig");
pub const start = @import("start.zig");
pub const state = @import("state.zig");
pub const kill = @import("kill.zig");
pub const delete = @import("delete.zig");

pub const Spec = spec.Spec;
pub const Root = spec.Root;
pub const Mount = spec.Mount;
pub const LinuxSpec = spec.LinuxSpec;
pub const LinuxNamespace = spec.LinuxNamespace;
pub const LinuxDevice = spec.LinuxDevice;

pub const CreateOpts = create.CreateOpts;
pub const CreateError = create.CreateError;
pub const createContainer = create.create;

pub const ContainerState = state.ContainerState;
pub const getState = state.getState;

test {
    @import("std").testing.refAllDecls(@This());
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
