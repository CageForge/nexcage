/// Backends module exports
const build_options = @import("build_options");

// Conditionally export backends based on build flags
pub const proxmox_lxc = if (build_options.enable_backend_proxmox_lxc) @import("proxmox-lxc/mod.zig") else struct {};
pub const proxmox_vm = if (build_options.enable_backend_proxmox_vm) @import("proxmox-vm/mod.zig") else struct {};
pub const crun = if (build_options.enable_backend_crun) @import("crun/mod.zig") else struct {};
pub const runc = if (build_options.enable_backend_runc) @import("runc/mod.zig") else struct {};

// Helper functions to check if backends are enabled
pub inline fn isProxmoxLxcEnabled() bool {
    return build_options.enable_backend_proxmox_lxc;
}

pub inline fn isProxmoxVmEnabled() bool {
    return build_options.enable_backend_proxmox_vm;
}

pub inline fn isCrunEnabled() bool {
    return build_options.enable_backend_crun;
}

pub inline fn isRuncEnabled() bool {
    return build_options.enable_backend_runc;
}
