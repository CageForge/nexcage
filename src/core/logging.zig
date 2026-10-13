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

/// True in the copy of nexcage that libcrun's CVE-2019-5736 protection
/// re-executes, for create and exec on the crun backend, until the copy
/// reaches the point where the first run re-executed
/// (CrunDriver.runFromSealedCopy). The copy starts again from main, so every
/// line the first run logged before that point came twice, in the engine's
/// --log file too; below warn the copy leaves them out. A warning or an error
/// there is kept, in case the copy meets one the first run did not.
pub var rerun_from_copy: bool = false;

/// Log context
/// How a log line is written. A container engine passes --log-format json and
/// then reads the file back to find out why the runtime failed, so the shape
/// matters: one object per line, with the fields runc writes.
pub const LogFormat = enum { text, json };

/// Opens a log file that other nexcage processes share: --log, which an
/// engine passes to every call on one container, and --log-file or the
/// configuration's log_file, which every call on the host can share.
///
/// O_APPEND: each write lands at the end of the file as it is then. Opening
/// and seeking to the end once fixed the offset, and of two calls writing
/// to the same file the one that opened first overwrote the other's lines --
/// the error line containerd reads back among them. O_NOFOLLOW: the last
/// component is not followed if it is a symlink; an engine names a file in a
/// directory of its own, which the runtime creates. O_CLOEXEC: no command
/// nexcage runs inherits it.
///
/// O_NONBLOCK, for the open only: a FIFO in the file's place that nothing
/// reads fails at once (NoDevice, ENXIO) instead of holding the call, as
/// root, until something opens it for reading. list's help suggested a name
/// in /tmp, where with fs.protected_fifos=0 anyone can leave one. Writes
/// block again afterwards, so a slow reader loses no lines. openat, not
/// open: only openat's wrapper names ENXIO rather than calling it Unexpected.
pub fn openAppend(path: []const u8) !std.fs.File {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true, .CLOEXEC = true, .NOFOLLOW = true, .NONBLOCK = true }, 0o640);
    errdefer std.posix.close(fd);
    const nonblock: usize = @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }));
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags & ~nonblock);
    return .{ .handle = fd };
}

test "two writers to one log file keep each other's lines" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    const log_path = try std.fs.path.join(std.testing.allocator, &.{ path, "log" });
    defer std.testing.allocator.free(log_path);

    // Both open before either writes, as two engine calls on one container do.
    const a = try openAppend(log_path);
    defer a.close();
    const b = try openAppend(log_path);
    defer b.close();
    try a.writeAll("A1\n");
    try b.writeAll("B1\n");
    try a.writeAll("A2\n");

    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("A1\nB1\nA2\n", try tmp.dir.readFile("log", &buf));
}

test "a log path whose last component is a symlink is not followed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink("target", "log", .{});
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    const log_path = try std.fs.path.join(std.testing.allocator, &.{ path, "log" });
    defer std.testing.allocator.free(log_path);

    try std.testing.expectError(error.SymLinkLoop, openAppend(log_path));
    try std.testing.expectError(error.FileNotFound, tmp.dir.access("target", .{}));
}

test "a FIFO in a log file's place is not waited on, and one that is read is written as a file is" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectEqual(@as(usize, 0), std.os.linux.mknodat(tmp.dir.fd, "log", std.os.linux.S.IFIFO | 0o600, 0));
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(path);
    const log_path = try std.fs.path.join(std.testing.allocator, &.{ path, "log" });
    defer std.testing.allocator.free(log_path);

    // Nothing reads it: refused at once.
    try std.testing.expectError(error.NoDevice, openAppend(log_path));

    // Something reads it: opened, and its writes block again, as a file's do.
    // The reader opens O_NONBLOCK itself, or it would wait for this writer.
    const reader = try std.posix.openat(tmp.dir.fd, "log", .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
    defer std.posix.close(reader);
    const f = try openAppend(log_path);
    defer f.close();
    const nonblock: usize = @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true }));
    try std.testing.expectEqual(@as(usize, 0), try std.posix.fcntl(f.handle, std.posix.F.GETFL, 0) & nonblock);
}

/// The most of a message a JSON log line carries, in bytes.
const json_message_max = 2048;

/// The message `format` makes, or as much of it as fits `buf` with "..."
/// in place of the rest, cut on a UTF-8 character boundary so that the JSON
/// line stays valid. bufPrint into a fixed buffer used to give up and leave
/// the message empty, and an error longer than the buffer -- pct create's
/// stderr, a libcrun message naming a long bundle path -- reached containerd
/// as "msg":"".
fn cut(buf: []u8, comptime format: []const u8, args: anytype) []const u8 {
    const mark = "...";
    var w = std.Io.Writer.fixed(buf);
    w.print(format, args) catch {
        var end = @min(w.end, buf.len - mark.len);
        while (end > 0 and buf[end] & 0xC0 == 0x80) end -= 1;
        @memcpy(buf[end..][0..mark.len], mark);
        return buf[0 .. end + mark.len];
    };
    return w.buffered();
}

