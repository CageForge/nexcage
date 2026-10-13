const std = @import("std");
const builtin = @import("builtin");
const logging = @import("logging.zig");

/// Simple advanced logging system with DEBUG mode and file output
pub const SimpleAdvancedLogging = struct {
    allocator: std.mem.Allocator,
    console_logger: LogContext,
    file_logger: ?LogContext = null,
    debug_mode: bool = false,
    log_file_path: ?[]const u8 = null,
    /// When the command started, in nanoseconds on the monotonic clock.
    command_start_time: ?u64 = null,

    const Self = @This();

    /// Initialize simple advanced logging system
    pub fn init(allocator: std.mem.Allocator, debug_mode: bool, log_file_path: ?[]const u8) !Self {
        const console_logger = LogContext.init(allocator, std.fs.File.stderr(), .debug, "nexcage");

        var file_logger: ?LogContext = null;
        if (log_file_path) |path| {
            // Every run shares the log file, so append to it; createFile's
            // default truncated it on each invocation, and seeking to the end
            // once let two runs overwrite each other (see openAppend). Create
            // the last directory if it is missing (e.g. /var/log/nexcage when
            // running as root). One makeDir, not makePath: makePath retries
            // while mkdir reports a missing parent, and on procfs it never
            // stops.
            if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makeDir(dir) catch {};
            const file = try logging.openAppend(path);
            file_logger = LogContext.init(allocator, file, .debug, "nexcage");
        }

        return Self{
            .allocator = allocator,
            .console_logger = console_logger,
            .file_logger = file_logger,
            .debug_mode = debug_mode,
            .log_file_path = log_file_path,
        };
    }

    /// Deinitialize logging system
    pub fn deinit(self: *Self) void {
        // Close file logger if exists
        if (self.file_logger) |*logger| {
            logger.deinit();
            logger.file.close();
        }

        // Note: log_file_path is owned by LoggingConfig, not by us
    }

    /// Log with both console and file output
    fn log(self: *Self, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        // Log to console using public methods
        switch (level) {
            .trace => try self.console_logger.trace(format, args),
            .debug => try self.console_logger.debug(format, args),
            .info => try self.console_logger.info(format, args),
            .warn => try self.console_logger.warn(format, args),
            .@"error" => try self.console_logger.err(format, args),
            .fatal => try self.console_logger.fatal(format, args),
        }

        // Log to file if enabled
        if (self.file_logger) |*logger| {
            switch (level) {
                .trace => try logger.trace(format, args),
                .debug => try logger.debug(format, args),
                .info => try logger.info(format, args),
                .warn => try logger.warn(format, args),
                .@"error" => try logger.err(format, args),
                .fatal => try logger.fatal(format, args),
            }
        }
    }

    /// Trace level logging
    pub fn trace(self: *Self, comptime format: []const u8, args: anytype) !void {
        if (self.debug_mode) {
            try self.log(.trace, format, args);
        }
    }

    /// Debug level logging
    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) !void {
        if (self.debug_mode) {
            try self.log(.debug, format, args);
        }
    }

    /// Info level logging
    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.info, format, args);
    }

    /// Warning level logging
    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.warn, format, args);
    }

    /// Error level logging
    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.@"error", format, args);
    }

    /// Fatal level logging
    pub fn fatal(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.fatal, format, args);
    }

    /// Log command execution start. `args` are nexcage's own words after the
    /// command name. `unlogged` is how many words come after them: the
    /// command `exec` runs, which is the container's, and which a caller is
    /// told to give its variables, tokens included, since the caller's
    /// environment does not reach it. Those words went into this line, and
    /// so to the --log-file as root; only their number does now.
    pub fn logCommandStart(self: *Self, command_name: []const u8, args: []const []const u8, unlogged: usize) !void {
        self.command_start_time = monotonicNs();

        const joined_args = try std.mem.join(self.allocator, " ", args);
        defer self.allocator.free(joined_args);
        const with: []const u8 = if (args.len > 0) " with args: " else "";
        if (unlogged > 0) {
            try self.info("Starting command: {s}{s}{s}, and a command of {d} word(s) for the container, not logged", .{ command_name, with, joined_args, unlogged });
        } else {
            try self.info("Starting command: {s}{s}{s}", .{ command_name, with, joined_args });
        }

        if (self.debug_mode) {
            try self.debug("Command execution environment:", .{});
            try self.debug("  Debug mode: enabled", .{});
            try self.debug("  Log file: {s}", .{self.log_file_path orelse "none"});
            try self.debug("  Timestamp: {d}", .{std.time.timestamp()});
        }
    }

    /// Log command execution completion
    pub fn logCommandComplete(self: *Self, command_name: []const u8, success: bool) !void {
        if (self.command_start_time) |start_time| {
            const duration_ms = (monotonicNs() -| start_time) / std.time.ns_per_ms;
            try self.info("Command '{s}' completed in {d}ms", .{ command_name, duration_ms });
        }

        if (success) {
            try self.info("Command '{s}' completed successfully", .{command_name});
        } else {
            try self.err("Command '{s}' failed", .{command_name});
        }
    }

    /// Log operation start
    pub fn logOperationStart(self: *Self, operation: []const u8, target: []const u8) !void {
        try self.info("Starting operation: {s} on {s}", .{ operation, target });

        if (self.debug_mode) {
            try self.debug("Operation details:", .{});
            try self.debug("  Operation: {s}", .{operation});
            try self.debug("  Target: {s}", .{target});
            try self.debug("  Start time: {d}", .{std.time.timestamp()});
        }
    }

    /// Log operation completion
    pub fn logOperationComplete(self: *Self, operation: []const u8, target: []const u8, success: bool) !void {
        if (success) {
            try self.info("Operation '{s}' on '{s}' completed successfully", .{ operation, target });
        } else {
            try self.err("Operation '{s}' on '{s}' failed", .{ operation, target });
        }
    }

    /// Log system information
    pub fn logSystemInfo(self: *Self) !void {
        if (self.debug_mode) {
            try self.debug("System Information:", .{});
            try self.debug("  OS: {s}", .{@tagName(builtin.os.tag)});
            try self.debug("  Architecture: {s}", .{@tagName(builtin.cpu.arch)});
            try self.debug("  Target: {s}", .{"native"});
            try self.debug("  Zig version: {s}", .{builtin.zig_version_string});
        }
    }

    /// Log memory usage
    pub fn logMemoryUsage(self: *Self, allocator_name: []const u8) !void {
        if (self.debug_mode) {
            // Note: This is a simplified memory logging
            // In a real implementation, you'd want to track actual memory usage
            try self.debug("Memory usage for {s}: [tracking not implemented]", .{allocator_name});
        }
    }
};

