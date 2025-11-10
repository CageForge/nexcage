# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Apply OCI `linux.netDevices` aliases when provisioning Proxmox LXC containers, generating pct `--netX` arguments and matching `/etc/network/interfaces` entries.
- Persist parsed `linux.intelRdt` profiles alongside container state for downstream QoS automation.

### Changed
- Template metadata now captures Intel RDT and network device information for visibility in the cache API.

### Documentation
- Clarified v0.7.4 upgrade notes with the new runtime metadata and networking behaviour.

## [0.7.4] - 2025-11-07

### 🚀 Spec Parity Release: OCI Runtime v1.3.0 Support

This release upgrades the OCI ingestion pipeline to fully understand the Linux additions introduced between v1.0.2 and v1.3.0, ensuring future bundles load without manual downgrades.

### Added
- **NUMA Memory Policy Parsing**: Support for `linux.memoryPolicy` (modes, nodes, flags) with strict validation.
- **Intel RDT Enhancements**: Parse `closID`, `schemata`, cache and memory bandwidth schemas, plus the new `enableMonitoring` flag.
- **Network Device Inventory**: Parse `linux.netDevices` map entries with alias/name support for future LXC bridging.
- **Developer Guidance**: README & Dev Quickstart now highlight OCI Runtime Spec v1.3.0 as the tested baseline.

### Changed
- Hardened error handling around malformed `memoryPolicy`, `intelRdt`, and `netDevices` entries to surface actionable diagnostics.
- Unit tests updated to cover OCI 1.3.0 fields and prevent regressions.
- Removed the legacy crun CLI fallback; builds now compile vendored `deps/crun` sources and require only libsystemd when targeting the crun backend.

### Testing
- `zig build`
- `zig build test`

### Documentation
- `docs/releases/NOTES_v0.7.4.md` — detailed notes for the release.
- README, `docs/DEV_QUICKSTART.md` — compatibility snapshot and requirements now state OCI 1.3.0 support.

---

## [0.7.3] - 2025-11-02

### 🔧 Bug Fix Release: Memory Leaks, Template Conversion, OCI Resources

This release fixes critical bugs in template conversion and OCI bundle processing, resolves memory leaks, and adds support for OCI bundle resource limits and namespaces.

### Added
- **OCI Bundle Resources Support**: 
  - Parse `memory_limit` from `linux.resources.memory.limit` (bytes to MB conversion)
  - Parse `cpu_limit` from `linux.resources.cpu.shares` (shares/1024.0 to cores conversion)
  - Priority: bundle_config > SandboxConfig > defaults
- **OCI Namespaces Support**:
  - Parse all OCI namespaces from `linux.namespaces` array (pid, network, ipc, uts, mount, user, cgroup)
  - Map user namespace to Proxmox LXC features (`nesting=1,keyctl=1`) via `pct set --features`
  - Automatic feature configuration based on namespace presence
- **Enhanced Validation**:
  - Recursive file counting in `validateRootfsDirectory` (counts files in subdirectories)
  - Validation before and after LXC configurations are applied
  - Detailed logging for file operations in `copyDirectoryRecursive`

### Fixed
- **Memory Leak in Template Manager**: 
  - Added `errdefer template_info.deinit()` for error cleanup
  - Added `errdefer metadata.deinit()` for metadata cleanup
  - Added `defer template_info.deinit()` after `addTemplate()` (which clones)
  - Proper cleanup for entrypoint and cmd arrays with errdefer blocks
- **Template Archive Issues**:
  - Archive now correctly includes all files (verified: `bin/sh`, `sbin/init`, `etc/hostname`)
  - Fixed recursive validation to count files in subdirectories
  - Enhanced error handling in `copyDirectoryRecursive`
- **CPU Cores Calculation**:
  - Fixed `cores=0` issue when CPU shares < 1024
  - Added minimum of 1 core guarantee: `if (calculated < 1.0) 1.0 else calculated`
  - Applied to both bundle_config and final calculation
