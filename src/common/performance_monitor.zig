/// Performance monitoring utilities for Proxmox LXCRI
/// 
/// This module provides lightweight performance monitoring capabilities
/// including operation timing, memory usage tracking, and metrics collection.

const std = @import("std");
const types = @import("types");
const logger = @import("logger");

/// Performance metrics structure for tracking operation performance
pub const PerformanceMetrics = struct {
    /// Operation name being measured
    operation_name: []const u8,
    /// Start time of the operation
    start_time: i64,
    /// End time of the operation (0 if still running)
    end_time: i64,
    /// Memory usage before operation (bytes)
    memory_before: usize,
    /// Memory usage after operation (bytes)
    memory_after: usize,
    /// Custom metadata for the operation
    metadata: ?[]const u8,
    /// Memory allocator for cleanup
    allocator: std.mem.Allocator,

    /// Initializes a new performance metrics tracker
    /// 
    /// Arguments:
    /// - allocator: Memory allocator for string duplication
    /// - operation_name: Name of the operation being tracked
    /// - metadata: Optional metadata about the operation
    /// 
    /// Returns: Initialized PerformanceMetrics structure
    pub fn init(allocator: std.mem.Allocator, operation_name: []const u8, metadata: ?[]const u8) !PerformanceMetrics {
        return PerformanceMetrics{
            .operation_name = try allocator.dupe(u8, operation_name),
            .start_time = std.time.nanoTimestamp(),
            .end_time = 0,
            .memory_before = getCurrentMemoryUsage(),
            .memory_after = 0,
            .metadata = if (metadata) |m| try allocator.dupe(u8, m) else null,
            .allocator = allocator,
        };
    }

    /// Marks the end of the operation and captures final metrics
    pub fn finish(self: *PerformanceMetrics) void {
        self.end_time = std.time.nanoTimestamp();
        self.memory_after = getCurrentMemoryUsage();
    }

    /// Calculates the duration of the operation in nanoseconds
    /// 
    /// Returns: Operation duration in nanoseconds, or 0 if not finished
    pub fn getDurationNanos(self: *const PerformanceMetrics) i64 {
        if (self.end_time == 0) return 0;
        return self.end_time - self.start_time;
    }

    /// Calculates the duration of the operation in milliseconds
    /// 
    /// Returns: Operation duration in milliseconds, or 0 if not finished
    pub fn getDurationMillis(self: *const PerformanceMetrics) f64 {
        const nanos = self.getDurationNanos();
        return @as(f64, @floatFromInt(nanos)) / 1_000_000.0;
    }

    /// Calculates the memory difference (increase/decrease) during operation
    /// 
    /// Returns: Memory change in bytes (positive = increase, negative = decrease)
    pub fn getMemoryDelta(self: *const PerformanceMetrics) i64 {
        if (self.memory_after == 0) return 0;
        return @as(i64, @intCast(self.memory_after)) - @as(i64, @intCast(self.memory_before));
    }

    /// Logs the performance metrics to the logger
    pub fn logMetrics(self: *const PerformanceMetrics) void {
        const duration_ms = self.getDurationMillis();
        const memory_delta = self.getMemoryDelta();
        
        logger.info(
            "Performance: {s} completed in {d:.2}ms, memory delta: {d} bytes", 
            .{ self.operation_name, duration_ms, memory_delta }
        ) catch {};

        if (self.metadata) |metadata| {
            logger.debug("Performance metadata: {s}", .{metadata}) catch {};
        }
    }

    /// Cleans up allocated memory
    pub fn deinit(self: *PerformanceMetrics) void {
        self.allocator.free(self.operation_name);
        if (self.metadata) |metadata| {
            self.allocator.free(metadata);
        }
    }
};

/// Performance timer for simple operation timing
pub const PerformanceTimer = struct {
    start_time: i64,
    operation_name: []const u8,

    /// Starts a new performance timer
    /// 
    /// Arguments:
    /// - operation_name: Name of the operation being timed
    /// 
    /// Returns: Initialized PerformanceTimer
    pub fn start(operation_name: []const u8) PerformanceTimer {
        logger.debug("Starting performance timer for: {s}", .{operation_name}) catch {};
        return PerformanceTimer{
            .start_time = std.time.nanoTimestamp(),
            .operation_name = operation_name,
        };
    }

    /// Stops the timer and logs the elapsed time
    pub fn stop(self: *const PerformanceTimer) void {
        const end_time = std.time.nanoTimestamp();
        const duration_nanos = end_time - self.start_time;
        const duration_ms = @as(f64, @floatFromInt(duration_nanos)) / 1_000_000.0;
        
        logger.info(
            "Performance: {s} completed in {d:.2}ms", 
            .{ self.operation_name, duration_ms }
        ) catch {};
    }
};

