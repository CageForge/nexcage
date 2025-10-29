## Sprint 6.5 Progress

## 2025-10-29: Fixed Create Command Segfault (PR #128)

### Problem Identified
- **Critical segfault** occurred during `create` command execution when logger was invoked
- Segfault happened specifically on second `logger.info()` call
- Root cause: Logger's allocator became invalid between calls
- File.Writer usage was incompatible with Zig 0.15.1

### Solution Implemented
1. **Logger Allocator Fix**:
   - Changed logger to use `std.heap.page_allocator` for all allocations
   - This ensures allocator remains valid throughout execution
   - Fixes segfault that occurred when logger tried to use invalid allocator

2. **File Storage Fix**:
   - Changed `LogContext` to store `File` directly instead of `Writer`
   - Updated to use `file.writeAll()` instead of `writer.file.writeAll()`
   - Fixes Zig 0.15.1 compatibility issues

3. **Comprehensive Debug Logging**:
   - Added extensive debug output throughout create command flow
   - Debug logging in router, driver, and logger functions
   - Helps diagnose issues in production

4. **Error Handling Improvements**:
   - ZFS dataset creation errors now return null and continue without ZFS
   - Better error messages for debugging

### Files Changed
- `src/core/logging.zig`: Fixed logger allocator, File storage, page_allocator usage
- `src/main.zig`: Fixed logger initialization (removed stack buffer)
- `src/backends/proxmox-lxc/driver.zig`: Added debug logging, improved ZFS error handling
- `src/cli/router.zig`: Added debug logging, restored logger usage
- `src/cli/create.zig`: Enhanced debug logging