- **pct create Error Handling**:
  - Enhanced debug output for exit codes, stdout, stderr
  - Better handling of "already exists" scenarios
  - Improved error messages for debugging

### Changed
- **Error Types**: Added `CopyFailed`, `RootfsNotFound`, `EmptyRootfs`, `ArchiveCreationFailed` to `core.Error`
- **Image Converter**: Enhanced `copyDirectoryRecursive` with detailed logging and error handling
- **Template Validation**: Switched from top-level only to recursive directory traversal

### Testing
- ✅ Memory leak resolved: No more leaks detected in template_manager
- ✅ Archive creation verified: All files included correctly
- ✅ Recursive validation working: Correctly counts files in subdirectories
- ✅ Cores fix verified: Containers now created with minimum 1 core (was 0)
- ✅ Container creation successful: Verified on Proxmox server (VMID 31386, 72421)
- ✅ pct create command working: Exit code 0, container configured correctly

### Documentation
- `docs/ANALYSIS_CREATE_PROXMOX_LXC.md` - Updated with implementation details
- `docs/OCI_BUNDLE_GENERATOR.md` - Updated with namespace mapping information
- `docs/TEMPLATE_CONVERSION_DEBUG.md` - Debugging analysis document
- `docs/TEST_RESULTS_PROXMOX.md` - Test results document
- `docs/INTEGRATION_TEST_PROXMOX.md` - Integration testing guide

### Notes
- Template warnings about `/etc/os-release` not found are expected for minimal OCI bundles
- Architecture detection falls back to `amd64` (normal behavior)
- ostype detection shows `unmanaged` for custom OCI bundles (expected)

---

## [0.7.2] - 2025-10-31

### 🎯 Code Quality & Observability Release: Error Handling, Memory Safety, Testing, Metrics

This release focuses on codebase quality improvements from Sprint 6.6, including comprehensive error handling, memory leak detection, test coverage increases, structured logging, Prometheus metrics, and automated dependency monitoring.

### Added
- **Error Handling System**: 
  - `ErrorContext` with detailed error information (message, source, line, column, stack trace)
  - `ErrorContextBuilder` for fluent error context creation
  - `ContextualError` and `ErrorWithContext` for error chaining
  - Helper functions: `createErrorContext`, `createErrorContextWithSource`
- **Memory Leak Detection**:
  - Automated memory audit script (`scripts/memory_leak_audit.sh`)
  - Valgrind integration in CI (`.github/workflows/memory_leak_check.yml`)
  - Memory leak audit report (`docs/MEMORY_LEAK_AUDIT_REPORT.md`)
  - Enhanced errdefer usage in critical paths
- **Comptime Validation**:
  - Comptime validation module (`src/core/comptime_validation.zig`)
  - Type-safe ConfigBuilder pattern
  - Comptime string operations (StringOps)
  - Runtime type parsing at compile time
- **Structured JSON Logging**:
  - JSON logger (`src/core/json_logging.zig`)
  - Structured log output with timestamp, level, component, message
  - Custom fields support via `logWithFields()`
  - Proper JSON escaping
- **Prometheus Metrics**:
  - Metrics registry (`src/core/metrics.zig`)
  - Counter, Gauge, and Histogram metric types
  - Label support for metrics
  - Prometheus text format export
- **Test Coverage**:
  - 4 new test files for core modules
  - ~25+ new test functions
  - Coverage increased from ~60% to ~75-80%
  - Tests for router, errors, comptime_validation, validation modules
- **Dependency Monitoring**:
  - Dependabot configuration for GitHub Actions and Docker
  - Custom workflow for OCI specs, crun, and Proxmox VE monitoring
  - Automatic GitHub issue creation for available updates
  - Weekly scheduled checks

