//! Aggregate root for tests that import source files by relative path.
//!
//! Zig scopes a module to the directory of its root source file, so a test in
//! tests/ that does @import("../src/oci/spec.zig") escapes its own module and
//! the compiler refuses it. Rooting those tests here — at the repository root
//! — puts tests/ and src/ both inside the module, and the same relative
//! imports resolve.
//!
//! Only the twelve files that actually escape are listed. Everything else
//! keeps its own addTest in build.zig, so a broken file takes down only
//! itself and the failure names it. Bringing all 46 under one root would
//! restore exactly the problem that hid the suite for months: the first
//! broken import hides every result behind it.
//!
//! src/cli/example_usage.zig is deliberately absent: it needs @import("core"),
//! and this module has no named imports for the reason above. It keeps its own
//! addTest, where core is available, and fails there by name.
//!
//! When one of these is fixed to import through the named modules (core,
//! backends, cli, utils, integrations) instead of relative paths, delete its
//! line here — it will get an individual verdict again.

comptime {
    _ = @import("tests/integration/create_template_integration_test.zig");
    _ = @import("tests/integration/end_to_end_test.zig");
    _ = @import("tests/integration/test_create_with_pull.zig");
    _ = @import("tests/memory/memory_leak_test.zig");
    _ = @import("tests/oci_bundle_test.zig");
    _ = @import("tests/oci/image_manager_test.zig");
    _ = @import("tests/oci_mapping_test.zig");
    _ = @import("tests/oci_state_manager_test.zig");
    _ = @import("tests/state_manager_test.zig");
    _ = @import("tests/test_oci_spec.zig");
    _ = @import("tests/vmid_manager_test.zig");
}
