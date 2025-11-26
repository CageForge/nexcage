/// Version information module
/// Provides access to build-time version information
/// Note: This module is included in the core module which has build_options available

/// Get application version from build options
pub fn getVersion() []const u8 {
    // Import build_options at function scope to avoid module-level conflicts
    const build_options = @import("build_options");
    return build_options.app_version;
}

