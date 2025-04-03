const std = @import("std");
const time = std.time;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

pub const Logger = struct {
    allocator: Allocator,
    level: LogLevel,
    writer: std.fs.File.Writer,

    pub fn init(allocator: Allocator, level: LogLevel, writer: std.fs.File.Writer) !Logger {
        return Logger{
            .allocator = allocator,
            .level = level,
            .writer = writer,
        };
    }

    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(.debug)) {
            try self.log("DEBUG", format, args);
        }
    }

    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(.info)) {
            try self.log("INFO", format, args);
        }
    }

    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(.warn)) {
            try self.log("WARN", format, args);
        }
    }

    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(.err)) {
            try self.log("ERROR", format, args);
        }
    }

    fn log(self: *Logger, level: []const u8, comptime format: []const u8, args: anytype) !void {
        const timestamp = time.timestamp();
        const timestamp_str = try fmt.allocPrint(self.allocator, "{d}", .{timestamp});
        defer self.allocator.free(timestamp_str);

        try self.writer.print("[{s}] [{s}] {s}\n", .{ timestamp_str, level, try fmt.allocPrint(self.allocator, format, args) });
    }
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
}; 