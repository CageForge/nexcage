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

// For backward compatibility
pub const Logger = types.LogContext;

var global_logger: ?types.LogContext = null;

pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer, level: types.LogLevel) LoggerError!void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try types.LogContext.init(allocator, writer, level, "global");
}

pub fn initWithFile(allocator: std.mem.Allocator, file: std.fs.File, level: types.LogLevel, name: []const u8) !void {
    if (global_logger != null) {
        global_logger.?.deinit();
    }
    global_logger = try types.LogContext.initWithFile(allocator, file, level, name);
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
