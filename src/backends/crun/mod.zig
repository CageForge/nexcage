/// Crun backend module
pub const driver = @import("driver.zig");
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

// Feature flag for libcrun ABI (may require systemd and proper linking)
// Set USE_LIBCRUN_ABI=false to use CLI driver instead
pub const USE_LIBCRUN_ABI = @import("builtin").mode == .Debug; // Use ABI in Debug, CLI in Release for now

pub const CrunDriver = if (USE_LIBCRUN_ABI) libcrun_driver.CrunDriver else driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based
pub const CrunDriverCli = driver.CrunDriver; // CLI-based fallback