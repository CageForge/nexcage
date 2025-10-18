const std = @import("std");
const builtin = @import("builtin");

/// Simple advanced logging system with DEBUG mode and file output
pub const SimpleAdvancedLogging = struct {
    allocator: std.mem.Allocator,
    console_logger: LogContext,
    file_logger: ?LogContext = null,
    debug_mode: bool = false,
    log_file_path: ?[]const u8 = null,
    command_start_time: ?u64 = null,

    const Self = @This();

    /// Initialize simple advanced logging system
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
        };
    }

    /// Deinitialize logging system
    pub fn deinit(self: *Self) void {
        // Close file logger if exists
        if (self.file_logger) |*logger| {
            logger.deinit();
        }

        // Note: log_file_path is owned by LoggingConfig, not by us
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
        self.command_start_time = @intCast(std.time.nanoTimestamp());
        
        if (args.len > 0) {
            const joined_args = try std.mem.join(self.allocator, " ", args);
            defer self.allocator.free(joined_args);
            const args_str = try std.fmt.allocPrint(self.allocator, " with args: {s}", .{joined_args});
            defer self.allocator.free(args_str);
            try self.info("Starting command: {s}{s}", .{ command_name, args_str });
        } else {
            try self.info("Starting command: {s}", .{command_name});
        }
        
        if (self.debug_mode) {
            try self.debug("Command execution environment:", .{});
            try self.debug("  Debug mode: enabled", .{});
            try self.debug("  Log file: {s}", .{self.log_file_path orelse "none"});
            try self.debug("  Timestamp: {d}", .{std.time.timestamp()});
        }
    }

    /// Log command execution completion
    pub fn logCommandComplete(self: *Self, command_name: []const u8, success: bool) !void {
        if (self.command_start_time) |start_time| {
            const duration_ms = (@as(u64, @intCast(std.time.nanoTimestamp())) - start_time) / 1_000_000;
            try self.info("Command '{s}' completed in {d}ms", .{ command_name, duration_ms });
        }
        
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
            try self.debug("  Target: {s}", .{"native"});
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
};

/// Re-export LogLevel and LogContext for compatibility
pub const LogLevel = @import("logging.zig").LogLevel;
pub const LogContext = @import("logging.zig").LogContext;
