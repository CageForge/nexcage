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
    pub fn invalidInput(self: *const ErrorHandler, message: []const u8, args: anytype) CliError {
        if (self.logger) |log| {
            log.err(message, args) catch {};
        }
        return CliError.InvalidInput;
    }

    /// Log and return CommandNotFound error
    pub fn commandNotFound(self: *const ErrorHandler, command: []const u8) CliError {
        if (self.logger) |log| {
            log.err("Command '{s}' not found", .{command}) catch {};
        }
        return CliError.CommandNotFound;
    }

    /// Log and return UnsupportedOperation error with context
    pub fn unsupportedOperation(self: *const ErrorHandler, operation: []const u8, context: []const u8) CliError {
        if (self.logger) |log| {
            log.err("Operation '{s}' not supported: {s}", .{ operation, context }) catch {};
        }
        return CliError.UnsupportedOperation;
    }

    /// Log and return OperationFailed error with context
    pub fn operationFailed(self: *const ErrorHandler, operation: []const u8, reason: []const u8) CliError {
        if (self.logger) |log| {
            log.err("Operation '{s}' failed: {s}", .{ operation, reason }) catch {};
        }
        return CliError.OperationFailed;
    }

    /// Convert core errors to CLI errors
    pub fn fromCoreError(core_error: anyerror) CliError {
        return switch (core_error) {
            core.Error.InvalidInput => CliError.InvalidInput,
            core.Error.UnsupportedOperation => CliError.UnsupportedOperation,
            core.types.Error.InvalidInput => CliError.InvalidInput,
            core.types.Error.NotFound => CliError.CommandNotFound,
            core.types.Error.OperationFailed => CliError.OperationFailed,
            else => CliError.SystemError,
        };
    }

    /// Convert any error to CLI error with logging
    pub fn handleError(self: *const ErrorHandler, err: anyerror, context: []const u8) CliError {
        const cli_error = fromCoreError(err);

        if (self.logger) |log| {
            log.err("Error in {s}: {any}", .{ context, err }) catch {};
        }

        return cli_error;
    }
};

/// Create a standardized error handler for a command
pub fn createErrorHandler(logger: ?*core.LogContext) ErrorHandler {
    return ErrorHandler.init(logger);
}