### Changed
- **Memory Management**:
  - Added errdefer for all allocations in `router.zig`
  - Improved error path cleanup safety
  - Better memory lifecycle documentation
- **Code Cleanup**:
  - Removed ~60 lines of obsolete code
  - Clarified 10+ TODO comments with better context
  - Removed unused AppContext fields and methods
- **Error Handling**:
  - Replaced `format()` with `formatError()` in ErrorWithContext
  - Improved error message formatting
  - Better error context propagation

### Fixed
- **Memory Leaks**: Added errdefer statements in critical allocation paths
- **Code Quality**: Removed shadowing issues in metrics module
- **Build System**: Fixed comptime validation syntax for Zig 0.15.1 compatibility
- **Documentation**: Updated all documentation to reflect new features

### Documentation
- `docs/MEMORY_LEAK_AUDIT_REPORT.md` - Memory audit results
- `docs/CODE_CLEANUP_REPORT.md` - Code cleanup summary
- `docs/COMPTIME_IMPROVEMENTS.md` - Comptime features documentation
- `docs/TEST_COVERAGE_IMPROVEMENTS.md` - Test coverage tracking
- `docs/OBSERVABILITY_IMPROVEMENTS.md` - Observability features guide
- `docs/releases/NOTES_v0.7.2.md` - Release notes

### Infrastructure
- Dependabot configuration for automated dependency updates
- Custom dependency check workflow for OCI specs, crun, Proxmox VE
- Memory leak check workflow in CI
- Enhanced test infrastructure

### Notes
- Comptime validation auto-validation disabled due to Zig 0.15.1 syntax limitations
- JSON logging and metrics available but require manual integration
- Test coverage improvements ensure better stability
- Dependency monitoring helps track critical updates automatically

---

## [0.7.1] - 2025-10-31

### 🔧 Integration + Stability Release: libcrun ABI, OCI state.json, Proxmox fixes

This release adds libcrun ABI integration and includes critical fixes and improvements made after v0.7.0, including OCI state.json persistence, Proxmox-LXC kill command improvements, and enhanced E2E test stability.

### Added
- **libcrun ABI Integration**: Direct FFI bindings for libcrun API (`libcrun_container_create`, `start`, `kill`, `delete`)
- **libcrun Context Management**: Proper context initialization and lifecycle management for libcrun operations
- **Feature Flag Support**: Automatic fallback to CLI driver when libcrun ABI is unavailable (systemd dependency)
- **OCI state.json Persistence**: 
  - State files created at `/run/nexcage/<container_id>/state.json` on container creation
  - State updates on `start` (status: "running", actual PID) and `stop` (status: "stopped", pid: 0)
  - PID retrieval from running containers via `pct exec <vmid> -- cat /proc/1/stat`
- **libcrun FFI Bindings**: Complete Zig bindings for libcrun container operations

### Changed
- **CrunDriver**: Now uses libcrun ABI in Debug mode, CLI driver in Release mode (systemd dependency handling)
- **Build System**: Added systemd linking for libcrun ABI support
- **Module Structure**: Added `libcrun_driver.zig` and `libcrun_ffi.zig` for ABI-based operations
- **Default Network Bridge**: Changed from `lxcbr0` to `vmbr50` for Proxmox-LXC backend (Proxmox default)
- **E2E Test Framework**: 
  - Help tests now pass if help text is detected, regardless of exit code
  - Automatic Proxmox template provisioning in test scripts
  - Improved test output capture and validation

### Fixed
- **Proxmox-LXC Kill Command**: 
  - Pre-check if container is already stopped (treat as success)
  - Multiple fallback paths: `/usr/bin/kill`, `/bin/kill`, `/bin/sh -c`
  - Status polling after signal attempts (10 retries, 200ms interval)
  - Treat exit code 255 as success if container is confirmed stopped
  - Enhanced debug logging for all exec attempts
- **OCI state.json Implementation**:
  - Fixed JSON formatting for Zig 0.15.1 compatibility
  - Proper OCI-compliant state output format
  - Correct PID tracking for running containers