/// Writes `msg` with each control character but tab as an escape -- \n, \r
/// or \xNN -- and each backslash doubled, so that text which looks like an
/// escape cannot pass for one. A message carries text nexcage did not write
/// -- pct's stderr, a libcrun error naming the bundle's process.args[0] --
/// and a newline in it made a second log line indistinguishable from a real
/// one, while an escape sequence reached the terminal of whoever read the log
/// or nexcage's stderr.
///
/// That includes the C1 controls, U+0080 to U+009F: xterm and VTE terminals
/// act on them written as UTF-8, on CSI (U+009B) as on ESC [, and NEL
/// (U+0085) starts a line on screen. Escaping only bytes below 0x20 let them
/// through. They are escaped a byte at a time, as are U+2028 and U+2029,
/// which some readers take for line breaks, and any byte that is not part of
/// valid UTF-8, since a terminal not in UTF-8 mode takes a lone 0x9b for CSI.
fn writeEscaped(out: *std.Io.Writer, msg: []const u8) !void {
    var start: usize = 0;
    var i: usize = 0;
    while (i < msg.len) {
        const len, const escape = nextCharacter(msg[i..]);
        if (escape) {
            try out.writeAll(msg[start..i]);
            for (msg[i..][0..len]) |c| switch (c) {
                '\n' => try out.writeAll("\\n"),
                '\r' => try out.writeAll("\\r"),
                '\\' => try out.writeAll("\\\\"),
                else => try out.print("\\x{x:0>2}", .{c}),
            };
            start = i + len;
        }
        i += len;
    }
    try out.writeAll(msg[start..]);
}

/// The length of the character `rest` starts with, and whether writeEscaped
/// escapes it. A byte that does not start valid UTF-8 is taken on its own.
fn nextCharacter(rest: []const u8) struct { usize, bool } {
    const c = rest[0];
    if (c < 0x80) return .{ 1, (c < 0x20 and c != '\t') or c == 0x7f or c == '\\' };
    const len = std.unicode.utf8ByteSequenceLength(c) catch return .{ 1, true };
    if (len > rest.len) return .{ 1, true };
    const cp = std.unicode.utf8Decode(rest[0..len]) catch return .{ 1, true };
    return .{ len, cp <= 0x9f or cp == 0x2028 or cp == 0x2029 };
}

