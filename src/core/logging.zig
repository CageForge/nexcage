const std = @import("std");

/// Logging system for the application
/// Log levels
pub const LogLevel = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    @"error" = 4,
    fatal = 5,
};

/// Log context
pub const LogContext = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    level: LogLevel,
    component: []const u8,
    timestamp: bool = true,
    colorize: bool = true,

    pub fn init(allocator: std.mem.Allocator, _: std.fs.File.Writer, level: LogLevel, component: []const u8) LogContext {
        // In Zig 0.15.1, Writer doesn't expose file directly, so we store File separately
        // For stdout, we use stdout() directly
        const stdout = std.fs.File.stdout();
        return LogContext{
            .allocator = allocator,
            .file = stdout,
            .level = level,
            .component = component,
        };
    }

    pub fn deinit(self: *LogContext) void {
        _ = self;
    }

    pub fn trace(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.trace, format, args);
    }

    pub fn debug(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.debug, format, args);
    }

    pub fn info(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.info, format, args);
    }

    pub fn warn(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.warn, format, args);
    }

    pub fn err(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.@"error", format, args);
    }

    pub fn fatal(self: *LogContext, comptime format: []const u8, args: anytype) !void {
        try self.log(.fatal, format, args);
    }

    fn log(self: *LogContext, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        // Safety check: validate self pointer and fields before any access
        // Use stderr for debug output to avoid recursion
        const stderr = std.fs.File.stderr();
        stderr.writeAll("[LOG] log: Starting\n") catch {};
        
        // Check self pointer validity by accessing fields
        stderr.writeAll("[LOG] log: Checking self.level\n") catch {};
        const current_level = self.level;
        const current_level_int: u8 = @intFromEnum(current_level);
        stderr.writeAll("[LOG] log: self.level checked\n") catch {};
        
        // Early return if log level is below threshold
        stderr.writeAll("[LOG] log: Checking log level threshold\n") catch {};
        const level_int = @intFromEnum(level);
        const threshold_int: u8 = if (current_level_int <= @intFromEnum(LogLevel.fatal)) current_level_int else @intFromEnum(LogLevel.info);
        
        if (level_int < threshold_int) {
            stderr.writeAll("[LOG] log: Log level below threshold, returning\n") catch {};
            return;
        }
        stderr.writeAll("[LOG] log: Log level OK, continuing\n") catch {};
        
        // Use page_allocator for logger to avoid segfault from invalid allocator
        // The logger's allocator might become invalid during execution
        const safe_allocator = std.heap.page_allocator;
        
        stderr.writeAll("[LOG] log: Before allocator test\n") catch {};
        const test_alloc = safe_allocator.alloc(u8, 1) catch {
            stderr.writeAll("[LOG] log: Allocator test failed, skipping\n") catch {};
            return;
        };
        defer safe_allocator.free(test_alloc);
        stderr.writeAll("[LOG] log: Allocator test passed\n") catch {};

        stderr.writeAll("[LOG] log: Getting timestamp\n") catch {};
        const timestamp = if (self.timestamp) blk: {
            const now = std.time.timestamp();
            const seconds = @as(u64, @intCast(now));
            break :blk seconds;
        } else 0;
        stderr.writeAll("[LOG] log: Timestamp obtained\n") catch {};

        stderr.writeAll("[LOG] log: Getting level strings\n") catch {};
        const level_str = self.getLevelString(level);
        const color = if (self.colorize) self.getLevelColor(level) else "";
        const reset = if (self.colorize) "\x1b[0m" else "";
        stderr.writeAll("[LOG] log: Level strings obtained\n") catch {};

        stderr.writeAll("[LOG] log: Before allocPrint\n") catch {};
        
        if (self.timestamp) {
            const message = std.fmt.allocPrint(safe_allocator, "{s}[{d}] {s}{s} {s}: " ++ format ++ "{s}\n", .{
                color,
                timestamp,
                level_str,
                reset,
                self.component,
            } ++ args ++ .{reset}) catch {
                stderr.writeAll("[LOG] log: allocPrint failed, skipping\n") catch {};
                return;
            };
            defer safe_allocator.free(message);
            stderr.writeAll("[LOG] log: allocPrint succeeded, len = ") catch {};
            const len_str = try std.fmt.allocPrint(safe_allocator, "{d}", .{message.len});
            defer safe_allocator.free(len_str);
            stderr.writeAll(len_str) catch {};
            stderr.writeAll("\n") catch {};
            stderr.writeAll("[LOG] log: Before file.writeAll\n") catch {};
            // Use file.writeAll directly to avoid segfault
            self.file.writeAll(message) catch {
                stderr.writeAll("[LOG] log: file.writeAll failed\n") catch {};
            };
            stderr.writeAll("[LOG] log: file.writeAll completed\n") catch {};
        } else {
            const message = std.fmt.allocPrint(safe_allocator, "{s}{s} {s}: " ++ format ++ "{s}\n", .{
                color,
                level_str,
                self.component,
            } ++ args ++ .{reset}) catch {
                stderr.writeAll("[LOG] log: allocPrint failed (no timestamp), skipping\n") catch {};
                return;
            };
            defer safe_allocator.free(message);
            stderr.writeAll("[LOG] log: Before file.writeAll (no timestamp)\n") catch {};
            // Use file.writeAll directly to avoid segfault
            self.file.writeAll(message) catch {
                stderr.writeAll("[LOG] log: file.writeAll failed (no timestamp)\n") catch {};
            };
            stderr.writeAll("[LOG] log: file.writeAll completed (no timestamp)\n") catch {};
        }
        stderr.writeAll("[LOG] log: Finished\n") catch {};
    }

    fn getLevelString(self: *LogContext, level: LogLevel) []const u8 {
        _ = self;
        return switch (level) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO ",
            .warn => "WARN ",
            .@"error" => "ERROR",
            .fatal => "FATAL",
        };
    }

    fn getLevelColor(self: *LogContext, level: LogLevel) []const u8 {
        _ = self;
        return switch (level) {
            .trace => "\x1b[90m", // gray
            .debug => "\x1b[36m", // cyan
            .info => "\x1b[32m", // green
            .warn => "\x1b[33m", // yellow
            .@"error" => "\x1b[31m", // red
            .fatal => "\x1b[35m", // magenta
        };
    }
};

