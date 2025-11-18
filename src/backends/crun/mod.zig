/// Crun backend module
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

const feature_options = @import("feature_options");

comptime {
    if (!feature_options.libcrun_abi_requested) {
        @compileError("libcrun CLI backend has been removed. Rebuild with -Denable-libcrun-abi=true to use the crun backend.");
    }
    if (!feature_options.libsystemd_available or !feature_options.libcrun_abi_active) {
        @compileError("libsystemd development files are required for the libcrun ABI backend.");
    }
}

pub const LIBCRUN_ABI_REQUESTED = feature_options.libcrun_abi_requested;
pub const LIBSYSTEMD_AVAILABLE = feature_options.libsystemd_available;
pub const USE_LIBCRUN_ABI = feature_options.libcrun_abi_active;

pub const CrunDriver = libcrun_driver.CrunDriver;
