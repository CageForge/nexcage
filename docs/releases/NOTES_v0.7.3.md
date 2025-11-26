# Release Notes v0.7.3

**Release Date**: 2025-11-02  
**Type**: Bug Fix Release

## Overview

Version 0.7.3 fixes critical bugs in template conversion and OCI bundle processing, resolves memory leaks in the template manager, and adds support for OCI bundle resource limits and namespaces.

## Key Features

### OCI Bundle Resources Support
- Parse memory limits from OCI bundle `config.json` (`linux.resources.memory.limit`)
- Parse CPU shares from OCI bundle (`linux.resources.cpu.shares`)
- Automatic conversion: bytes → MB for memory, shares/1024.0 → cores for CPU
- Priority order: bundle_config > SandboxConfig > defaults

### OCI Namespaces Support
- Parse all OCI namespaces: pid, network, ipc, uts, mount, user, cgroup
- Map user namespace to Proxmox LXC features (`nesting=1,keyctl=1`)
- Automatic feature configuration via `pct set --features`

## Bug Fixes

### Memory Leak in Template Manager
Fixed memory leaks in `processOciBundle()`:
- Added proper `errdefer` cleanup for `template_info` and `metadata`
- Added `defer` cleanup after `addTemplate()` (which clones the template)
- Proper cleanup for entrypoint and cmd arrays

### Template Archive Issues
- Archive now correctly includes all files (verified: `bin/sh`, `sbin/init`, `etc/hostname`)
- Fixed recursive validation to count files in subdirectories
- Enhanced error handling in `copyDirectoryRecursive`

### CPU Cores Calculation
- Fixed `cores=0` issue when CPU shares < 1024
- Added minimum of 1 core guarantee
- Prevents invalid container configuration

### pct create Error Handling
- Enhanced debug output for troubleshooting
- Better handling of edge cases
- Improved error messages

## Testing

All changes have been tested on Proxmox server (`mgr.cp.if.ua`):
- ✅ Memory leaks resolved
- ✅ Archive creation verified
- ✅ Container creation successful (VMID 31386, 72421)
- ✅ pct create working correctly

## Migration Notes

No breaking changes. This is a bug fix release.

## Contributors

- Template conversion debugging and fixes
- Memory leak resolution
- OCI bundle resources and namespaces support

## Full Changelog

See [CHANGELOG.md](../../CHANGELOG.md) for complete list of changes.
