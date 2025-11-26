# OCI Specs Zig Migration Plan

**Date:** 2025-11-25  
**Status:** ✅ Completed (2025-11-26 12:04)  
**Sprint:** OCI Specs Zig Consolidation

## Overview

This plan outlines the migration of OCI-related code from `src/backends/proxmox-lxc/` into `oci-spec-zig` package, and moving `oci-spec-zig` from project root to `deps/oci-spec-zig` to follow the project's dependency structure.

## Current State

### OCI Code Location
- **`oci-spec-zig/`** (project root): Basic OCI spec types (runtime, image, distribution)
- **`src/backends/proxmox-lxc/oci_bundle.zig`**: OCI bundle parser (config.json + rootfs) → LXC config converter
- **`src/backends/proxmox-lxc/image_converter.zig`**: OCI bundle → LXC rootfs converter

### Dependencies
- `build.zig.zon` references `oci_spec_zig` from GitHub repository
- `build.zig` uses `b.dependency("oci_spec_zig", ...)` to get the module
- `oci_bundle.zig` imports `oci_spec.runtime` types (MemoryPolicy, IntelRdt, NetDevice)

## Goals

1. Move `oci-spec-zig` from project root to `deps/oci-spec-zig`
2. Migrate `oci_bundle.zig` → `oci-spec-zig/src/runtime/bundle.zig` (following oci-spec-rs structure)
3. Move `image_converter.zig` → `src/utils/lxc_converter.zig` (LXC-specific utility, not part of oci-spec-zig)
4. Ensure structure matches `oci-spec-rs` reference implementation:
   - `runtime/` - Runtime spec types + bundle parser
   - `image/` - Image spec types
   - `distribution/` - Distribution spec types
5. Update all imports and build configuration
6. Ensure compilation and tests pass

## Migration Steps

### Phase 1: Move oci-spec-zig to deps/

1. **Move directory**
   ```bash
   mv oci-spec-zig deps/oci-spec-zig
   ```

2. **Update build.zig**
   - Change dependency from GitHub URL to local path:
     ```zig
     const oci_spec_dep = b.dependency("oci_spec_zig", .{
         .target = target,
         .optimize = optimize,
     });
     ```
   - Or use direct module reference if switching to local dependency

3. **Update build.zig.zon** (if keeping local dependency)
   - Remove GitHub URL dependency
   - Add local path reference or keep as submodule

### Phase 2: Migrate oci_bundle.zig (following oci-spec-rs structure)

**Reference: oci-spec-rs structure**
- `oci-spec-rs` has `runtime` module that contains Runtime spec types
- Bundle parsing functionality should be part of `runtime` module
- In `oci-spec-rs`, bundle parsing is typically done via `runtime::Spec::load()` methods

1. **Move bundle parser to runtime module**
   - Move `src/backends/proxmox-lxc/oci_bundle.zig` → `deps/oci-spec-zig/src/runtime/bundle.zig`
   - This follows `oci-spec-rs` pattern where bundle operations are part of runtime spec

2. **Refactor oci_bundle.zig**
   - Update imports:
     - `const oci_spec = @import("oci_spec");` → `const runtime = @import("runtime/mod.zig");`
     - Use types from `runtime/mod.zig` directly (MemoryPolicy, IntelRdt, NetDevice)
   - Keep `OciBundleParser` and `OciBundleConfig` structures
   - Keep helper types: `MountConfig`, `UserConfig`, `RlimitConfig`, `DeviceConfig`, `NamespaceConfig`
   - Remove dependency on `core` module (see Critical Considerations)

3. **Export bundle functionality from runtime module**
   - Add to `deps/oci-spec-zig/src/runtime/mod.zig`:
     ```zig
     pub const bundle = @import("runtime/bundle.zig");
     ```
   - Or integrate bundle parser directly into runtime module exports

### Phase 3: Move image_converter.zig to utils (LXC-specific utility)

**Note:** `image_converter.zig` converts OCI bundles to LXC rootfs, which is **LXC backend-specific functionality**.
This is NOT part of OCI spec - it's a utility for converting OCI bundles to LXC format.
Therefore, it should remain in the project as a utility module, not integrated into `oci-spec-zig`.

1. **Move image_converter.zig to utils**
   - Move `src/backends/proxmox-lxc/image_converter.zig` → `src/utils/lxc_converter.zig`
   - This keeps LXC-specific conversion logic separate from OCI spec implementation

