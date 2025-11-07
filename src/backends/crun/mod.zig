/// Crun backend module
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

const build_options = @import("feature_options");

comptime {
    if (!build_options.libcrun_abi_requested) {
        @compileError("libcrun CLI backend has been removed. Rebuild with -Denable-libcrun-abi=true to use the crun backend.");
    }
    if (!build_options.libsystemd_available or !build_options.libcrun_abi_active) {
        @compileError("libsystemd development files are required for the libcrun ABI backend.");
    }
}

pub const LIBCRUN_ABI_REQUESTED = build_options.libcrun_abi_requested;
pub const LIBSYSTEMD_AVAILABLE = build_options.libsystemd_available;
pub const USE_LIBCRUN_ABI = build_options.libcrun_abi_active;

pub const CrunDriver = libcrun_driver.CrunDriver;