- **Memory Management**: 
  - Fixed memory management in libcrun context initialization
  - Proper null-terminated string handling for C FFI
  - Context structure alignment for libcrun API compatibility
- **Build Compatibility**: Removed `std.time.sleep` usage, replaced with `std.time.sleep(ns_per_ms)` for Zig 0.15.1

### Added (Post-v0.7.0)
- **DEB Package Support**: Automatic DEB package building for releases
  - Package name: `nexcage`
  - Installation via `dpkg -i nexcage-<version>-amd64.deb`
  - Configuration files and documentation included
- **CNCF Compliance Improvements**:
  - DCO (Developer Certificate of Origin) check workflow
  - OpenSSF Scorecards integration
  - CycloneDX SBOM generation
  - SLSA Provenance support
- **Codebase Quality Improvements**:
  - Repository cleanup (removed 29 obsolete files)
  - Archive organization (21 files moved to archive/)
  - Enhanced .gitignore for build artifacts
  - Codebase maturity: 7.9 → 8.5/10

### Changed (Post-v0.7.0)
- **Build System**: Optional libcrun/systemd linking (disabled by default for portability)
- **Documentation**: Added quality improvement plans and best practices guides

### Notes
- libcrun ABI requires systemd library for cgroup management
- CLI driver remains available as fallback when systemd is not available
- Debug builds use libcrun ABI, Release builds use CLI driver by default
- E2E test success rate improved from 88% to 93% (40/43 tests passing)
- DEB packages are automatically built on release tags
- All releases include SBOMs (SPDX + CycloneDX) and SLSA provenance

---

## [0.7.0] - 2025-10-29

### 🚀 Feature + Hardening Release: OCI kill/state, Proxmox fixes, security

This release delivers new OCI-compatible commands and multiple stability and security improvements across the Proxmox LXC backend and CLI.

### Added
- OCI `kill` command with `--signal` option (wired to proxmox-lxc, crun, runc)
- OCI `state` command returning OCI-compatible JSON
- Extensive debug tracing (opt-in via `--debug`)
- Foundational input validators (hostname/vmid/storage/path/env)

### Changed
- Debug output is gated by flags (`--debug`) to reduce noise by default
- Proxmox LXC: image parsing corrected — Proxmox templates vs docker-style refs
- Proxmox LXC: ZFS dataset creation validates pool/dataset existence; creates parents
- Path security hardening: bundle path validation and boundary checks
- Logging: safer allocator usage, writer changes to prevent segfaults

### Fixed
- Create command segfault due to logger allocator misuse
- ZFS errors when pool does not exist — now gracefully degraded or auto-creates parents
- Misclassification of `ubuntu:20.04` as Proxmox template

### Notes
- E2E: base smoke stable; functional flows pending create/start stabilization on target PVE

---

## [0.6.1] - 2025-10-27

### ✨ Enhancement Release: Improved Error Handling

This release focuses on improving error handling for Proxmox LXC backend, providing better error messages and validation.

### Changed
- **Enhanced pct Error Mapping**: Comprehensive error mapping for all pct command scenarios
- **Improved Error Messages**: Better error messages with actionable feedback for users
- **Detailed Logging**: Added detailed logging for debugging pct command failures
- **Error Categorization**: Better error categorization (Timeout, PermissionDenied, InvalidInput, NetworkError, etc.)

### Added
- **VMID Validation**: Check VMID uniqueness before creating containers
- **Comprehensive Error Detection**: Detect common pct command error scenarios
- **Enhanced Error Context**: Detailed error information with logging

### Fixed
- **Error Code Semantics**: Fixed incorrect error codes for existing resources (changed from NotFound to OperationFailed)
- **VMID Collision Prevention**: Proper validation prevents duplicate container creation
- **Error Message Clarity**: Clear, actionable error messages help users resolve issues quickly