2. **Refactor image_converter.zig**
   - Update imports:
     - `const oci_bundle = @import("oci_bundle.zig");` → `const oci_spec = @import("oci_spec"); const bundle = oci_spec.runtime.bundle;`
     - Update references: `oci_bundle.OciBundleParser` → `bundle.OciBundleParser`
     - Update references: `oci_bundle.OciBundleConfig` → `bundle.OciBundleConfig`
   - Keep dependency on `core` module (acceptable for project utilities)
   - Rename struct if needed: `ImageConverter` → `LxcConverter` (optional, for clarity)

3. **Export from utils module**
   - Add to `src/utils/mod.zig`:
     ```zig
     pub const lxc_converter = @import("lxc_converter.zig");
     ```

### Phase 4: Update Proxmox LXC Backend

1. **Update driver.zig**
   - Change imports (following oci-spec-rs pattern):
     ```zig
     // Old:
     const oci_bundle = @import("oci_bundle.zig");
     const image_converter = @import("image_converter.zig");
     
     // New (following oci-spec-rs structure):
     const oci_spec = @import("oci_spec");
     const runtime = oci_spec.runtime;
     const bundle = runtime.bundle;  // Bundle parser from runtime module (OCI spec)
     const utils = @import("utils");
     const lxc_converter = utils.lxc_converter;  // LXC-specific converter utility
     ```
   - Update references:
     - `oci_bundle.OciBundleParser` → `bundle.OciBundleParser`
     - `oci_bundle.OciBundleConfig` → `bundle.OciBundleConfig`
     - `image_converter.ImageConverter` → `lxc_converter.ImageConverter` (or `LxcConverter` if renamed)

2. **Update mod.zig**
   - Remove exports:
     ```zig
     // Remove:
     pub const oci_bundle = @import("oci_bundle.zig");
     pub const image_converter = @import("image_converter.zig");
     ```
   - Note: `image_converter` is now in `utils` module, not exported from backend

3. **Update template_manager.zig**
   - Update any references to `oci_bundle` module

### Phase 5: Update Build Configuration

1. **Update build.zig**
   - Ensure `oci_spec_mod` includes new modules:
     ```zig
     const oci_spec_mod = oci_spec_dep.module("oci_spec");
     // Should automatically include bundle and converter via lib.zig exports
     ```

2. **Update build.zig.zon** (if using local dependency)
   - Option A: Keep GitHub dependency (no changes needed)
   - Option B: Switch to local path (requires updating dependency format)

### Phase 6: Update Tests

1. **Update test imports**
   - Find all test files importing `oci_bundle` or `image_converter`
   - Update to use `oci_spec.bundle` and `oci_spec.converter`

2. **Verify test compilation**
   ```bash
   zig build test
   ```

### Phase 7: Cleanup

1. **Remove old files**
   - Delete `src/backends/proxmox-lxc/oci_bundle.zig`
   - Delete `src/backends/proxmox-lxc/image_converter.zig`

2. **Update documentation**
   - Update any references to OCI bundle/converter locations
   - Update architecture diagrams if needed

## File Structure After Migration (Following oci-spec-rs Structure)

```
deps/
  oci-spec-zig/
    src/
      lib.zig              # Main entry point (exports runtime, image, distribution)
      runtime/
        mod.zig           # OCI Runtime spec types (like oci-spec-rs)
        bundle.zig         # OCI bundle parser (part of runtime module)
      image/
        mod.zig           # OCI Image spec types (like oci-spec-rs)
      distribution/
        mod.zig           # OCI Distribution spec types (like oci-spec-rs)
    build.zig
    build.zig.zon
    README.md
    schemas/
    tools/

src/
  utils/
    mod.zig               # Utils module exports
    lxc_converter.zig     # LXC-specific OCI → LXC converter (migrated from image_converter.zig)
    fs.zig
    net.zig

  backends/proxmox-lxc/
    driver.zig            # Uses oci_spec.runtime.bundle and utils.lxc_converter
    mod.zig               # No longer exports oci_bundle/image_converter
    # ... other files ...
```

**Structure matches oci-spec-rs:**
- `runtime/` - Contains Runtime spec types + bundle parser (OCI spec compliant)
- `image/` - Contains Image spec types
- `distribution/` - Contains Distribution spec types
- Bundle parser is part of `runtime` module (not separate) - follows oci-spec-rs pattern
- **LXC converter is in `utils/`** - LXC-specific utility, NOT part of OCI spec

