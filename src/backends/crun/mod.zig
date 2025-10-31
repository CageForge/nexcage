/// Crun backend module
pub const driver = @import("driver.zig");
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

// Feature flag for libcrun ABI (may require systemd and proper linking)
// Set USE_LIBCRUN_ABI=false to use CLI driver instead
// Note: libcrun/systemd may not be available in all CI environments
// Use CLI driver as default to ensure portability
pub const USE_LIBCRUN_ABI = false; // Default to CLI driver for portability (can be enabled when libcrun is available)

pub const CrunDriver = if (USE_LIBCRUN_ABI) libcrun_driver.CrunDriver else driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based
pub const CrunDriverCli = driver.CrunDriver; // CLI-based fallback