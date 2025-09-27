const std = @import("std");
const types = @import("types.zig");

/// Error system for the application
/// Error context for better error reporting
pub const ErrorContext = struct {
    allocator: std.mem.Allocator,
    message: []const u8,
    source: ?[]const u8 = null,
    line: ?u32 = null,
    column: ?u32 = null,
    stack_trace: ?[]const u8 = null,

    pub fn deinit(self: *ErrorContext) void {
        self.allocator.free(self.message);
        if (self.source) |s| self.allocator.free(s);
        if (self.stack_trace) |st| self.allocator.free(st);
    }
};

/// Error handler interface
pub const ErrorHandler = struct {
    const Self = @This();

    /// Handle error with context
    handle: *const fn (self: *Self, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) void,

    /// Log error
    log: *const fn (self: *Self, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) void,

    /// Recover from error
    recover: *const fn (self: *Self, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) bool,
};

/// Default error handler implementation
pub const DefaultErrorHandler = struct {
    allocator: std.mem.Allocator,
    logger: ?*std.io.Writer(std.fs.File, std.fs.File.WriteError) = null,

    pub fn init(allocator: std.mem.Allocator, logger: ?*std.io.Writer(std.fs.File, std.fs.File.WriteError)) DefaultErrorHandler {
        return DefaultErrorHandler{
            .allocator = allocator,
            .logger = logger,
        };
    }

    pub fn handle(self: *DefaultErrorHandler, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) void {
        _ = allocator;

        const error_message = self.getErrorMessage(error_type);

        if (self.logger) |logger| {
            logger.print("Error: {s}", .{error_message}) catch {};

            if (context) |ctx| {
                logger.print("Context: {s}", .{ctx.message}) catch {};
                if (ctx.source) |src| {
                    logger.print("Source: {s}", .{src}) catch {};
                }
                if (ctx.line) |line| {
                    logger.print("Line: {d}", .{line}) catch {};
                }
                if (ctx.column) |col| {
                    logger.print("Column: {d}", .{col}) catch {};
                }
            }
        }

        if (context) |ctx| {
            ctx.deinit();
        }
    }

    pub fn log(self: *DefaultErrorHandler, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) void {
        self.handle(error_type, context, allocator);
    }

    pub fn recover(self: *DefaultErrorHandler, error_type: types.Error, context: ?ErrorContext, allocator: std.mem.Allocator) bool {
        _ = self;
        _ = error_type;
        _ = context;
        _ = allocator;

        // Default implementation: no recovery
        return false;
    }

    fn getErrorMessage(self: *DefaultErrorHandler, error_type: types.Error) []const u8 {
        _ = self;

        return switch (error_type) {
            .InvalidConfig => "Invalid configuration",
            .NetworkError => "Network operation failed",
            .StorageError => "Storage operation failed",
            .RuntimeError => "Runtime operation failed",
            .ValidationError => "Validation failed",
            .NotFound => "Resource not found",
            .PermissionDenied => "Permission denied",
            .Timeout => "Operation timed out",
            .OutOfMemory => "Out of memory",
            .InvalidInput => "Invalid input",
            .OperationFailed => "Operation failed",
            .UnsupportedOperation => "Unsupported operation",
        };
    }
};

/// Error recovery strategies
pub const ErrorRecovery = struct {
    /// Retry strategy
    pub const RetryStrategy = struct {
        max_attempts: u32,
        delay_ms: u64,
        exponential_backoff: bool = false,

        pub fn shouldRetry(self: *RetryStrategy, attempt: u32) bool {
            return attempt < self.max_attempts;
        }

        pub fn getDelay(self: *RetryStrategy, attempt: u32) u64 {
            if (self.exponential_backoff) {
                return self.delay_ms * (@as(u64, 1) << @intCast(attempt));
            }
            return self.delay_ms;
        }
    };

    /// Fallback strategy
    pub const FallbackStrategy = struct {
        fallback_function: *const fn (allocator: std.mem.Allocator) anyerror!void,

        pub fn execute(self: *FallbackStrategy, allocator: std.mem.Allocator) !void {
            return self.fallback_function(allocator);
        }
    };
};

/// Error reporting utilities
pub const ErrorReporter = struct {
    allocator: std.mem.Allocator,
    handler: ErrorHandler,

    pub fn init(allocator: std.mem.Allocator, handler: ErrorHandler) ErrorReporter {
        return ErrorReporter{
            .allocator = allocator,
            .handler = handler,
        };
    }

    pub fn report(self: *ErrorReporter, error_type: types.Error, message: []const u8) void {
        const context = ErrorContext{
            .allocator = self.allocator,
            .message = self.allocator.dupe(u8, message) catch return,
        };

        self.handler.handle(error_type, context, self.allocator);
    }

    pub fn reportWithSource(self: *ErrorReporter, error_type: types.Error, message: []const u8, source: []const u8, line: u32, column: u32) void {
        const context = ErrorContext{
            .allocator = self.allocator,
            .message = self.allocator.dupe(u8, message) catch return,
            .source = self.allocator.dupe(u8, source) catch return,
            .line = line,
            .column = column,
        };

        self.handler.handle(error_type, context, self.allocator);
    }
};
