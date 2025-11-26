/// Integrations module exports
const build_options = @import("build_options");

// Conditionally export integrations based on build flags
pub const proxmox_api = if (build_options.enable_proxmox_api) @import("proxmox-api/mod.zig") else struct {};
pub const bfc = if (build_options.enable_bfc) @import("bfc/mod.zig") else struct {};
pub const zfs = if (build_options.enable_zfs) @import("zfs/mod.zig") else struct {};

// Helper functions to check if integrations are enabled
pub inline fn isProxmoxApiEnabled() bool {
    return build_options.enable_proxmox_api;
}

pub inline fn isBfcEnabled() bool {
    return build_options.enable_bfc;
}

pub inline fn isZfsEnabled() bool {
    return build_options.enable_zfs;
}
