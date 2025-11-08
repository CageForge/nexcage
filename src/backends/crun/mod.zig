/// Crun backend module
const build_options = @import("build_options");

pub const driver = @import("driver.zig");
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

// Feature flag for libcrun ABI (controlled by build option)
// Use -Denable-libcrun-abi=true to enable libcrun ABI driver
// Note: libcrun/systemd may not be available in all CI environments
// CLI driver is default to ensure portability
pub const USE_LIBCRUN_ABI = build_options.enable_libcrun_abi;

pub const CrunDriver = if (USE_LIBCRUN_ABI) libcrun_driver.CrunDriver else driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based
pub const CrunDriverCli = driver.CrunDriver; // CLI-based fallback