pub const LogContext = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,
    level: LogLevel,
    component: []const u8,
    timestamp: bool = true,
    colorize: bool = false,
    /// --log-format. text for a person, json for a container engine.
    format: LogFormat = .text,
    /// Errors are written here as well, as one plain line. main points it at
    /// stderr when --log sends the log to a file, which is what runc and crun
    /// do: an engine reads the command's own output to tell one failure from
    /// another. containerd's shim takes "no such process" from `kill` as a
    /// process that has already exited; with the reason only in the file, it
    /// saw "operation failed" and could not stop the pod.
    echo: ?std.fs.File = null,

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

    /// Writes a warning to `echo` the way an error is echoed there: one
    /// plain line, escaped. Only errors are echoed by themselves; a caller
    /// whose warning is about protection the command did not give uses this
    /// beside warn(), so whoever ran the command sees it when --log sends
    /// the log to a file. Nothing is written without an echo, or when
    /// --log-level asked for errors only.
    pub fn echoWarning(self: *LogContext, comptime format: []const u8, args: anytype) void {
        const echo = self.echo orelse return;
        if (@intFromEnum(LogLevel.warn) < @intFromEnum(self.level)) return;
        const whole: ?[]u8 = std.fmt.allocPrint(self.allocator, format, args) catch null;
        defer if (whole) |m| self.allocator.free(m);
        var fallback: [json_message_max]u8 = undefined;
        const text = whole orelse cut(&fallback, format, args);

        var echo_buffer: [1024]u8 = undefined;
        var echo_writer = echo.writerStreaming(&echo_buffer);
        const out = &echo_writer.interface;
        out.print("{s}: warning: ", .{self.component}) catch {};
        writeEscaped(out, text) catch {};
        out.writeAll("\n") catch {};
        out.flush() catch {};
    }

    fn log(self: *LogContext, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;
        if (rerun_from_copy and @intFromEnum(level) < @intFromEnum(LogLevel.warn)) return;
        const echoed = self.echo != null and @intFromEnum(level) >= @intFromEnum(LogLevel.@"error");

        // A text line and the echo carry the whole message, escaped; should
        // memory run out, as much of it as a JSON line would.
        var whole: ?[]u8 = null;
        defer if (whole) |m| self.allocator.free(m);
        var fallback: [json_message_max]u8 = undefined;
        const text: []const u8 = if (self.format == .text or echoed) blk: {
            whole = std.fmt.allocPrint(self.allocator, format, args) catch null;
            break :blk whole orelse cut(&fallback, format, args);
        } else "";

        if (echoed) {
            var echo_buffer: [1024]u8 = undefined;
            var echo_writer = self.echo.?.writerStreaming(&echo_buffer);
            const out = &echo_writer.interface;
            out.print("{s}: ", .{self.component}) catch {};
            writeEscaped(out, text) catch {};
            out.writeAll("\n") catch {};
            out.flush() catch {};
        }

        // A log line that cannot be written must not fail the operation it describes.
        if (self.format == .json) {
            // One object per line, with the fields runc writes and containerd
            // reads back: it opens this file to report why the runtime failed.
            var msg_buf: [json_message_max]u8 = undefined;
            const msg = cut(&msg_buf, format, args);
            // Built whole and written with one write(): with O_APPEND, two
            // calls sharing the file cannot interleave inside a line. Room
            // for every byte of the message escaped as \u00XX.
            var line_buf: [json_message_max * 6 + 96]u8 = undefined;
            var line = std.Io.Writer.fixed(&line_buf);
            line.writeAll("{\"level\":\"") catch return;
            line.writeAll(self.getJsonLevel(level)) catch return;
            line.writeAll("\",\"msg\":") catch return;
            json.writeString(&line, msg) catch return;
            var ts_buf: [20]u8 = undefined;
            line.writeAll(",\"time\":\"") catch return;
            line.writeAll(rfc3339.format(&ts_buf, std.time.timestamp())) catch return;
            line.writeAll("\"}\n") catch return;
            self.file.writeAll(line.buffered()) catch return;
            return;
        }

        // Streaming rather than positional: a positional writer starts at
        // offset 0, so each message would overwrite the last one in a log file.
        var buffer: [4096]u8 = undefined;
        var file_writer = self.file.writerStreaming(&buffer);
        const out = &file_writer.interface;

        const color = if (self.colorize) self.getLevelColor(level) else "";
        const reset = if (self.colorize) "\x1b[0m" else "";

        if (self.timestamp) out.print("[{d}] ", .{std.time.timestamp()}) catch return;
        out.print("{s}{s}{s} {s}: ", .{ color, self.getLevelString(level), reset, self.component }) catch return;
        writeEscaped(out, text) catch return;
        out.writeAll("\n") catch return;
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

test "an error is echoed as a plain line, and nothing below it is" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const log_file = try tmp.dir.createFile("log.json", .{});
    defer log_file.close();
    const echo_file = try tmp.dir.createFile("stderr", .{});
    defer echo_file.close();

    var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
    logger.format = .json;
    logger.echo = echo_file;
    try logger.info("Killing container {s}", .{"web-1"});
    try logger.warn("a warning", .{});
    try logger.err("libcrun container_kill: {s}", .{"process not running: No such process"});

    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "nexcage: libcrun container_kill: process not running: No such process\n",
        try tmp.dir.readFile("stderr", &buf),
    );
    // The file keeps every line, the error among them.
    const logged = try tmp.dir.readFile("log.json", &buf);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, logged, "\n"));
    try std.testing.expect(std.mem.indexOf(u8, logged, "\"level\":\"error\"") != null);
}

test "a json message longer than the line allows keeps its start, and says it was cut" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const log_file = try tmp.dir.createFile("log.json", .{});
    defer log_file.close();

    var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
    logger.format = .json;
    // 20 + 2024 bytes, then two-byte characters: the cut, at 2045 bytes with
    // room for "...", falls inside the first, which goes whole.
    try logger.err("pct command failed: {s}", .{"x" ** 2024 ++ "\u{e9}" ** 600});

    var buf: [16 * 1024]u8 = undefined;
    const logged = try tmp.dir.readFile("log.json", &buf);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "\n"));
    const Line = struct { level: []const u8, msg: []const u8, time: []const u8 };
    const parsed = try std.json.parseFromSlice(Line, std.testing.allocator, logged, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("error", parsed.value.level);
    try std.testing.expect(std.mem.startsWith(u8, parsed.value.msg, "pct command failed: xxxx"));
    try std.testing.expect(std.mem.endsWith(u8, parsed.value.msg, "x..."));
    try std.testing.expect(parsed.value.msg.len <= json_message_max);
    try std.testing.expect(std.unicode.utf8ValidateSlice(parsed.value.msg));
}

