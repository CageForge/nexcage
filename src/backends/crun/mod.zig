/// Crun backend module
pub const driver = @import("driver.zig");
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

const build_options = @import("feature_options");

pub const LIBCRUN_ABI_REQUESTED = build_options.libcrun_abi_requested;
pub const LIBSYSTEMD_AVAILABLE = build_options.libsystemd_available;
pub const USE_LIBCRUN_ABI = build_options.libcrun_abi_active;

pub const CrunDriver = if (USE_LIBCRUN_ABI) libcrun_driver.CrunDriver else driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based
pub const CrunDriverCli = driver.CrunDriver; // CLI-based fallback
