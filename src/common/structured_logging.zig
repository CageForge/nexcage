/// Structured logging system for Proxmox LXCRI
/// 
/// This module provides advanced structured logging capabilities including
/// JSON formatting, log rotation, remote logging, and performance metrics.

const std = @import("std");
const types = @import("types");
const logger = @import("logger");
const json = std.json;

/// Log entry structure for structured logging
pub const LogEntry = struct {
    timestamp: i64,
    level: types.LogLevel,
    message: []const u8,
    context: std.StringHashMap([]const u8),
    metadata: ?std.StringHashMap(json.Value),
    allocator: std.mem.Allocator,

    /// Initializes a new log entry
    pub fn init(allocator: std.mem.Allocator, level: types.LogLevel, message: []const u8) !LogEntry {
        return LogEntry{
            .timestamp = std.time.nanoTimestamp(),
            .level = level,
            .message = try allocator.dupe(u8, message),
            .context = std.StringHashMap([]const u8).init(allocator),
            .metadata = null,
            .allocator = allocator,
        };
    }

    /// Adds context field to log entry
    pub fn addContext(self: *LogEntry, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.context.put(owned_key, owned_value);
    }

    /// Adds metadata field to log entry
    pub fn addMetadata(self: *LogEntry, key: []const u8, value: json.Value) !void {
        if (self.metadata == null) {
            self.metadata = std.StringHashMap(json.Value).init(self.allocator);
        }
        
        const owned_key = try self.allocator.dupe(u8, key);
        try self.metadata.?.put(owned_key, value);
    }

    /// Converts log entry to JSON string
    pub fn toJSON(self: *const LogEntry) ![]u8 {
        var json_obj = std.StringHashMap(json.Value).init(self.allocator);
        defer json_obj.deinit();

        // Add basic fields
        try json_obj.put("timestamp", json.Value{ .integer = self.timestamp });
        try json_obj.put("level", json.Value{ .string = @tagName(self.level) });
        try json_obj.put("message", json.Value{ .string = self.message });

        // Add context fields
        var context_iter = self.context.iterator();
        while (context_iter.next()) |entry| {
            try json_obj.put(entry.key_ptr.*, json.Value{ .string = entry.value_ptr.* });
        }

        // Add metadata fields
        if (self.metadata) |metadata| {
            var metadata_iter = metadata.iterator();
            while (metadata_iter.next()) |entry| {
                try json_obj.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }

        // Convert to JSON string
        var json_string = std.ArrayList(u8).init(self.allocator);
        try json.stringify(json.Value{ .object = json_obj }, .{}, json_string.writer());
        return json_string.toOwnedSlice();
    }

    /// Cleans up log entry
    pub fn deinit(self: *LogEntry) void {
        self.allocator.free(self.message);
        
        var context_iter = self.context.iterator();
        while (context_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.context.deinit();

        if (self.metadata) |*metadata| {
            var metadata_iter = metadata.iterator();
            while (metadata_iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            metadata.deinit();
        }
    }
};

/// Log rotation configuration
pub const RotationConfig = struct {
    max_file_size: usize,
    max_file_count: u32,
    compression: bool,

    pub const default = RotationConfig{
        .max_file_size = 100 * 1024 * 1024, // 100MB
        .max_file_count = 10,
        .compression = true,
    };
};

/// File-based structured logger with rotation
pub const StructuredFileLogger = struct {
    file_path: []const u8,
    current_file: ?std.fs.File,
    rotation_config: RotationConfig,
    current_file_size: usize,
    allocator: std.mem.Allocator,

    /// Initializes structured file logger
    pub fn init(allocator: std.mem.Allocator, file_path: []const u8, rotation_config: RotationConfig) !StructuredFileLogger {
        return StructuredFileLogger{
            .file_path = try allocator.dupe(u8, file_path),
            .current_file = null,
            .rotation_config = rotation_config,
            .current_file_size = 0,
            .allocator = allocator,
        };
    }

    /// Deinitializes structured file logger
    pub fn deinit(self: *StructuredFileLogger) void {
        if (self.current_file) |file| {
            file.close();
        }
        self.allocator.free(self.file_path);
    }

    /// Opens or creates log file
    fn ensureFileOpen(self: *StructuredFileLogger) !void {
        if (self.current_file != null) return;

        self.current_file = std.fs.cwd().createFile(self.file_path, .{
            .truncate = false,
            .exclusive = false,
        }) catch |err| {
            logger.err("Failed to open log file: {s}", .{@errorName(err)}) catch {};
            return err;
        };

        // Get current file size
        const stat = try self.current_file.?.stat();
        self.current_file_size = @intCast(stat.size);
    }

    /// Rotates log file if necessary
    fn rotateIfNeeded(self: *StructuredFileLogger) !void {
        if (self.current_file_size < self.rotation_config.max_file_size) return;

        logger.info("Rotating log file (size: {} bytes)", .{self.current_file_size}) catch {};

        // Close current file
        if (self.current_file) |file| {
            file.close();
            self.current_file = null;
        }

        // Rotate files
        var i: u32 = self.rotation_config.max_file_count - 1;
        while (i > 0) : (i -= 1) {
            const old_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.file_path, i });
            defer self.allocator.free(old_name);
            
            const new_name = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{ self.file_path, i + 1 });
            defer self.allocator.free(new_name);

            std.fs.cwd().rename(old_name, new_name) catch {};
        }

        // Move current file to .1
        const backup_name = try std.fmt.allocPrint(self.allocator, "{s}.1", .{self.file_path});
        defer self.allocator.free(backup_name);
        
        std.fs.cwd().rename(self.file_path, backup_name) catch {};

        // Reset file size
        self.current_file_size = 0;
    }

    /// Writes log entry to file
    pub fn writeEntry(self: *StructuredFileLogger, entry: *const LogEntry) !void {
        try self.ensureFileOpen();
        try self.rotateIfNeeded();

        const json_entry = try entry.toJSON();
        defer self.allocator.free(json_entry);

        if (self.current_file) |file| {
            const bytes_written = try file.writeAll(json_entry);
            _ = try file.writeAll("\n");
            self.current_file_size += json_entry.len + 1;
        }
    }
};