test "a logged value cannot add a line or a terminal escape" {
    // C0 controls; C1 ones as UTF-8, which xterm and VTE terminals act on
    // (U+009B is CSI, U+0085 NEL a new line); U+2028, where some readers
    // split lines; a lone byte that is not UTF-8, which a terminal not in
    // UTF-8 mode takes for CSI; and a backslash before an n, which must not
    // read as an escaped newline. The text between them, Cyrillic as much as
    // ASCII, is kept as it is. A JSON log writes the controls as \u escapes,
    // and the lone byte, which no JSON string can stand for, as it was.
    const forged = "/x\n[1790000000] ERROR nexcage: forged\r\x1b]0;t\x07\u{9b}2J\u{85}[1790000000] ERROR nexcage: nel\u{2028}ls \x9b \\n \u{440}";
    for ([_]LogFormat{ .text, .json }) |format| {
        var tmp = std.testing.tmpDir(.{});
        defer tmp.cleanup();
        const log_file = try tmp.dir.createFile("log", .{});
        defer log_file.close();
        const echo_file = try tmp.dir.createFile("stderr", .{});
        defer echo_file.close();

        var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
        logger.timestamp = false;
        logger.format = format;
        logger.echo = echo_file;
        try logger.err("libcrun container_create: executable file `{s}` not found", .{forged});

        var buf: [1024]u8 = undefined;
        for ([_][]const u8{ "log", "stderr" }) |name| {
            const got = try tmp.dir.readFile(name, &buf);
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, got, "\n"));
            for ([_][]const u8{ "\r", "\x1b", "\x07", "\u{9b}", "\u{85}", "\u{2028}" }) |c| {
                if (std.mem.indexOf(u8, got, c)) |at| {
                    std.debug.print("{s} ({s}) has {x} at {d}\n", .{ name, @tagName(format), c, at });
                    return error.TestUnexpectedControl;
                }
            }
        }
        try std.testing.expectEqualStrings(
            "nexcage: libcrun container_create: executable file `/x\\n[1790000000] ERROR nexcage: forged\\r\\x1b]0;t\\x07\\xc2\\x9b2J\\xc2\\x85[1790000000] ERROR nexcage: nel\\xe2\\x80\\xa8ls \\x9b \\\\n \u{440}` not found\n",
            try tmp.dir.readFile("stderr", &buf),
        );
    }
}

test "a warning echoed on purpose is one escaped line, as an echoed error is" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const log_file = try tmp.dir.createFile("log", .{});
    defer log_file.close();
    const echo_file = try tmp.dir.createFile("stderr", .{});
    defer echo_file.close();

    var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
    logger.echo = echo_file;
    logger.echoWarning("linux.seccomp in {s}/config.json: not applied", .{"/b/x\nnexcage: forged\x1b[2J\u{85}"});
    // --log-level error: not written
    logger.level = .@"error";
    logger.echoWarning("quiet", .{});

    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings(
        "nexcage: warning: linux.seccomp in /b/x\\nnexcage: forged\\x1b[2J\\xc2\\x85/config.json: not applied\n",
        try tmp.dir.readFile("stderr", &buf),
    );
}

test "the re-executed copy leaves out the lines below warn until it is told it has caught up" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const log_file = try tmp.dir.createFile("log", .{});
    defer log_file.close();
    var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
    logger.format = .json;

    rerun_from_copy = true;
    defer rerun_from_copy = false;
    try logger.info("Executing create command", .{});
    try logger.warn("kept", .{});
    rerun_from_copy = false;
    try logger.info("Creating OCI container with libcrun", .{});

    var buf: [1024]u8 = undefined;
    const got = try tmp.dir.readFile("log", &buf);
    try std.testing.expect(std.mem.indexOf(u8, got, "Executing create command") == null);
    try std.testing.expect(std.mem.indexOf(u8, got, "\"msg\":\"kept\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got, "Creating OCI container with libcrun") != null);
}

test "without echo an error goes to the log alone" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const log_file = try tmp.dir.createFile("log", .{});
    defer log_file.close();

    var logger = LogContext.init(std.testing.allocator, log_file, .info, "nexcage");
    try logger.err("boom", .{});

    var buf: [256]u8 = undefined;
    const logged = try tmp.dir.readFile("log", &buf);
    try std.testing.expect(std.mem.endsWith(u8, logged, "ERROR nexcage: boom\n"));
}

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
