# NexCage v0.7.6 Release Notes

**Release Date:** 2026-02-01

## Summary

Code cleanup and OCI specification improvements. This release focuses on stability, maintainability, and completing OCI bundle parsing.

## Changes

### OCI Bundle Parser (oci-spec-zig)
- **Mount options**: Parse `options` array from OCI mount config and convert to comma-separated string for LXC compatibility
- **Capabilities**: Parse OCI capabilities object (bounding, effective, etc.) and extract capability names as comma-separated string
- **Zig 0.15.1 compatibility**: Use `ArrayListUnmanaged` instead of `ArrayList` for compatibility

### CLI Cleanup
- **Create command**: Remove excessive debug output that cluttered logs
- **Router**: Remove unused `config_module` import

### Build & Tests
- All tests pass
- Build verified with Zig 0.15.1

## Upgrade Notes

No breaking changes. This is a maintenance release.

## Full Changelog

See [packaging/debian/changelog](packaging/debian/changelog) for details.