/// Structured logging
pub const StructuredLogger = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    level: LogLevel,
    component: []const u8,

    pub fn init(allocator: std.mem.Allocator, writer: std.io.Writer(std.fs.File, std.fs.File.WriteError), level: LogLevel, component: []const u8) StructuredLogger {
        return StructuredLogger{
            .allocator = allocator,
            .writer = writer,
            .level = level,
            .component = component,
        };
    }

    pub fn deinit(self: *StructuredLogger) void {
        _ = self;
    }

    pub fn log(self: *StructuredLogger, level: LogLevel, message: []const u8, fields: anytype) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        const timestamp = std.time.timestamp();
        const level_str = self.getLevelString(level);

        // Create JSON-like structured log using single writer
        // Use the provided writer for structured logger
        var writer = self.writer;
        try writer.print("{{\"timestamp\":{d},\"level\":\"{s}\",\"component\":\"{s}\",\"message\":\"{s}\"", .{
            timestamp,
            level_str,
            self.component,
            message,
        });

        // Add fields if provided
        if (@TypeOf(fields) != @TypeOf({})) {
            try writer.print(",\"fields\":{{", .{});

            const fields_info = @typeInfo(@TypeOf(fields));
            if (fields_info == .Struct) {
                inline for (fields_info.Struct.fields, 0..) |field, i| {
                    if (i > 0) try writer.print(",", .{});
                    try writer.print("\"{s}\":", .{field.name});

                    const field_value = @field(fields, field.name);
                    try self.logValueWithWriter(writer, field_value);
                }
            }

            try writer.print("}}", .{});
        }

        try writer.print("}}\n", .{});
    }

    fn logValue(self: *StructuredLogger, value: anytype) !void {
        try self.logValueWithWriter(self.writer, value);
    }

    fn logValueWithWriter(writer: std.fs.File.Writer, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Int, .Float => try writer.print("{d}", .{value}),
            .Bool => try writer.print("{}", .{value}),
            .Pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    try writer.print("\"{s}\"", .{value});
                } else {
                    try writer.print("\"<pointer>\"", .{});
                }
            },
            .Optional => |_| {
                if (value) |v| {
                    try logValueWithWriter(writer, v);
                } else {
                    try writer.print("null", .{});
                }
            },
            else => try writer.print("\"<unknown>\"", .{}),
        }
    }

    fn getLevelString(self: *StructuredLogger, level: LogLevel) []const u8 {
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

/// Logger factory
pub const LoggerFactory = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LoggerFactory {
        return LoggerFactory{
            .allocator = allocator,
        };
    }

    pub fn createConsoleLogger(self: *LoggerFactory, level: LogLevel, component: []const u8) LogContext {
        return LogContext.init(self.allocator, std.fs.File.stdout().writer(&[_]u8{ } ** 0), level, component);
    }

    pub fn createStructuredLogger(self: *LoggerFactory, level: LogLevel, component: []const u8) StructuredLogger {
        return StructuredLogger.init(self.allocator, std.fs.File.stdout().writer(&[_]u8{ } ** 0), level, component);
    }

    pub fn createFileLogger(self: *LoggerFactory, level: LogLevel, component: []const u8, file_path: []const u8) !LogContext {
        const file = try std.fs.cwd().createFile(file_path, .{});
        return LogContext.init(self.allocator, file.writer(), level, component);
    }
};
