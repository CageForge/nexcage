# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