/// Now, in nanoseconds on the monotonic clock. The duration of a command was
/// taken from the wall clock, and in u64: NTP or `date -s` stepping it back
/// while a command ran made the subtraction overflow, a panic after the
/// command had already succeeded -- an engine saw a create that worked
/// fail. The monotonic clock does not step, and the subtraction that uses it
/// saturates anyway. 0 if the clock cannot be read, which gives no duration
/// rather than a wrong one.
fn monotonicNs() u64 {
    const ts = std.posix.clock_gettime(.MONOTONIC) catch return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

test "a command's duration cannot overflow, whatever the clock did meanwhile" {
    var logger = try SimpleAdvancedLogging.init(std.testing.allocator, false, null);
    defer logger.deinit();
    const null_file = try std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only });
    defer null_file.close();
    logger.console_logger.file = null_file;
    // A start later than now on any clock: what a wall clock stepped back
    // during the command looked like.
    logger.command_start_time = std.math.maxInt(u64);
    try logger.logCommandComplete("create", true);
}

test "a --log-file is appended to by every call, and a symlink in its place is not followed" {
    // The open behind --log-file, NEXCAGE_LOG_FILE and the configuration's
    // log_file, which is not main's --log open and needs its own proof.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir);

    try tmp.dir.symLink("target.log", "link.log", .{});
    const link = try std.fs.path.join(std.testing.allocator, &.{ dir, "link.log" });
    defer std.testing.allocator.free(link);
    try std.testing.expectError(error.SymLinkLoop, SimpleAdvancedLogging.init(std.testing.allocator, false, link));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("target.log", .{}));

    // Two calls sharing the file, both open before either writes.
    const shared = try std.fs.path.join(std.testing.allocator, &.{ dir, "shared.log" });
    defer std.testing.allocator.free(shared);
    var a = try SimpleAdvancedLogging.init(std.testing.allocator, false, shared);
    defer a.deinit();
    var b = try SimpleAdvancedLogging.init(std.testing.allocator, false, shared);
    defer b.deinit();
    try a.file_logger.?.file.writeAll("A1\n");
    try b.file_logger.?.file.writeAll("B1\n");
    try a.file_logger.?.file.writeAll("A2\n");
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("A1\nB1\nA2\n", try tmp.dir.readFile("shared.log", &buf));
}

/// Re-export LogLevel and LogContext for compatibility
pub const LogLevel = @import("logging.zig").LogLevel;
pub const LogContext = @import("logging.zig").LogContext;
