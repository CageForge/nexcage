const std = @import("std");
const json = @import("json.zig");
const rfc3339 = @import("rfc3339.zig");

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
/// How a log line is written. A container engine passes --log-format json and
/// then reads the file back to find out why the runtime failed, so the shape
/// matters: one object per line, with the fields runc writes.
pub const LogFormat = enum { text, json };

pub const LogContext = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    level: LogLevel,
    component: []const u8,
    timestamp: bool = true,
    colorize: bool = false,
    /// --log-format. text for a person, json for a container engine.
    format: LogFormat = .text,

    /// Messages are written to `file`. Console loggers should be given stderr:
    /// stdout carries command output (the list table, state JSON) that other
    /// programs parse. The previous signature took a Writer, ignored it and
    /// wrote to stdout, so a "file" logger never reached its file.
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File, level: LogLevel, component: []const u8) LogContext {
        return LogContext{
            .allocator = allocator,
            .file = file,
            .level = level,
            .component = component,
            .colorize = file.isTty(),
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
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        // Streaming rather than positional: a positional writer starts at
        // offset 0, so each message would overwrite the last one in a log file.
        var buffer: [1024]u8 = undefined;
        var file_writer = self.file.writerStreaming(&buffer);
        const out = &file_writer.interface;

        // A log line that cannot be written must not fail the operation it describes.
        if (self.format == .json) {
            // One object per line, with the fields runc writes and containerd
            // reads back: it opens this file to report why the runtime failed.
            var msg_buf: [2048]u8 = undefined;
            const msg = std.fmt.bufPrint(&msg_buf, format, args) catch msg_buf[0..0];
            out.writeAll("{\"level\":\"") catch return;
            out.writeAll(self.getJsonLevel(level)) catch return;
            out.writeAll("\",\"msg\":") catch return;
            json.writeString(out, msg) catch return;
            var ts_buf: [20]u8 = undefined;
            out.writeAll(",\"time\":\"") catch return;
            out.writeAll(rfc3339.format(&ts_buf, std.time.timestamp())) catch return;
            out.writeAll("\"}\n") catch return;
            out.flush() catch return;
            return;
        }

        const color = if (self.colorize) self.getLevelColor(level) else "";
        const reset = if (self.colorize) "\x1b[0m" else "";

        if (self.timestamp) out.print("[{d}] ", .{std.time.timestamp()}) catch return;
        out.print("{s}{s}{s} {s}: " ++ format ++ "\n", .{ color, self.getLevelString(level), reset, self.component } ++ args) catch return;
        out.flush() catch return;
    }

    /// The level names runc uses, which is what an engine expects to parse.
    fn getJsonLevel(self: *LogContext, level: LogLevel) []const u8 {
        _ = self;
        return switch (level) {
            .trace, .debug => "debug",
            .info => "info",
            .warn => "warning",
            .@"error" => "error",
            .fatal => "fatal",
        };
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
        return LogContext.init(self.allocator, std.fs.File.stderr(), level, component);
    }

    pub fn createStructuredLogger(self: *LoggerFactory, level: LogLevel, component: []const u8) StructuredLogger {
        return StructuredLogger.init(self.allocator, std.fs.File.stdout().writer(&[_]u8{} ** 0), level, component);
    }

    pub fn createFileLogger(self: *LoggerFactory, level: LogLevel, component: []const u8, file_path: []const u8) !LogContext {
        const file = try std.fs.cwd().createFile(file_path, .{});
        return LogContext.init(self.allocator, file, level, component);
    }
};