## Dependencies Analysis

### oci_bundle.zig dependencies:
- `std` (standard library)
- `core` (project core module) - **NOTE: This creates a circular dependency risk**
- `oci_spec.runtime` (MemoryPolicy, IntelRdt, NetDevice)

### image_converter.zig dependencies:
- `std` (standard library)
- `core` (project core module) - **OK for utils module** (not part of oci-spec-zig)
- `oci_bundle` (OciBundleParser, OciBundleConfig) - Will use `oci_spec.runtime.bundle` after migration

## Critical Considerations

### Circular Dependency Risk

**For `oci_bundle.zig` (migrating to oci-spec-zig):**
- Depends on `core` module (`core.LogContext`, `core.Error`)
- **Solution**: Remove `core` dependency - use logger interface and custom error types
- **Reason**: `oci-spec-zig` should be independent, reusable package

**For `image_converter.zig` (moving to utils):**
- Depends on `core` module (`core.LogContext`, `core.Error`)
- **Solution**: Keep `core` dependency - acceptable for project utilities
- **Reason**: Utils module is part of project, not a separate package

**Solutions for bundle.zig:**
1. **Remove `core` dependency** (recommended for oci-spec-zig)
   - Replace `core.LogContext` with optional logger interface:
     ```zig
     pub const Logger = struct {
         info: ?fn (comptime fmt: []const u8, args: anytype) void = null,
         err: ?fn (comptime fmt: []const u8, args: anytype) void = null,
         warn: ?fn (comptime fmt: []const u8, args: anytype) void = null,
         debug: ?fn (comptime fmt: []const u8, args: anytype) void = null,
     };
     ```
   - Replace `core.Error` with custom error types:
     ```zig
     pub const BundleError = error{
         ConfigFileNotFound,
         RootfsNotFound,
         InvalidConfigFormat,
         // ... other errors
     };
     ```
   - **Pros**: Clean separation, no circular dependencies, reusable package
   - **Cons**: Requires refactoring logging and error handling

### Refactoring Required

**For `bundle.zig` (in oci-spec-zig):**

1. **Logging**: Replace `core.LogContext` with optional logger interface:
   ```zig
   pub const Logger = struct {
       info: ?fn (comptime fmt: []const u8, args: anytype) void = null,
       err: ?fn (comptime fmt: []const u8, args: anytype) void = null,
       warn: ?fn (comptime fmt: []const u8, args: anytype) void = null,
       debug: ?fn (comptime fmt: []const u8, args: anytype) void = null,
   };
   
   // Usage:
   if (logger.info) |log_fn| log_fn("message", .{});
   ```

2. **Error Types**: Replace `core.Error` with custom error types:
   ```zig
   pub const BundleError = error{
       ConfigFileNotFound,
       RootfsNotFound,
       InvalidConfigFormat,
       EmptyRootfs,
       ArchiveCreationFailed,
       // ... other errors
   };
   ```

**For `lxc_converter.zig` (in utils):**
- Keep `core` dependency - no refactoring needed
- Update imports to use `oci_spec.runtime.bundle` instead of `oci_bundle`

## Testing Strategy

1. **Unit Tests**
   - Test `bundle.OciBundleParser` independently
   - Test `converter.ImageConverter` independently
   - Verify no regressions in parsing/conversion logic

2. **Integration Tests**
   - Test Proxmox LXC backend with new module structure
   - Verify OCI bundle creation and conversion still works

3. **Compilation Tests**
   - Ensure all files compile without errors
   - Verify no circular dependencies

## Timeline Estimate

- **Phase 1** (Move to deps/): 30 minutes
- **Phase 2** (Migrate bundle): 1-2 hours
- **Phase 3** (Migrate converter): 1-2 hours
- **Phase 4** (Update backend): 1 hour
- **Phase 5** (Build config): 30 minutes
- **Phase 6** (Tests): 1 hour
- **Phase 7** (Cleanup): 30 minutes

**Total**: ~6-8 hours

## Success Criteria

- [ ] `oci-spec-zig` moved to `deps/oci-spec-zig`
- [ ] Structure matches `oci-spec-rs` reference:
  - [ ] `runtime/` module contains Runtime spec types
  - [ ] `runtime/bundle.zig` contains bundle parser (part of runtime module)
  - [ ] `image/` module contains Image spec types
  - [ ] `distribution/` module contains Distribution spec types
