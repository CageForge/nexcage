const std = @import("std");
const core = @import("core");

/// Base command interface that provides consistent logger handling
/// All CLI commands should embed this struct to get standardized logging support
pub const BaseCommand = struct {
    logger: ?*core.LogContext = null,

    /// Set the logger for this command
    pub fn setLogger(self: *BaseCommand, logger: *core.LogContext) void {
        self.logger = logger;
    }

    /// Log an info message if logger is available
    pub fn logInfo(self: *const BaseCommand, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.info(format, args);
        }
    }

    /// Log a warning message if logger is available
    pub fn logWarn(self: *const BaseCommand, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.warn(format, args);
        }
    }

    /// Log an error message if logger is available
    pub fn logError(self: *const BaseCommand, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.err(format, args);
        }
    }

    /// Log command start
    pub fn logCommandStart(self: *const BaseCommand, command_name: []const u8) !void {
        try self.logInfo("Executing {s} command", .{command_name});
    }

    /// Log command completion
    pub fn logCommandComplete(self: *const BaseCommand, command_name: []const u8) !void {
        try self.logInfo("{s} command completed successfully", .{command_name});
    }

    /// Log command operation with context
    pub fn logOperation(self: *const BaseCommand, operation: []const u8, target: []const u8) !void {
        try self.logInfo("{s} {s}", .{ operation, target });
    }
};

/// Helper macro for embedding BaseCommand in CLI command structs
/// Usage: const base = LoggerMixin(@This());
pub fn LoggerMixin(comptime CommandType: type) type {
    return struct {
        pub fn setLogger(self: *CommandType, logger: *core.LogContext) void {
            self.base.setLogger(logger);
        }

        pub fn logInfo(self: *const CommandType, comptime format: []const u8, args: anytype) !void {
            try self.base.logInfo(format, args);
        }

        pub fn logWarn(self: *const CommandType, comptime format: []const u8, args: anytype) !void {
            try self.base.logWarn(format, args);
        }

        pub fn logError(self: *const CommandType, comptime format: []const u8, args: anytype) !void {
            try self.base.logError(format, args);
        }

        pub fn logCommandStart(self: *const CommandType, command_name: []const u8) !void {
            try self.base.logCommandStart(command_name);
        }

        pub fn logCommandComplete(self: *const CommandType, command_name: []const u8) !void {
            try self.base.logCommandComplete(command_name);
        }

        pub fn logOperation(self: *const CommandType, operation: []const u8, target: []const u8) !void {
            try self.base.logOperation(operation, target);
        }
    };
}
