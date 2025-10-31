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

/// Error context builder for easy error creation with context
pub const ErrorContextBuilder = struct {
    allocator: std.mem.Allocator,
    context: ErrorContext,

    pub fn init(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ErrorContextBuilder {
        const message = try std.fmt.allocPrint(allocator, fmt, args);
        return ErrorContextBuilder{
            .allocator = allocator,
            .context = ErrorContext{
                .allocator = allocator,
                .message = message,
                .source = null,
                .line = null,
                .column = null,
                .stack_trace = null,
            },
        };
    }

    pub fn withSource(self: *ErrorContextBuilder, source: []const u8) !void {
        self.context.source = try self.allocator.dupe(u8, source);
    }

    pub fn withLocation(self: *ErrorContextBuilder, line: u32, column: u32) void {
        self.context.line = line;
        self.context.column = column;
    }

    pub fn withStackTrace(self: *ErrorContextBuilder, stack_trace: []const u8) !void {
        self.context.stack_trace = try self.allocator.dupe(u8, stack_trace);
    }

    pub fn build(self: *ErrorContextBuilder) ErrorContext {
        const context = self.context;
        // Don't free here - caller owns the context
        return context;
    }

    pub fn deinit(self: *ErrorContextBuilder) void {
        self.context.deinit();
    }
};

/// Helper functions for creating errors with context
pub fn createErrorContext(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !ErrorContext {
    const message = try std.fmt.allocPrint(allocator, fmt, args);
    return ErrorContext{
        .allocator = allocator,
        .message = message,
        .source = null,
        .line = null,
        .column = null,
        .stack_trace = null,
    };
}

/// Create error context with file location
pub fn createErrorContextWithSource(
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
    source_file: []const u8,
    line: u32,
) !ErrorContext {
    const message = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(message);
    
    const source = try allocator.dupe(u8, source_file);
    errdefer allocator.free(source);
    
    return ErrorContext{
        .allocator = allocator,
        .message = message,
        .source = source,
        .line = line,
        .column = null,
        .stack_trace = null,
    };
}

/// Error wrapper that preserves context
pub const ContextualError = struct {
    error_type: types.Error,
    context: ?ErrorContext = null,
    cause: ?anyerror = null,

    pub fn init(error_type: types.Error) ContextualError {
        return ContextualError{
            .error_type = error_type,
            .context = null,
            .cause = null,
        };
    }

    pub fn withContext(self: ContextualError, context: ErrorContext) ContextualError {
        return ContextualError{
            .error_type = self.error_type,
            .context = context,
            .cause = self.cause,
        };
    }

    pub fn withCause(self: ContextualError, cause: anyerror) ContextualError {
        return ContextualError{
            .error_type = self.error_type,
            .context = self.context,
            .cause = cause,
        };
    }

    pub fn format(self: ContextualError, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{}", .{self.error_type});
        if (self.context) |ctx| {
            try writer.print(": {s}", .{ctx.message});
        }
        if (self.cause) |c| {
            try writer.print(" (caused by: {})", .{c});
        }
    }

    pub fn deinit(self: *ContextualError, allocator: std.mem.Allocator) void {
        _ = allocator;
        if (self.context) |*ctx| {
            ctx.deinit();
        }
    }
};

/// Enhanced error types with context support
pub const ErrorWithContext = union(enum) {
    simple: types.Error,
    contextual: struct {
        error_type: types.Error,
        context: ErrorContext,
    },
    chained: struct {
        error_type: types.Error,
        context: ErrorContext,
        cause: *ErrorWithContext,
    },

    pub fn format(self: ErrorWithContext, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .simple => |err| {
                _ = fmt;
                _ = options;
                try writer.print("{}", .{err});
            },
            .contextual => |e| {
                _ = fmt;
                _ = options;
                try writer.print("{}: {s}", .{ e.error_type, e.context.message });
                if (e.context.source) |src| {
                    try writer.print(" (source: {s}", .{src});
                    if (e.context.line) |line| {
                        try writer.print(", line: {d}", .{line});
                    }
                    try writer.writeAll(")");
                }
            },
            .chained => |e| {
                try writer.print("{}: {s}", .{ e.error_type, e.context.message });
                try writer.writeAll(" -> ");
                try e.cause.format(fmt, options, writer);
            },
        }
    }
};
