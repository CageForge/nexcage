const std = @import("std");
const builtin = @import("builtin");

/// Advanced logging system with DEBUG mode, file output, and execution timing
pub const AdvancedLogging = struct {
    allocator: std.mem.Allocator,
    console_logger: LogContext,
    file_logger: ?LogContext = null,
    debug_mode: bool = false,
    log_file_path: ?[]const u8 = null,
    execution_timers: std.StringHashMap(ExecutionTimer),

    const Self = @This();

    /// Execution timer for tracking command performance
    pub const ExecutionTimer = struct {
        start_time: u64,
        end_time: ?u64 = null,
        duration_ms: ?u64 = null,
        command_name: []const u8,
        operation: []const u8,
        details: std.ArrayList([]const u8),

        pub fn init(allocator: std.mem.Allocator, command_name: []const u8, operation: []const u8) ExecutionTimer {
            return ExecutionTimer{
                .start_time = @intCast(std.time.nanoTimestamp()),
                .command_name = command_name,
                .operation = operation,
                .details = std.ArrayList([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *ExecutionTimer, allocator: std.mem.Allocator) void {
            self.details.deinit(allocator);
        }

        pub fn finish(self: *ExecutionTimer) void {
            self.end_time = @intCast(std.time.nanoTimestamp());
            self.duration_ms = (self.end_time.? - self.start_time) / 1_000_000;
        }

        pub fn addDetail(self: *ExecutionTimer, detail: []const u8) !void {
            try self.details.append(detail);
        }
    };

    /// Initialize advanced logging system
    pub fn init(allocator: std.mem.Allocator, debug_mode: bool, log_file_path: ?[]const u8) !Self {
        const console_logger = LogContext.init(allocator, std.fs.File.stdout().writer(&[_]u8{} ** 0), .debug, "nexcage");
        
        var file_logger: ?LogContext = null;
        if (log_file_path) |path| {
            const file = try std.fs.cwd().createFile(path, .{});
            var buffer: [1024]u8 = undefined;
            file_logger = LogContext.init(allocator, file.writer(&buffer), .debug, "nexcage");
        }

        return Self{
            .allocator = allocator,
            .console_logger = console_logger,
            .file_logger = file_logger,
            .debug_mode = debug_mode,
            .log_file_path = log_file_path,
            .execution_timers = std.StringHashMap(ExecutionTimer).init(allocator),
        };
    }

    /// Deinitialize logging system
    pub fn deinit(self: *Self) void {
        // Close file logger if exists
        if (self.file_logger) |*logger| {
            logger.deinit();
        }

        // Cleanup execution timers
        var iterator = self.execution_timers.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.execution_timers.deinit();

        // Free log file path if allocated
        if (self.log_file_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Start execution timer for a command
    pub fn startTimer(self: *Self, command_name: []const u8, operation: []const u8) !void {
        const timer = ExecutionTimer.init(self.allocator, command_name, operation);
        try self.execution_timers.put(command_name, timer);
        
        if (self.debug_mode) {
            try self.debug("Started execution timer for command: {s} - {s}", .{ command_name, operation });
        }
    }

    /// Finish execution timer and log results
    pub fn finishTimer(self: *Self, command_name: []const u8) !void {
        if (self.execution_timers.getPtr(command_name)) |timer| {
            timer.finish();
            
            if (self.debug_mode) {
                try self.debug("Command '{s}' completed in {d}ms", .{ command_name, timer.duration_ms.? });
                
                // Log execution details
                for (timer.details.items) |detail| {
                    try self.debug("  Detail: {s}", .{detail});
                }
            }
            
            // Log execution summary
            try self.info("Command '{s}' executed successfully in {d}ms", .{ command_name, timer.duration_ms.? });
            
            // Cleanup timer
            timer.deinit(self.allocator);
            _ = self.execution_timers.remove(command_name);
        }
    }

    /// Add detail to current execution timer
    pub fn addTimerDetail(self: *Self, command_name: []const u8, detail: []const u8) !void {
        if (self.execution_timers.getPtr(command_name)) |timer| {
            try timer.addDetail(detail);
        }
    }

    /// Log with both console and file output
    fn log(self: *Self, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        // Log to console using public methods
        switch (level) {
            .trace => try self.console_logger.trace(format, args),
            .debug => try self.console_logger.debug(format, args),
            .info => try self.console_logger.info(format, args),
            .warn => try self.console_logger.warn(format, args),
            .@"error" => try self.console_logger.err(format, args),
            .fatal => try self.console_logger.fatal(format, args),
        }
        
        // Log to file if enabled
        if (self.file_logger) |*logger| {
            switch (level) {
                .trace => try logger.trace(format, args),
                .debug => try logger.debug(format, args),
                .info => try logger.info(format, args),
                .warn => try logger.warn(format, args),
                .@"error" => try logger.err(format, args),
                .fatal => try logger.fatal(format, args),
            }
        }
    }

    /// Trace level logging
    pub fn trace(self: *Self, comptime format: []const u8, args: anytype) !void {
        if (self.debug_mode) {
            try self.log(.trace, format, args);
        }
    }

    /// Debug level logging
    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) !void {
        if (self.debug_mode) {
            try self.log(.debug, format, args);
        }
    }

    /// Info level logging
    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.info, format, args);
    }

    /// Warning level logging
    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.warn, format, args);
    }

    /// Error level logging
    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.@"error", format, args);
    }

    /// Fatal level logging
    pub fn fatal(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.fatal, format, args);
    }

    /// Log command execution start
    pub fn logCommandStart(self: *Self, command_name: []const u8, args: []const []const u8) !void {
        try self.startTimer(command_name, "command_execution");
        
        const args_str = if (args.len > 0) 
            try std.fmt.allocPrint(self.allocator, " with args: {s}", .{std.mem.join(self.allocator, " ", args)})
        else 
            "";
        defer if (args.len > 0) self.allocator.free(args_str);
        
        try self.info("Starting command: {s}{s}", .{ command_name, args_str });
        
        if (self.debug_mode) {
            try self.debug("Command execution environment:", .{});
            try self.debug("  Debug mode: enabled", .{});
            try self.debug("  Log file: {s}", .{self.log_file_path orelse "none"});
            try self.debug("  Timestamp: {d}", .{std.time.timestamp()});
        }
    }

    /// Log command execution completion
    pub fn logCommandComplete(self: *Self, command_name: []const u8, success: bool) !void {
        try self.finishTimer(command_name);
        
        if (success) {
            try self.info("Command '{s}' completed successfully", .{command_name});
        } else {
            try self.err("Command '{s}' failed", .{command_name});
        }
    }

    /// Log operation start
    pub fn logOperationStart(self: *Self, operation: []const u8, target: []const u8) !void {
        try self.info("Starting operation: {s} on {s}", .{ operation, target });
        
        if (self.debug_mode) {
            try self.debug("Operation details:", .{});
            try self.debug("  Operation: {s}", .{operation});
            try self.debug("  Target: {s}", .{target});
            try self.debug("  Start time: {d}", .{std.time.timestamp()});
        }
    }

    /// Log operation completion
    pub fn logOperationComplete(self: *Self, operation: []const u8, target: []const u8, success: bool) !void {
        if (success) {
            try self.info("Operation '{s}' on '{s}' completed successfully", .{ operation, target });
        } else {
            try self.err("Operation '{s}' on '{s}' failed", .{ operation, target });
        }
    }

    /// Log performance metrics
    pub fn logPerformance(self: *Self, operation: []const u8, duration_ms: u64, details: ?[]const u8) !void {
        try self.info("Performance: {s} took {d}ms", .{ operation, duration_ms });
        
        if (self.debug_mode and details) |d| {
            try self.debug("Performance details: {s}", .{d});
        }
    }

    /// Log system information
    pub fn logSystemInfo(self: *Self) !void {
        if (self.debug_mode) {
            try self.debug("System Information:", .{});
            try self.debug("  OS: {s}", .{@tagName(builtin.os.tag)});
            try self.debug("  Architecture: {s}", .{@tagName(builtin.cpu.arch)});
            try self.debug("  Target: {s}", .{builtin.target});
            try self.debug("  Zig version: {s}", .{builtin.zig_version_string});
        }
    }

    /// Log memory usage
    pub fn logMemoryUsage(self: *Self, allocator_name: []const u8) !void {
        if (self.debug_mode) {
            // Note: This is a simplified memory logging
            // In a real implementation, you'd want to track actual memory usage
            try self.debug("Memory usage for {s}: [tracking not implemented]", .{allocator_name});
        }
    }

    /// Create structured log entry
    pub fn logStructured(self: *Self, level: LogLevel, message: []const u8, fields: anytype) !void {
        const timestamp = std.time.timestamp();
        const level_str = self.getLevelString(level);
        
        // Create structured log entry
        const log_entry = try std.fmt.allocPrint(self.allocator, 
            "{{\"timestamp\":{d},\"level\":\"{s}\",\"component\":\"nexcage\",\"message\":\"{s}\"", 
            .{ timestamp, level_str, message }
        );
        defer self.allocator.free(log_entry);
        
        // Add fields if provided
        if (@TypeOf(fields) != @TypeOf({})) {
            const fields_str = try std.fmt.allocPrint(self.allocator, ",\"fields\":{s}", .{@as([]const u8, "{}")});
            defer self.allocator.free(fields_str);
            
            const full_entry = try std.fmt.allocPrint(self.allocator, "{s}{s}}}", .{ log_entry, fields_str });
            defer self.allocator.free(full_entry);
            
            try self.log(level, "{s}", .{full_entry});
        } else {
            const full_entry = try std.fmt.allocPrint(self.allocator, "{s}}}", .{log_entry});
            defer self.allocator.free(full_entry);
            
            try self.log(level, "{s}", .{full_entry});
        }
    }

    /// Get level string
    fn getLevelString(self: *Self, level: LogLevel) []const u8 {
        _ = self;
        return switch (level) {
            .trace => "trace",
            .debug => "debug", 
            .info => "info",
            .warn => "warn",
            .@"error" => "error",
            .fatal => "fatal",
        };
    }
};

/// Re-export LogLevel for compatibility
pub const LogLevel = @import("logging.zig").LogLevel;
pub const LogContext = @import("logging.zig").LogContext;
