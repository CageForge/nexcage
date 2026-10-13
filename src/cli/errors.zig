const std = @import("std");
const core = @import("core");

/// Standardized CLI Error Types
/// This module provides consistent error handling across all CLI commands
pub const CliError = error{
    /// Input validation failed (missing required arguments, invalid formats, etc.)
    InvalidInput,

    /// Requested command was not found in the registry
    CommandNotFound,

    /// Operation is not supported by the current backend/configuration
    UnsupportedOperation,

    /// Operation failed during execution
    OperationFailed,

    /// Help was requested (not really an error, but used for control flow)
    HelpRequested,

    /// System-level errors (memory allocation, file I/O, etc.)
    SystemError,
};

/// Error handling utilities for CLI commands
pub const ErrorHandler = struct {
    logger: ?*core.LogContext,

    pub fn init(logger: ?*core.LogContext) ErrorHandler {
        return ErrorHandler{ .logger = logger };
    }

    /// Log and return InvalidInput error with context
    pub fn invalidInput(self: *const ErrorHandler, comptime message: []const u8, args: anytype) CliError {
        if (self.logger) |log| {
            log.err(message, args) catch {};
        }
        return CliError.InvalidInput;
    }
};

/// Create a standardized error handler for a command
pub fn createErrorHandler(logger: ?*core.LogContext) ErrorHandler {
    return ErrorHandler.init(logger);
}
