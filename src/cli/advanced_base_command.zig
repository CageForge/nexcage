const std = @import("std");
const core = @import("core");

/// Advanced base command with detailed logging and performance tracking
pub const AdvancedBaseCommand = struct {
    logger: ?*core.AdvancedLogging = null,
    command_name: []const u8 = "",
    start_time: ?u64 = null,

    const Self = @This();

    /// Set logger
    pub fn setLogger(self: *Self, logger: *core.AdvancedLogging) void {
        self.logger = logger;
    }

    /// Set command name
    pub fn setCommandName(self: *Self, command_name: []const u8) void {
        self.command_name = command_name;
    }

    /// Log command start with detailed information
    pub fn logCommandStart(self: *const Self, command_name: []const u8, args: []const []const u8) !void {
        if (self.logger) |log| {
            self.start_time = std.time.nanoTimestamp();
            try log.logCommandStart(command_name, args);
            try log.logSystemInfo();
        }
    }

    /// Log command completion with performance metrics
    pub fn logCommandComplete(self: *const Self, command_name: []const u8, success: bool) !void {
        if (self.logger) |log| {
            try log.logCommandComplete(command_name, success);
            
            if (self.start_time) |start| {
                const duration_ms = (std.time.nanoTimestamp() - start) / 1_000_000;
                try log.logPerformance("command_execution", duration_ms, null);
            }
        }
    }

    /// Log operation start
    pub fn logOperationStart(self: *const Self, operation: []const u8, target: []const u8) !void {
        if (self.logger) |log| {
            try log.logOperationStart(operation, target);
        }
    }

    /// Log operation completion
    pub fn logOperationComplete(self: *const Self, operation: []const u8, target: []const u8, success: bool) !void {
        if (self.logger) |log| {
            try log.logOperationComplete(operation, target, success);
        }
    }

    /// Log info message
    pub fn logInfo(self: *const Self, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.info(format, args);
        }
    }

    /// Log debug message
    pub fn logDebug(self: *const Self, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.debug(format, args);
        }
    }

    /// Log warning message
    pub fn logWarn(self: *const Self, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.warn(format, args);
        }
    }

    /// Log error message
    pub fn logError(self: *const Self, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.err(format, args);
        }
    }

    /// Log trace message
    pub fn logTrace(self: *const Self, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.trace(format, args);
        }
    }

    /// Log performance metrics
    pub fn logPerformance(self: *const Self, operation: []const u8, duration_ms: u64, details: ?[]const u8) !void {
        if (self.logger) |log| {
            try log.logPerformance(operation, duration_ms, details);
        }
    }

    /// Log memory usage
    pub fn logMemoryUsage(self: *const Self, allocator_name: []const u8) !void {
        if (self.logger) |log| {
            try log.logMemoryUsage(allocator_name);
        }
    }

    /// Log structured data
    pub fn logStructured(self: *const Self, level: core.LogLevel, message: []const u8, fields: anytype) !void {
        if (self.logger) |log| {
            try log.logStructured(level, message, fields);
        }
    }

    /// Add timer detail
    pub fn addTimerDetail(self: *const Self, command_name: []const u8, detail: []const u8) !void {
        if (self.logger) |log| {
            try log.addTimerDetail(command_name, detail);
        }
    }

    /// Start performance timer
    pub fn startTimer(self: *const Self, command_name: []const u8, operation: []const u8) !void {
        if (self.logger) |log| {
            try log.startTimer(command_name, operation);
        }
    }

    /// Finish performance timer
    pub fn finishTimer(self: *const Self, command_name: []const u8) !void {
        if (self.logger) |log| {
            try log.finishTimer(command_name);
        }
    }

    /// Log command execution with timing
    pub fn executeWithTiming(self: *const Self, command_name: []const u8, args: []const []const u8, execute_fn: anytype) !void {
        try self.logCommandStart(command_name, args);
        
        const start_time = std.time.nanoTimestamp();
        var success = true;
        
        execute_fn() catch |err| {
            success = false;
            try self.logError("Command '{s}' failed: {}", .{ command_name, err });
            return err;
        };
        
        const duration_ms = (std.time.nanoTimestamp() - start_time) / 1_000_000;
        try self.logPerformance("command_execution", duration_ms, null);
        try self.logCommandComplete(command_name, success);
    }
};
