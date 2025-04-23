const std = @import("std");
const types = @import("types");

pub const LoggerError = error{
    WriterError,
    AllocationError,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    level: types.LogLevel,

    pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: types.LogLevel) LoggerError!Logger {
        return Logger{
            .allocator = allocator,
            .writer = writer,
            .level = level,
        };
    }

    pub fn deinit(self: *Logger) void {
        _ = self;
        // Nothing to deinit for now
    }

    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.debug)) {
            try self.log("DEBUG", format, args);
        }
    }

    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.info)) {
            try self.log("INFO", format, args);
        }
    }

    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.warn)) {
            try self.log("WARN", format, args);
        }
    }

    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.err)) {
            try self.log("ERROR", format, args);
        }
    }

    fn log(self: *Logger, level: []const u8, comptime format: []const u8, args: anytype) !void {
        const timestamp = std.time.timestamp();
        try self.writer.print("[{s}] {d}: " ++ format ++ "\n", .{ level, timestamp } ++ args);
    }
};

pub const logger = Logger;