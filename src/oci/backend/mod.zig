// Backend module for OCI commands
// This module provides the backend plugin system for OCI container operations

pub const plugin = @import("plugin.zig");
pub const manager = @import("manager.zig");
pub const crun = @import("crun.zig");
pub const proxmox_lxc = @import("proxmox_lxc.zig");
pub const proxmox_vm = @import("proxmox_vm.zig");
pub const bfc = @import("bfc.zig");

// Re-export commonly used types
pub const BackendType = plugin.BackendType;
pub const ContainerState = plugin.ContainerState;
pub const ContainerInfo = plugin.ContainerInfo;
pub const BackendPlugin = plugin.BackendPlugin;
pub const BackendRegistry = plugin.BackendRegistry;
pub const BackendManager = manager.BackendManager;
pub const BackendError = plugin.BackendError;
