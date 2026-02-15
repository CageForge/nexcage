/// Backends module exports
const build_options = @import("build_options");

// Export Proxmox LXC backend
pub const proxmox_lxc = @import("proxmox-lxc/mod.zig");

// Helper functions to check if backends are enabled
pub inline fn isProxmoxLxcEnabled() bool {
    return true;
}