### Testing Results
- ✅ **No more segfault** when logger.info() is called
- ✅ Create command execution progresses successfully to pct create
- ✅ Logger works correctly throughout execution
- ✅ ZFS errors handled gracefully (continues without ZFS if pool doesn't exist)
- ✅ Tested on Proxmox server `mgr.cp.if.ua`

### Time Spent
- Diagnosis: ~2 hours
- Fix implementation: ~1 hour
- Testing: ~30 minutes
- **Total: ~3.5 hours**

### PR
- **PR #128**: [fix: Resolve segfault in create command caused by logger allocator](https://github.com/CageForge/nexcage/pull/128)
- Branch: `fix/create-segfault-logger`
- Status: Ready for review

---

# Sprint 6.5 Progress — Full Modular Refactor

### 2025-10-14
- Created `Roadmap/SPRINT_6.5_PLAN.md`.
- Fixed build by removing nonexistent `oci` module usage:
  - Deleted `src/oci/mod.zig` and removed references from code/build.
  - Cleaned `src/integrations/mod.zig` exports (removed `nfs`).
- Verified `zig build` succeeds on Zig 0.15.1.

- Centralized release version management:
  - Added `VERSION` file and build options wiring.
  - Replaced hardcoded versions in `src/main.zig` and CLI.
  - Added `scripts/bump_version.sh` and CI workflow `version-check.yml`.
  - Local CI script `scripts/ci/check_version.sh` validates version embedding.
  - Added auto-release workflow `.github/workflows/release.yml` (tag+release on VERSION change).

Time spent: 1.7h (planning: 0.4h, build fixes: 0.3h, version system + CI: 1.0h)


### 2025-10-29
- Security/validation integration and memory-safety pass:
  - Exported `core.validation` from `src/core/mod.zig`.
  - Fixed `src/core/validation.zig` self-import and aligned errors with `core.Error` variants (use `ValidationError`).
  - Integrated validation in `src/backends/crun/driver.zig` via module export.
  - Verified successful build on Zig 0.15.1 (`zig build`).

Time spent: 0.6h (debug: 0.3h, fixes: 0.2h, build+verification: 0.1h)

### 2025-10-29 (cont.)
- Enforce CLI-only Proxmox interaction policy:
  - Removed `proxmox-api` module wiring from `build.zig` (no API usage at runtime).
  - Verified `zig build` succeeds after removal.

Time spent: +0.2h (cleanup: 0.2h)

### 2025-10-29 (merge)
- Merged PR 123 (plugin system rewrite) into PR 122 branch; build green.
- Prepared PR 122 for merge to main (threads resolved, comments added).

Time spent: +0.4h (merge+verify: 0.3h, comms: 0.1h)

### 2025-10-29 (smoke test)
- Ran smoke tests on Proxmox mgr.cp.if.ua via scripts/proxmox_only_test.sh:
  - Infrastructure checks: PASS (build, copy, SSH, PVE env, storage, network)
  - ReleaseFast binary deployed (Debug had memory leak detections)
  - **Issue**: Segmentation fault on command execution (version, list)
  - Success rate: 36% (16/44 passed; negative tests OK, functional tests fail)
  - Needs investigation: segfault likely due to runtime/memory/config issue

Time spent: +0.5h (test run: 0.3h, debug: 0.2h)

### 2025-10-29
- Fixed segmentation fault in version and list commands:
  - Root cause: CommandInterface.execute/help/validate function pointers didn't pass `self` (ctx)
  - Solution: Updated CommandInterface to accept `self: *CommandInterface` as first parameter
  - Created wrapper functions in registry.zig that extract ctx from CommandInterface and pass as self to concrete commands
  - Fixed error set compatibility using @errorCast for proper error propagation
  - Fixed health_check.zig help() and validate() signatures to match interface
  - Replaced std.debug.print with stdout.writeAll in version.zig for Release mode compatibility
  - Verified version and list commands work on both local and Proxmox server (mgr.cp.if.ua)
  
- Created GitHub issue #125 for state command implementation:
  - Command to retrieve container state/status information
  - Integration with proxmox-lxc backend via pct status/list
  
Time spent: 2.5h (issue creation: 0.1h, segfault debug+fix: 2.0h, testing: 0.4h)

### 2025-10-29 (state command)
- Implemented OCI-compliant `state` command:
  - Created `src/cli/state.zig` following same pattern as `start`, `stop` commands
  - Command uses router for backend routing and queries backend via `list()` method
  - Maps backend status to OCI status values (created|running|stopped|paused)
  - Outputs OCI-compatible JSON with ociVersion, id, status, pid, bundle, annotations
  - Registered command in `src/cli/registry.zig`
  - Added `.state` operation to `router.Operation` enum
  - Added `.state` to `Command` enum in `types.zig`
  - Updated `parseCommand` and `parseRuntimeOptions` in `main.zig` to handle state command
  - Supports proxmox-lxc backend (primary), fallback for crun/runc/vm
  - Fixed logger crash by adding error handling in `core/logging.zig` (catch allocator failures)
  - Tested successfully on Proxmox server `mgr.cp.if.ua`:
    - Command `state 101` returns correct OCI-compatible JSON with status "stopped"
    - Command `state 501` returns correct OCI-compatible JSON
    - Command `state 999` correctly identifies existing container
    - Help command works correctly
    - Logger no longer crashes after adding error handling to allocator failures
  
- Known issue: None (logger fix resolved crash issue)

Time spent: 2.0h (implementation: 1.0h, testing+debugging: 0.5h, Proxmox testing: 0.5h)

### 2025-10-29: Fixed ZFS Pool and Dataset Validation (WIP)

#### Problem Identified
- **Missing validation** before creating ZFS datasets during container creation
- Container creation attempted to create datasets on non-existent pools (e.g., "tank" pool not found)
- No check if dataset already exists before creation
- Parent datasets not created automatically when missing

#### Solution Implemented
1. **Pool Existence Check**:
   - Added `poolExists()` function to verify ZFS pool exists before creating datasets
   - Extracts pool name from config (e.g., "tank" from "tank/containers")
   - Uses `zpool list` to verify pool exists
   - Returns `null` from `createContainerDataset()` if pool doesn't exist (continues without ZFS)

2. **Dataset Existence Check**:
   - Added `datasetExists()` function to check if dataset already exists
   - Uses `zfs list` to verify dataset existence
   - Returns existing dataset name if found, preventing duplicate creation

3. **Parent Dataset Creation**:
   - Added `getParentDataset()` function to extract parent path from full dataset path
   - Automatically creates parent dataset with `zfs create -p` if missing
   - Handles nested dataset paths (e.g., creates "tank/containers" before "tank/containers/container-vmid")

4. **Improved Dataset Path Handling**:
   - Extracts pool name correctly from config (supports both "pool" and "pool/path" formats)
   - Uses base path from config if it contains a path separator
   - Falls back to "pool_name/containers" if config only specifies pool name

#### Files Changed
- `src/backends/proxmox-lxc/driver.zig`:
  - Added `poolExists()` function (lines 101-121)
  - Added `datasetExists()` function (lines 123-133)
  - Added `getParentDataset()` function (lines 135-143)
  - Enhanced `createContainerDataset()` with validation checks (lines 209-268)

#### Testing Status
- ✅ Compilation successful
- ⏳ Testing on Proxmox server pending

#### Time Spent
- Implementation: ~1.5h
- Testing: pending

#### Branch
- Branch: `fix/zfs-validation`
- Status: Ready for testing

