/// Crun backend module (ABI only)
pub const libcrun_driver = @import("libcrun_driver.zig");
pub const libcrun_ffi = @import("libcrun_ffi.zig");

// Expose ABI-based driver only
pub const CrunDriver = libcrun_driver.CrunDriver;
pub const CrunDriverLibcrun = libcrun_driver.CrunDriver; // libcrun ABI-based
pub const CrunDriverCli = driver.CrunDriver; // CLI-based fallback