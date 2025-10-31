# Observability Improvements

**Date**: 2025-10-31  
**Status**: In Progress  
**Scope**: Structured logging, metrics, and health checks

---

## Overview

This document describes the observability improvements implemented to enhance monitoring and debugging capabilities.

---

## Features Implemented

### 1. Structured JSON Logging ✅

**Module**: `src/core/json_logging.zig`

**Purpose**: Output logs in structured JSON format for better parsing and analysis.

#### Features

- **JSON Format**: All log entries output as JSON
- **Structured Fields**: timestamp, level, component, message
- **Custom Fields**: Additional fields support via `logWithFields()`
- **Escaping**: Proper JSON string escaping for special characters

#### Usage

```zig
var json_logger = core.json_logging.JsonLogger.init(allocator, stdout.writer(), "my-component");
try json_logger.info("Container created: {s}", .{"my-container"});

// With custom fields
try json_logger.logWithFields(.info, "Operation completed", .{}, .{
    .container_id = "123",
    .duration_ms = 42.5,
});
```

#### Output Format

```json
{"timestamp":1698765432,"level":"info","component":"my-component","message":"Container created: my-container"}
{"timestamp":1698765433,"level":"info","component":"my-component","message":"Operation completed","fields":{"container_id":"123","duration_ms":42.5}}
```

---

### 2. Prometheus Metrics ✅

**Module**: `src/core/metrics.zig`

**Purpose**: Export metrics in Prometheus format for monitoring.

#### Features

- **Metrics Registry**: Central registry for all metrics
- **Counter**: Increment-only metrics
- **Gauge**: Metrics that can go up and down
- **Histogram**: Distribution metrics (simplified implementation)
- **Labels**: Support for metric labels
- **Prometheus Format**: Export in standard Prometheus text format

#### Usage

```zig
var registry = core.metrics.MetricsRegistry.init(allocator);
defer registry.deinit();

const container_created = try registry.counter(
    "nexcage_containers_created_total",
    "Total number of containers created"
);
container_created.inc(1.0);

const active_containers = try registry.gauge(
    "nexcage_containers_active",
    "Number of currently active containers"
);
active_containers.set(5.0);

// Export metrics
var buffer = std.ArrayList(u8).init(allocator);
try registry.exportMetrics(buffer.writer());
```

#### Output Format

```
# HELP nexcage_containers_created_total Total number of containers created
# TYPE nexcage_containers_created_total counter
nexcage_containers_created_total 1

# HELP nexcage_containers_active Number of currently active containers
# TYPE nexcage_containers_active gauge
nexcage_containers_active 5
```

---

### 3. Enhanced Health Checks ✅

**Module**: `src/cli/health_check.zig`

**Purpose**: Comprehensive system health monitoring.

#### Features

- System integrity checks
- Proxmox connectivity verification
- Storage and network checks
- Configuration validation
- Structured health report output

---

## Integration Points

### Core Module Export

**File**: `src/core/mod.zig`

Added exports:
```zig
pub const json_logging = @import("json_logging.zig");
pub const metrics = @import("metrics.zig");
```

---

## Usage Examples

### JSON Logging

```zig
const core = @import("core");
const stdout = std.fs.File.stdout();

var json_logger = core.json_logging.JsonLogger.init(
    allocator,
    stdout.writer(),
    "nexcage"
);

try json_logger.info("Starting container", .{});
try json_logger.logWithFields(.info, "Container started", .{}, .{
    .container_id = "test-123",
    .runtime = "proxmox-lxc",
    .success = true,
});
```

### Metrics Collection

```zig
const core = @import("core");

var metrics = core.metrics.MetricsRegistry.init(allocator);
defer metrics.deinit();

// Track container operations
const ops_counter = try metrics.counter(
    "nexcage_operations_total",
    "Total container operations"
);

const active_gauge = try metrics.gauge(
    "nexcage_containers_active",
    "Active container count"
);

// Increment on operation
ops_counter.inc(1.0);

// Update gauge
active_gauge.set(10.0);

// Export for Prometheus scraping
var output = std.ArrayList(u8).init(allocator);
try metrics.exportMetrics(output.writer());
```

---

## Future Enhancements

### 1. HTTP Metrics Endpoint
- Expose metrics via HTTP endpoint
- Standard `/metrics` endpoint for Prometheus

### 2. Distributed Tracing
- OpenTelemetry integration
- Trace context propagation
- Span creation and management

### 3. Log Aggregation
- Centralized log collection
- Log rotation and retention
- Structured log search

### 4. Alerting Integration
- Alert manager integration
- Custom alert rules
- Notification channels

---

## Configuration

### JSON Logging

Enable via logging configuration:
```json
{
  "logging": {
    "format": "json",
    "level": "info"
  }
}
```

### Metrics

Metrics collection can be enabled via:
- Command-line flag: `--metrics-port 9090`
- Configuration file: `metrics.enabled = true`

---

## Testing

### JSON Logger Tests

```zig
test "JSON logger output" {
    var buffer = std.ArrayList(u8).init(allocator);
    var logger = JsonLogger.init(allocator, buffer.writer(), "test");
    
    try logger.info("Test message", .{});
    
    const output = try buffer.toOwnedSlice();
    // Verify JSON structure
}
```

### Metrics Tests

```zig
test "Metrics registry" {
    var registry = MetricsRegistry.init(allocator);
    defer registry.deinit();
    
    const counter = try registry.counter("test_counter", "Test");
    counter.inc(1.0);
    
    // Verify export
    var buffer = std.ArrayList(u8).init(allocator);
    try registry.exportMetrics(buffer.writer());
}
```

---

## References

- [Prometheus Metrics Format](https://prometheus.io/docs/instrumenting/exposition_formats/)
- [JSON Logging Best Practices](https://www.datadoghq.com/blog/json-logging-best-practices/)
- Project files:
  - `src/core/json_logging.zig`
  - `src/core/metrics.zig`

---

**Status**: ✅ Basic observability features implemented  
**Next**: HTTP endpoint integration and distributed tracing