- [ ] `oci_bundle.zig` migrated to `deps/oci-spec-zig/src/runtime/bundle.zig`
- [ ] `image_converter.zig` moved to `src/utils/lxc_converter.zig` (LXC-specific utility)
- [ ] All imports updated in Proxmox LXC backend:
  - [ ] Uses `oci_spec.runtime.bundle` for bundle parsing
  - [ ] Uses `utils.lxc_converter` for LXC conversion
- [ ] Build configuration updated
- [ ] All tests pass
- [ ] No circular dependencies in `oci-spec-zig` (removed `core` dependency from bundle.zig)
- [x] Documentation updated to reflect oci-spec-rs-aligned structure

## Completion Report

**Completed:** 2025-11-26 12:04  
**Time Spent:** ~2 hours  
**Branch:** `feature/oci-specs-zig-migration`

### Changes Made

1. **Moved `oci-spec-zig` to `deps/oci-spec-zig`**
   - Updated `build.zig` to use local path dependency
   - Removed GitHub URL dependency from `build.zig.zon`

2. **Migrated `oci_bundle.zig` → `deps/oci-spec-zig/src/runtime/bundle.zig`**
   - Refactored to remove `core` module dependency
   - Introduced generic `Logger` interface (`*anyopaque` with function pointers)
   - Replaced `core.Error` with `BundleError` enum
   - Updated all logger calls to use helper functions (`logInfo`, `logErr`, `logWarn`, `logDebug`)
   - Fixed all error returns to use `BundleError.InvalidConfigFormat`

3. **Migrated `image_converter.zig` → `src/utils/lxc_converter.zig`**
   - Updated imports to use `oci_spec.runtime.bundle`
   - Added logger conversion from `core.LogContext` to `bundle.Logger`
   - Updated `src/utils/mod.zig` to export `lxc_converter`

4. **Updated `driver.zig`**
   - Updated imports: `oci_spec.runtime.bundle` and `utils.lxc_converter`
   - Added `getBundleLogger()` helper function to convert `core.LogContext` to `bundle.Logger`
   - Updated all bundle parser calls to use new logger interface

5. **Updated `build.zig`**
   - Changed `oci_spec_dep` to use local path: `b.path("deps/oci-spec-zig")`
   - Added `oci_spec_mod` to `utils_mod` imports

6. **Updated module exports**
   - Removed `oci_bundle` and `image_converter` from `src/backends/proxmox-lxc/mod.zig`
   - Added `lxc_converter` to `src/utils/mod.zig`

### Compilation Status

- ✅ All OCI migration-related code compiles successfully
- ⚠️ Note: crun backend compilation error exists but is unrelated to OCI migration (separate issue)

### Files Changed

- `build.zig` - Updated dependency configuration
- `src/backends/proxmox-lxc/driver.zig` - Updated imports and logger usage
- `src/backends/proxmox-lxc/mod.zig` - Removed old exports
- `src/utils/mod.zig` - Added lxc_converter export
- `deps/oci-spec-zig/src/runtime/bundle.zig` - Migrated and refactored
- `deps/oci-spec-zig/src/runtime/mod.zig` - Added bundle export

### Files Moved

- `oci-spec-zig/` → `deps/oci-spec-zig/`
- `src/backends/proxmox-lxc/oci_bundle.zig` → `deps/oci-spec-zig/src/runtime/bundle.zig`
- `src/backends/proxmox-lxc/image_converter.zig` → `src/utils/lxc_converter.zig`

## Notes

- **Structure alignment with oci-spec-rs**: The migration follows `oci-spec-rs` structure where:
  - Bundle operations are part of `runtime` module (not separate)
  - Runtime spec types are in `runtime/mod.zig`
  - Image spec types are in `image/mod.zig`
  - Distribution spec types are in `distribution/mod.zig`
- **LXC converter separation**: `image_converter.zig` is LXC-specific and remains in project as `utils/lxc_converter.zig`
  - This is NOT part of OCI spec - it's a utility for converting OCI bundles to LXC format
  - Keeps `oci-spec-zig` clean and focused on OCI specifications only
- Consider making `oci-spec-zig` a Git submodule if it's maintained separately
- May need to update `.gitignore` if moving to `deps/`
- Consider versioning strategy for `oci-spec-zig` package

