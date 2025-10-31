# Release Notes v0.7.2

**Release Date:** 2025-10-31  
**Type:** Code Quality & Stability Release

## Overview

v0.7.2 focuses on codebase quality improvements and enhanced observability. This release implements comprehensive error handling, memory leak detection, test coverage improvements, structured logging, metrics export, and automated dependency monitoring.

## What's New

### Error Handling Enhancement

Comprehensive error handling system with context and chaining capabilities.

#### Features

- **ErrorContext**: Detailed error information including message, source file, line, column, and stack trace
- **ErrorContextBuilder**: Fluent API for building error contexts
- **Error Chaining**: Link related errors to provide complete trace of issues
- **Contextual Errors**: Wrap errors with additional context information

#### Benefits

- Better debugging experience with detailed error information
- Complete error traces showing root causes
- Improved error messages for end users
- Easier troubleshooting in production environments

### Memory Leak Detection

Comprehensive memory management audit and improvements.

#### Features

- **Memory Audit Script**: Automated script to detect potential memory leaks
- **Enhanced errdefer**: Added errdefer statements in critical paths
- **Memory Leak Report**: Detailed analysis of 299 allocator operations
- **Valgrind Integration**: CI workflow for memory leak detection

#### Improvements

- Added errdefer for all allocations in `router.zig`
- Improved error path cleanup safety
- Better memory lifecycle management
- Documentation of memory ownership patterns

### Code Cleanup

Removed obsolete code and clarified documentation.

#### Changes

- **Removed**: ~60 lines of obsolete/commented code
- **Clarified**: 10+ TODO comments with better context
- **Removed**: Unused AppContext fields (BackendInterface, NetworkProvider, etc.)
- **Removed**: Unused initialization methods

#### Benefits

- Cleaner codebase
- Better maintainability
- Clearer documentation
- Reduced confusion from obsolete code

### Comptime Improvements

Type-safe configuration validation using Zig's comptime capabilities.

#### Features

- **Comptime Validation Module**: Compile-time checks for config structures
- **ConfigBuilder Pattern**: Type-safe builder for configurations
- **Comptime String Operations**: String utilities for compile-time
- **Runtime Type Parsing**: Compile-time parsing of runtime types

#### Status

Module created and available for manual use. Auto-validation disabled due to Zig 0.15.1 type checking syntax limitations. Will be re-enabled when upgrading Zig version.

### Test Coverage Increase

Significant improvements in test coverage for core modules.

#### New Test Files

- `tests/core/router_test.zig` - BackendRouter tests
- `tests/core/errors_test.zig` - Error handling tests
- `tests/core/comptime_validation_test.zig` - Comptime validation tests
- `tests/core/validation_test.zig` - Validation function tests

#### Coverage Improvements

- **router.zig**: 0% → ~70% (estimated)
- **errors.zig**: 0% → ~80% (estimated)
- **comptime_validation.zig**: 0% → ~75% (estimated)
- **validation.zig**: 30% → ~70% (estimated)
- **Overall**: ~60% → ~75-80% (estimated)

### Observability Implementation

Structured logging and metrics for better monitoring.

#### JSON Logging

- **Structured Output**: All logs in JSON format
- **Custom Fields**: Support for additional structured fields
- **Proper Escaping**: Correct JSON string escaping
- **Machine Readable**: Easy parsing for log aggregation tools

#### Prometheus Metrics

- **MetricsRegistry**: Central registry for all metrics
- **Counter**: Increment-only metrics
- **Gauge**: Metrics that can go up and down
- **Histogram**: Distribution metrics (simplified)
- **Prometheus Format**: Standard text format export

#### Usage

```zig
// JSON Logging
var json_logger = core.json_logging.JsonLogger.init(allocator, stdout.writer(), "component");
try json_logger.info("Container created: {s}", .{"my-container"});

// Metrics
var metrics = core.metrics.MetricsRegistry.init(allocator);
const counter = try metrics.counter("operations_total", "Total operations");
counter.inc(1.0);
```

### Dependency Monitoring

Automated monitoring of critical dependencies.

#### Dependabot

