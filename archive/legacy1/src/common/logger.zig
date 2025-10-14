/// Logging system for Proxmox LXCRI container runtime
///
/// This module provides a global logging interface with support for multiple
/// log levels, file and console output, and proper resource management.
/// The logger integrates with the error handling system and provides
/// structured logging capabilities throughout the application.
const std = @import("std");
const types = @import("types");
const errors = @import("error");

/// Logger-specific error set for handling logging operations
///
/// These errors cover all possible failure modes during logging operations,
/// including I/O errors, memory allocation failures, and system resource issues.
pub const LoggerError = error{
    WriterError,
    AllocationError,
    NotInitialized,
    OutOfMemory,
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    DeviceBusy,
    InvalidArgument,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForWriting,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    Unexpected,
};

/// Type alias for backward compatibility with existing code
pub const Logger = types.LogContext;

/// Global logger instance shared across the application
var global_logger: ?types.LogContext = null;

/// Initializes the global logger with a file writer
///
/// Sets up the global logging system with the specified parameters. If a global
/// logger already exists, it will be properly cleaned up before creating the new one.
///
/// Arguments:
/// - allocator: Memory allocator for logger operations
/// - writer: File writer for log output
/// - level: Minimum log level to output
///
/// Returns: LoggerError if initialization fails
pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: types.LogLevel) LoggerError!void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try types.LogContext.init(allocator, writer, level, "global");
}

/// Initializes the global logger with a file handle
///
/// Alternative initialization method that takes a file handle directly
/// instead of a writer. Useful for more complex file management scenarios.
///
/// Arguments:
/// - allocator: Memory allocator for logger operations
/// - file: File handle for log output
/// - level: Minimum log level to output
/// - name: Name identifier for this logger instance
///
/// Returns: Error if initialization fails
pub fn initWithFile(allocator: std.mem.Allocator, file: std.fs.File, level: types.LogLevel, name: []const u8) !void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try types.LogContext.initWithFile(allocator, file, level, name);
}

/// Cleanly shuts down the global logger
///
/// Properly deinitializes the global logger and frees all associated resources.
/// Safe to call multiple times or when no logger is initialized.
pub fn deinit() void {
    if (global_logger) |*logger| {
        logger.deinit();
        global_logger = null;
    }
}

/// Logs a debug-level message
///
/// Outputs a formatted message at debug level. Message will only be output
/// if the global logger is initialized and the current log level permits debug messages.
///
/// Arguments:
/// - fmt: Format string (compile-time)
/// - args: Arguments for the format string
///
/// Returns: LoggerError if logging fails
pub fn debug(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.debug(fmt, args);
    }
}

/// Logs an info-level message
///
/// Outputs a formatted message at info level. This is the standard level
/// for operational information and status updates.
///
/// Arguments:
/// - fmt: Format string (compile-time)
/// - args: Arguments for the format string
///
/// Returns: LoggerError if logging fails
pub fn info(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.info(fmt, args);
    }
}

/// Logs a warning-level message
///
/// Outputs a formatted message at warning level. Used for non-fatal issues
/// that should be brought to the user's attention.
///
/// Arguments:
/// - fmt: Format string (compile-time)
/// - args: Arguments for the format string
///
/// Returns: LoggerError if logging fails
pub fn warn(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.warn(fmt, args);
    }
}

/// Logs an error-level message
///
/// Outputs a formatted message at error level. Used for serious issues
/// that indicate failures or problems requiring attention.
///
/// Arguments:
/// - fmt: Format string (compile-time)
/// - args: Arguments for the format string
///
/// Returns: LoggerError if logging fails
pub fn err(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.err(fmt, args);
    }
}