/// Remote logging configuration
pub const RemoteLogConfig = struct {
    endpoint: []const u8,
    api_key: ?[]const u8,
    batch_size: u32,
    flush_interval_ms: u32,

    pub const default = RemoteLogConfig{
        .endpoint = "http://localhost:8080/logs",
        .api_key = null,
        .batch_size = 100,
        .flush_interval_ms = 5000,
    };
};

/// Remote structured logger
pub const RemoteStructuredLogger = struct {
    config: RemoteLogConfig,
    batch: std.ArrayList(LogEntry),
    last_flush: i64,
    allocator: std.mem.Allocator,

    /// Initializes remote structured logger
    pub fn init(allocator: std.mem.Allocator, config: RemoteLogConfig) RemoteStructuredLogger {
        return RemoteStructuredLogger{
            .config = config,
            .batch = std.ArrayList(LogEntry).init(allocator),
            .last_flush = std.time.nanoTimestamp(),
            .allocator = allocator,
        };
    }

    /// Deinitializes remote structured logger
    pub fn deinit(self: *RemoteStructuredLogger) void {
        // Flush remaining entries
        self.flush() catch {};
        
        for (self.batch.items) |*entry| {
            entry.deinit();
        }
        self.batch.deinit();
    }

    /// Adds log entry to batch
    pub fn addEntry(self: *RemoteStructuredLogger, entry: LogEntry) !void {
        try self.batch.append(entry);

        // Check if we need to flush
        const should_flush_size = self.batch.items.len >= self.config.batch_size;
        const now = std.time.nanoTimestamp();
        const should_flush_time = (now - self.last_flush) >= self.config.flush_interval_ms * 1_000_000;

        if (should_flush_size or should_flush_time) {
            try self.flush();
        }
    }

    /// Flushes batch to remote endpoint
    pub fn flush(self: *RemoteStructuredLogger) !void {
        if (self.batch.items.len == 0) return;

        logger.info("Flushing {} log entries to remote endpoint", .{self.batch.items.len}) catch {};

        // In a real implementation, this would send HTTP request to remote endpoint
        // For now, we simulate the flush
        logger.debug("Sending logs to: {s}", .{self.config.endpoint}) catch {};

        // Clear batch
        for (self.batch.items) |*entry| {
            entry.deinit();
        }
        self.batch.clearRetainingCapacity();
        
        self.last_flush = std.time.nanoTimestamp();
    }
};