- **GitHub Actions**: Weekly automated updates
- **Docker**: Weekly automated updates
- **Automatic PRs**: Grouped updates for minor/patch versions
- **Custom Labels**: dependencies, github-actions, docker

#### Custom Dependency Checks

- **OCI Runtime Spec**: Version monitoring via GitHub API
- **OCI Image Spec**: Version monitoring via GitHub API
- **crun Library**: Version detection from deps/crun
- **Proxmox VE**: Release monitoring via multiple sources
- **Auto-Issues**: GitHub issues created for available updates

## Technical Details

### Error Handling

**Module**: `src/core/errors.zig`

New structures:
- `ErrorContext`: Detailed error information
- `ErrorContextBuilder`: Fluent API builder
- `ContextualError`: Error with context wrapper
- `ErrorWithContext`: Union for simple, contextual, or chained errors

### Memory Management

**Module**: `src/core/router.zig`

Improvements:
- Added errdefer for `name_buf` allocations
- Added errdefer for `image_buf` allocations
- Added errdefer for `bridge_buf` in network config
- Improved error path cleanup safety

**Audit Results**:
- 299 allocator operations reviewed
- Most allocations properly managed
- Critical paths improved with errdefer
- Risk level: Low-Medium (no critical leaks found)

### Comptime Validation

**Module**: `src/core/comptime_validation.zig`

Features:
- `validateConfigType()` - Validates config structures
- `hasRequiredFields()` - Checks for required fields
- `assertHasField/Method()` - Compile-time assertions
- `ConfigBuilder()` - Type-safe builder pattern
- `StringOps` - Comptime string utilities

### Observability

**Modules**:
- `src/core/json_logging.zig` - JSON structured logging
- `src/core/metrics.zig` - Prometheus metrics export

### Testing

**New Test Files**: 4 files, ~25+ new tests

**Coverage**: Increased from ~60% to ~75-80% (estimated)

## Breaking Changes

None. This is a backward-compatible release.

## Deprecations

None.

## Migration Guide

### Error Handling

Previous error handling remains compatible. New error context features are opt-in:

```zig
// Old way (still works)
return error.ValidationError;

// New way (with context)
var builder = try core.errors.ErrorContextBuilder.init(allocator, "Validation failed", .{});
try builder.withSource("config.zig");
const context = builder.build();
const contextual_error = core.errors.ContextualError{
    .error_type = types.Error.ValidationError,
    .context = context,
    .cause = null,
};
```

### JSON Logging

JSON logging is available but not enabled by default. To use:

```zig
var json_logger = core.json_logging.JsonLogger.init(allocator, stdout.writer(), "component");
try json_logger.info("Message", .{});
```

### Metrics

Metrics collection is available but requires manual integration:

```zig
var metrics = core.metrics.MetricsRegistry.init(allocator);
defer metrics.deinit();

const counter = try metrics.counter("name", "help");
counter.inc(1.0);

// Export for Prometheus
try metrics.exportMetrics(stdout.writer());
```

## Dependencies

### Updated
- None (dependency monitoring added, but no updates yet)

### New
- Dependabot integration (GitHub-native)
- Custom dependency check workflow

## Performance

- No performance regressions
- Memory leak improvements reduce potential leaks
- Test coverage improvements ensure stability

## Security

- Enhanced error handling prevents information leakage
- Better memory management reduces attack surface
- Test coverage improvements catch edge cases

## Known Issues

1. **Comptime Validation**: Auto-validation disabled due to Zig 0.15.1 syntax limitations
   - Workaround: Manual validation available
   - Fix: Will be re-enabled when upgrading Zig version

2. **Dependency Checks**: Proxmox VE version detection relies on web scraping
   - Workaround: Multiple fallback sources
   - Future: Direct API integration

## Credits

This release includes improvements from Sprint 6.6: Codebase Quality Improvements.

## Full Changelog

See [CHANGELOG.md](../CHANGELOG.md) for complete list of changes.

## Download

- **GitHub Releases**: https://github.com/CageForge/nexcage/releases/tag/v0.7.2
- **DEB Package**: Available in release artifacts

## Support

- **Documentation**: See project README and docs/
- **Issues**: https://github.com/CageForge/nexcage/issues
- **Discussions**: https://github.com/CageForge/nexcage/discussions