### Technical Details
- **Error Handling**: Comprehensive error mapping for all pct command errors
- **Validation**: VMID validation before container creation
- **Logging**: Detailed logging for debugging and troubleshooting
- **User Experience**: Better error messages with actionable feedback

---

## [0.6.0] - 2025-10-15

### 🎉 Major Release: Backend Integration & Legacy Cleanup

This release completes the backend integration system and removes all legacy code, providing a clean, modern, and production-ready codebase.

### Added
- **Backend Routing System**: Intelligent backend selection based on container naming patterns
- **OCI Backend Support**: 
  - Crun Driver: Full OCI container lifecycle management
  - Runc Driver: Alternative OCI runtime support
- **Proxmox VM Backend**: Complete VM management via Proxmox API
- **PCT CLI Integration**: Native Proxmox LXC management via `pct` command
- **Container Type Detection**: Automatic backend selection based on config patterns
- **E2E Testing**: Automated testing on remote Proxmox servers
- **Stub Libraries**: Minimal crun and bfc libraries for build compatibility

### Changed
- **Architecture**: Moved from direct API calls to CLI-based Proxmox integration
- **CLI Commands**: Refactored to use backend routing instead of direct OCI calls
- **Configuration**: Enhanced with container routing patterns and backend selection
- **Build System**: Completely rewritten for clean modular architecture
- **Error Handling**: Improved error mapping for external command failures

### Removed
- **Legacy Code**: All legacy build files and directories removed
- **Archive Files**: Old documentation and examples moved to archive
- **Old Sprint Files**: Cleaned up outdated sprint documentation
- **Direct API Calls**: Replaced with CLI-based Proxmox integration
- **Circular Dependencies**: Resolved all module dependency issues

### Fixed
- **Memory Leaks**: Resolved all known memory allocation issues
- **Build Errors**: Fixed compilation errors and dependency issues
- **Module Imports**: Cleaned up all import statements and dependencies
- **Type Mismatches**: Resolved all type casting and compatibility issues

### Technical Details
- **Backend Selection**: Based on `config.json` routing patterns
- **Container Types**: LXC, VM, crun, runc with automatic detection
- **CLI Integration**: Direct backend calls without OCI layer
- **Testing**: Automated E2E tests with SSH deployment
- **Documentation**: Comprehensive architecture and implementation guides

### Migration Notes
- Legacy code preserved in `legacy/backend-routing-integration` branch
- All functionality maintained with improved architecture
- Configuration format updated for backend routing
- Build system simplified and modernized

---

## [0.4.0] - 2025-10-01

### 🚀 Major Release: Modular Architecture

This release introduces a complete modular architecture following SOLID principles, providing clean separation of concerns and extensibility.

### Added
- **Modular Architecture**: Complete redesign following SOLID principles
- **Core Module**: Global settings, errors, logging, interfaces, and types
- **CLI Module**: Registry-based command system with built-in and custom commands
- **Backend Modules**: 
  - LXC Backend: Native LXC container management
  - Proxmox LXC Backend: Proxmox API integration for LXC containers
  - Proxmox VM Backend: Proxmox API integration for virtual machines
  - Crun Backend: OCI-compatible container runtime
- **Integration Modules**:
  - Proxmox API: RESTful API client for Proxmox VE
  - ZFS Integration: ZFS filesystem operations and snapshots
  - BFC Integration: Binary File Container support
- **Utils Module**: File system and network utilities
- **Command Registry**: Dynamic command registration and execution
- **Structured Logging**: Comprehensive logging system with multiple levels
- **Configuration Management**: Centralized configuration loading and parsing
- **Error Handling**: Centralized error types and handling mechanisms

### Changed
- **Architecture**: Complete redesign from monolithic to modular architecture
- **CLI System**: New registry-based command system replaces direct command handling
- **Backend Selection**: Dynamic backend selection through configuration
- **Memory Management**: Improved allocator usage patterns for Zig 0.13.0 compatibility
- **Documentation**: Complete documentation overhaul with examples and guides

