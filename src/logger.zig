const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;
const Writer = std.fs.File.Writer;

pub const Logger = struct {
    allocator: Allocator,
    level: types.LogLevel,
    writer: Writer,

    pub fn init(allocator: Allocator, level: types.LogLevel, writer: Writer) !Logger {
        return Logger{
            .allocator = allocator,
            .level = level,
            .writer = writer,
        };
    }

    pub fn deinit(self: *Logger) void {
        _ = self;
        // Nothing to deinit for now
    }

    pub fn debug(self: *Logger, comptime fmt_str: []const u8, args: anytype) !void {
        if (self.level == types.LogLevel.debug) {
            try self.log("DEBUG", fmt_str, args);
        }
    }

    pub fn info(self: *Logger, comptime fmt_str: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.info)) {
            try self.log("INFO", fmt_str, args);
        }
    }

    pub fn warn(self: *Logger, comptime fmt_str: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.warn)) {
            try self.log("WARN", fmt_str, args);
        }
    }

    pub fn err(self: *Logger, comptime fmt_str: []const u8, args: anytype) !void {
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.err)) {
            try self.log("ERROR", fmt_str, args);
        }
    }

    fn log(self: *Logger, level_str: []const u8, comptime fmt_str: []const u8, args: anytype) !void {
        const timestamp = std.time.timestamp();
        const seconds = @mod(timestamp, 86400);
        const hours = @divFloor(seconds, 3600);
        const minutes = @divFloor(@mod(seconds, 3600), 60);
        const secs = @mod(seconds, 60);

        try self.writer.print("[{d:0>2}:{d:0>2}:{d:0>2}] [{s}] ", .{
            hours,
            minutes,
            secs,
            level_str,
        });

        try self.writer.print(fmt_str ++ "\n", args);
    }
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};