/// Performance metrics logger
pub const PerformanceLogger = struct {
    metrics: std.StringHashMap(MetricValue),
    allocator: std.mem.Allocator,

    const MetricValue = union(enum) {
        counter: u64,
        gauge: f64,
        histogram: std.ArrayList(f64),
    };

    /// Initializes performance logger
    pub fn init(allocator: std.mem.Allocator) PerformanceLogger {
        return PerformanceLogger{
            .metrics = std.StringHashMap(MetricValue).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitializes performance logger
    pub fn deinit(self: *PerformanceLogger) void {
        var iterator = self.metrics.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            switch (entry.value_ptr.*) {
                .histogram => |*hist| hist.deinit(),
                else => {},
            }
        }
        self.metrics.deinit();
    }

    /// Increments a counter metric
    pub fn incrementCounter(self: *PerformanceLogger, name: []const u8, value: u64) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        
        if (self.metrics.get(name)) |existing| {
            switch (existing) {
                .counter => |current| {
                    try self.metrics.put(owned_name, MetricValue{ .counter = current + value });
                },
                else => return error.WrongMetricType,
            }
        } else {
            try self.metrics.put(owned_name, MetricValue{ .counter = value });
        }
    }

    /// Sets a gauge metric
    pub fn setGauge(self: *PerformanceLogger, name: []const u8, value: f64) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        try self.metrics.put(owned_name, MetricValue{ .gauge = value });
    }

    /// Records a histogram value
    pub fn recordHistogram(self: *PerformanceLogger, name: []const u8, value: f64) !void {
        const owned_name = try self.allocator.dupe(u8, name);
        
        if (self.metrics.get(name)) |existing| {
            switch (existing) {
                .histogram => |*hist| {
                    try hist.append(value);
                },
                else => return error.WrongMetricType,
            }
        } else {
            var hist = std.ArrayList(f64).init(self.allocator);
            try hist.append(value);
            try self.metrics.put(owned_name, MetricValue{ .histogram = hist });
        }
    }

    /// Logs all metrics
    pub fn logMetrics(self: *const PerformanceLogger) !void {
        var iterator = self.metrics.iterator();
        while (iterator.next()) |entry| {
            const name = entry.key_ptr.*;
            const value = entry.value_ptr.*;

            switch (value) {
                .counter => |counter| {
                    logger.info("Counter {s}: {d}", .{ name, counter }) catch {};
                },
                .gauge => |gauge| {
                    logger.info("Gauge {s}: {d:.2}", .{ name, gauge }) catch {};
                },
                .histogram => |hist| {
                    if (hist.items.len > 0) {
                        var sum: f64 = 0;
                        for (hist.items) |val| {
                            sum += val;
                        }
                        const avg = sum / @as(f64, @floatFromInt(hist.items.len));
                        logger.info("Histogram {s}: count={d}, avg={d:.2}", .{ name, hist.items.len, avg }) catch {};
                    }
                },
            }
        }
    }
};

/// Comprehensive structured logging manager
pub const StructuredLogger = struct {
    file_logger: ?StructuredFileLogger,
    remote_logger: ?RemoteStructuredLogger,
    performance_logger: PerformanceLogger,
    allocator: std.mem.Allocator,

    /// Initializes comprehensive structured logger
    pub fn init(allocator: std.mem.Allocator) StructuredLogger {
        return StructuredLogger{
            .file_logger = null,
            .remote_logger = null,
            .performance_logger = PerformanceLogger.init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitializes structured logger
    pub fn deinit(self: *StructuredLogger) void {
        if (self.file_logger) |*file_logger| {
            file_logger.deinit();
        }
        if (self.remote_logger) |*remote_logger| {
            remote_logger.deinit();
        }
        self.performance_logger.deinit();
    }

    /// Enables file logging
    pub fn enableFileLogging(self: *StructuredLogger, file_path: []const u8, rotation_config: RotationConfig) !void {
        self.file_logger = try StructuredFileLogger.init(self.allocator, file_path, rotation_config);
    }

    /// Enables remote logging
    pub fn enableRemoteLogging(self: *StructuredLogger, config: RemoteLogConfig) void {
        self.remote_logger = RemoteStructuredLogger.init(self.allocator, config);
    }

    /// Logs a structured entry
    pub fn log(self: *StructuredLogger, level: types.LogLevel, message: []const u8, context: ?std.StringHashMap([]const u8)) !void {
        var entry = try LogEntry.init(self.allocator, level, message);
        defer entry.deinit();

        // Add context if provided
        if (context) |ctx| {
            var ctx_iter = ctx.iterator();
            while (ctx_iter.next()) |ctx_entry| {
                try entry.addContext(ctx_entry.key_ptr.*, ctx_entry.value_ptr.*);
            }
        }

        // Log to file if enabled
        if (self.file_logger) |*file_logger| {
            try file_logger.writeEntry(&entry);
        }

        // Log to remote if enabled
        if (self.remote_logger) |*remote_logger| {
            try remote_logger.addEntry(entry);
        }

        // Update performance metrics
        const level_name = @tagName(level);
        try self.performance_logger.incrementCounter(level_name, 1);
    }
};
