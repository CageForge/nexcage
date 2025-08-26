const std = @import("std");
const spec_mod = @import("spec.zig");
const types = @import("types");

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
pub const stop = @import("stop.zig");
pub const state = @import("state.zig");
pub const kill = @import("kill.zig");
pub const delete = @import("delete.zig");
pub const list = @import("list.zig");
pub const info = @import("info.zig");
pub const exec = @import("exec.zig");

// Runtime modules
pub const crun = @import("crun.zig");
pub const lxc = @import("lxc.zig");

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

// Export runtime types
pub const CrunManager = crun.CrunManager;
pub const CrunError = crun.CrunError;
pub const CrunContainerState = crun.ContainerState;
pub const ContainerStatus = crun.ContainerStatus;

pub const LXCManager = lxc.LXCManager;
pub const LXCError = lxc.LXCError;
pub const LXCContainerState = lxc.LXCContainerState;
pub const LXCContainerStatus = lxc.LXCContainerStatus;

test {
    @import("std").testing.refAllDecls(@This());
}