/// Global performance monitoring state
var monitoring_enabled: bool = false;
var total_operations: u64 = 0;
var total_duration_nanos: u64 = 0;

/// Enables performance monitoring globally
pub fn enableMonitoring() void {
    monitoring_enabled = true;
    logger.info("Performance monitoring enabled") catch {};
}

/// Disables performance monitoring globally  
pub fn disableMonitoring() void {
    monitoring_enabled = false;
    logger.info("Performance monitoring disabled") catch {};
}

/// Checks if performance monitoring is currently enabled
/// 
/// Returns: True if monitoring is enabled, false otherwise
pub fn isMonitoringEnabled() bool {
    return monitoring_enabled;
}

/// Records an operation in global statistics
/// 
/// Arguments:
/// - duration_nanos: Duration of the operation in nanoseconds
pub fn recordOperation(duration_nanos: u64) void {
    if (!monitoring_enabled) return;
    
    total_operations += 1;
    total_duration_nanos += duration_nanos;
}

/// Gets the average operation duration in milliseconds
/// 
/// Returns: Average duration in milliseconds, or 0 if no operations recorded
pub fn getAverageOperationDuration() f64 {
    if (total_operations == 0) return 0.0;
    
    const avg_nanos = total_duration_nanos / total_operations;
    return @as(f64, @floatFromInt(avg_nanos)) / 1_000_000.0;
}

/// Logs current performance statistics
pub fn logStatistics() void {
    if (!monitoring_enabled) return;
    
    const avg_duration = getAverageOperationDuration();
    logger.info(
        "Performance stats: {d} operations, avg duration: {d:.2}ms", 
        .{ total_operations, avg_duration }
    ) catch {};
}

/// Resets global performance statistics
pub fn resetStatistics() void {
    total_operations = 0;
    total_duration_nanos = 0;
    logger.debug("Performance statistics reset") catch {};
}

/// Convenience macro for timing a block of code
/// 
/// Usage: 
/// ```zig
/// {
///     const timer = PerformanceTimer.start("my_operation");
///     defer timer.stop();
///     // Your code here
/// }
/// ```

/// Gets current memory usage (placeholder implementation)
/// 
/// Note: This is a simplified implementation. In a real-world scenario,
/// you would integrate with system-specific memory tracking APIs.
/// 
/// Returns: Estimated current memory usage in bytes
fn getCurrentMemoryUsage() usize {
    // Placeholder implementation - in production, this would query
    // actual memory usage from the system or allocator
    return 0;
}

/// Performance monitoring hook for container operations
pub const ContainerPerformanceHook = struct {
    metrics: ?PerformanceMetrics,
    allocator: std.mem.Allocator,

    /// Initializes a performance hook for container operations
    /// 
    /// Arguments:
    /// - allocator: Memory allocator for metrics
    /// 
    /// Returns: Initialized ContainerPerformanceHook
    pub fn init(allocator: std.mem.Allocator) ContainerPerformanceHook {
        return ContainerPerformanceHook{
            .metrics = null,
            .allocator = allocator,
        };
    }

    /// Starts monitoring a container operation
    /// 
    /// Arguments:
    /// - operation: Name of the container operation
    /// - container_id: ID of the container being operated on
    pub fn startOperation(self: *ContainerPerformanceHook, operation: []const u8, container_id: []const u8) !void {
        if (!monitoring_enabled) return;

        const metadata = try std.fmt.allocPrint(self.allocator, "container_id: {s}", .{container_id});
        defer self.allocator.free(metadata);

        self.metrics = try PerformanceMetrics.init(self.allocator, operation, metadata);
    }

    /// Finishes monitoring a container operation
    pub fn finishOperation(self: *ContainerPerformanceHook) void {
        if (self.metrics) |*metrics| {
            metrics.finish();
            metrics.logMetrics();
            
            const duration = metrics.getDurationNanos();
            if (duration > 0) {
                recordOperation(@intCast(duration));
            }
            
            metrics.deinit();
            self.metrics = null;
        }
    }

    /// Cleans up the performance hook
    pub fn deinit(self: *ContainerPerformanceHook) void {
        if (self.metrics) |*metrics| {
            metrics.deinit();
        }
    }
};
