const std = @import("std");
const types = @import("types");
const errors = @import("error");

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

pub const LogContext = struct {
    allocator: std.mem.Allocator,
    writer: std.fs.File.Writer,
    level: types.LogLevel,
    initialized: bool,
    name: []const u8,
    file: ?std.fs.File,

    pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: types.LogLevel, name: []const u8) LoggerError!LogContext {
        return LogContext{
            .allocator = allocator,
            .writer = writer,
            .level = level,
            .initialized = true,
            .name = try allocator.dupe(u8, name),
            .file = null,
        };
    }

    pub fn initWithFile(allocator: std.mem.Allocator, file: std.fs.File, level: types.LogLevel, name: []const u8) LoggerError!LogContext {
        return LogContext{
            .allocator = allocator,
            .writer = file.writer(),
            .level = level,
            .initialized = true,
            .name = try allocator.dupe(u8, name),
            .file = file,
        };
    }

    pub fn deinit(self: *LogContext) void {
        self.allocator.free(self.name);
        if (self.file) |file| {
            file.close();
        }
        self.initialized = false;
    }

    pub fn debug(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (!self.initialized) return LoggerError.NotInitialized;
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.debug)) {
            self.writer.print("[DEBUG] [{s}] " ++ fmt ++ "\n", .{self.name} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn info(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (!self.initialized) return LoggerError.NotInitialized;
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.info)) {
            self.writer.print("[INFO] [{s}] " ++ fmt ++ "\n", .{self.name} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn warn(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (!self.initialized) return LoggerError.NotInitialized;
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.warn)) {
            self.writer.print("[WARN] [{s}] " ++ fmt ++ "\n", .{self.name} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }

    pub fn err(self: *LogContext, comptime fmt: []const u8, args: anytype) LoggerError!void {
        if (!self.initialized) return LoggerError.NotInitialized;
        if (@intFromEnum(self.level) <= @intFromEnum(types.LogLevel.err)) {
            self.writer.print("[ERROR] [{s}] " ++ fmt ++ "\n", .{self.name} ++ args) catch |write_err| {
                return switch (write_err) {
                    error.DiskQuota => LoggerError.DiskQuota,
                    error.FileTooBig => LoggerError.FileTooBig,
                    error.InputOutput => LoggerError.InputOutput,
                    error.NoSpaceLeft => LoggerError.NoSpaceLeft,
                    error.DeviceBusy => LoggerError.DeviceBusy,
                    error.InvalidArgument => LoggerError.InvalidArgument,
                    error.AccessDenied => LoggerError.AccessDenied,
                    error.BrokenPipe => LoggerError.BrokenPipe,
                    error.SystemResources => LoggerError.SystemResources,
                    error.OperationAborted => LoggerError.OperationAborted,
                    error.NotOpenForWriting => LoggerError.NotOpenForWriting,
                    error.LockViolation => LoggerError.LockViolation,
                    error.WouldBlock => LoggerError.WouldBlock,
                    error.ConnectionResetByPeer => LoggerError.ConnectionResetByPeer,
                    error.Unexpected => LoggerError.Unexpected,
                };
            };
        }
    }
};

// Для зворотної сумісності
pub const Logger = LogContext;

var global_logger: ?LogContext = null;

pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: types.LogLevel) LoggerError!void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try LogContext.init(allocator, writer, level, "global");
}

pub fn initWithFile(allocator: std.mem.Allocator, file: std.fs.File, level: types.LogLevel) LoggerError!void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try LogContext.initWithFile(allocator, file, level, "global");
}

pub fn deinit() void {
    if (global_logger) |*logger| {
        logger.deinit();
        global_logger = null;
    }
}

pub fn debug(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.debug(fmt, args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.info(fmt, args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.warn(fmt, args);
    }
}

pub fn err(comptime fmt: []const u8, args: anytype) LoggerError!void {
    if (global_logger) |*logger| {
        try logger.err(fmt, args);
    }
}