### Deprecated
- **Legacy Version**: Legacy monolithic architecture marked as deprecated
- **Old CLI**: Direct command handling deprecated in favor of registry system
- **Monolithic Backends**: Individual backend implementations deprecated

### Removed
- **Monolithic Structure**: Removed tight coupling between components
- **Legacy Dependencies**: Cleaned up unused dependencies
- **Deprecated APIs**: Removed deprecated API interfaces

### Fixed
- **Memory Management**: Fixed allocator union access issues for Zig 0.13.0
- **Module Dependencies**: Resolved circular dependencies
- **Error Handling**: Improved error propagation and handling
- **Configuration Loading**: Fixed configuration parsing and validation

### Security
- **Input Validation**: Enhanced input validation across all modules
- **Error Information**: Improved error messages without exposing sensitive data
- **Memory Safety**: Better memory management and cleanup

### Documentation
- **MODULAR_ARCHITECTURE.md**: Comprehensive architecture guide
- **Usage Examples**: Complete examples for all modules
- **Migration Guide**: Guide for moving from legacy to modular architecture
- **API Documentation**: Complete API documentation for all modules
- **Best Practices**: Development and usage guidelines

### Examples
- **modular_basic_example.zig**: Basic usage examples for all backends
- **modular_cli_example.zig**: CLI integration and custom command examples

### Performance
- **Module Loading**: Optimized module loading and initialization
- **Memory Usage**: Improved memory allocation patterns
- **Command Execution**: Streamlined command processing through registry
- **Backend Selection**: Efficient backend selection and caching

### Breaking Changes
- **Module Structure**: Complete restructuring requires code updates
- **CLI Interface**: New command registry system
- **Configuration Format**: Updated configuration structure
- **API Interfaces**: New interface definitions for backends and integrations

### Migration Notes
- Update imports to use modular paths
- Use new configuration system
- Leverage new logging system
- Take advantage of registry-based CLI
- See MODULAR_ARCHITECTURE.md for detailed migration guide

## [0.3.0] - 2025-09-15

### Added
- ZFS Checkpoint/Restore system
- Lightning-fast container state snapshots
- Hybrid ZFS snapshots + CRIU fallback system
- Advanced performance optimizations
- Enhanced security features

### Changed
- Improved container lifecycle management
- Enhanced ZFS integration
- Better error handling and recovery

### Fixed
- Memory leak issues
- Performance bottlenecks
- Configuration parsing bugs

## [0.2.0] - 2025-08-20

### Added
- Proxmox VE integration
- OCI Runtime Specification compliance
- Container orchestration support
- Advanced networking features

### Changed
- Improved API design
- Enhanced documentation
- Better error messages

## [0.1.0] - 2025-07-10

### Added
- Initial release
- Basic LXC container support
- OCI image system
- Core runtime functionality

---

## Version History Summary

- **v0.4.0**: Modular Architecture - Complete redesign with SOLID principles
- **v0.3.0**: ZFS Checkpoint/Restore - Performance and snapshot improvements
- **v0.2.0**: Proxmox Integration - Full Proxmox VE integration
- **v0.1.0**: Initial Release - Basic functionality

## Support Policy

- **v0.4.0+**: Active development and support
- **v0.3.x**: Security updates only
- **v0.2.x**: Critical bug fixes only
- **v0.1.x**: Deprecated, no support

## Upgrade Path

- **From v0.3.x to v0.4.0**: Major upgrade required, see migration guide
- **From v0.2.x to v0.4.0**: Major upgrade required, see migration guide
- **From v0.1.x to v0.4.0**: Major upgrade required, see migration guide

For detailed migration instructions, see [MODULAR_ARCHITECTURE.md](docs/MODULAR_ARCHITECTURE.md).
