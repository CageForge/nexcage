/// Backends module exports
const build_options = @import("build_options");

// Proxmox LXC is always built; crun only when its build flag is on.
pub const proxmox_lxc = @import("proxmox-lxc/mod.zig");
pub const crun = if (build_options.enable_backend_crun) @import("crun/mod.zig") else struct {};

// Whether the crun backend is compiled in
pub inline fn isCrunEnabled() bool {
    return build_options.enable_backend_crun;
}
