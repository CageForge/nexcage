const std = @import("std");
const os = std.os;
const linux = os.linux;
const logger = @import("logger");
const config = @import("config");
const fs = std.fs;

var shutdown_requested: bool = false;
var last_signal: i32 = 0;
var log: logger.Logger = undefined;

fn signalHandler(sig: i32) callconv(.C) void {
    shutdown_requested = true;
    last_signal = sig;
}

fn waitForShutdown() !void {
    const act = linux.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = linux.empty_sigset,
        .flags = 0,
        .restorer = null,
    };

    // SIGINT = 2, SIGTERM = 15
    const rc1 = linux.syscall3(.rt_sigaction, 2, @intFromPtr(&act), 0);
    const err1: linux.E = @enumFromInt(-@as(i32, @intCast(rc1)));
    if (err1 != .SUCCESS) {
        return error.SignalHandlerError;
    }

    const rc2 = linux.syscall3(.rt_sigaction, 15, @intFromPtr(&act), 0);
    const err2: linux.E = @enumFromInt(-@as(i32, @intCast(rc2)));
    if (err2 != .SUCCESS) {
        return error.SignalHandlerError;
    }

    while (!shutdown_requested) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    try log.info("Received signal {}, shutting down...", .{last_signal});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize configuration
    var cfg = try config.Config.init(allocator);
    defer cfg.deinit();

    // Initialize logger
    log = try logger.Logger.init(allocator, cfg.runtime.log_level, std.io.getStdOut().writer());

    try log.info("Starting Proxmox LXCRI...", .{});

    try waitForShutdown();
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    // Check environment variable first
    if (std.process.getEnvVarOwned(allocator, "PROXMOX_LXCRI_CONFIG")) |path| {
        return path;
    } else |_| {}

    // Check default locations
    const default_paths = [_][]const u8{
        "/etc/proxmox-lxcri/config.json",
        "./config.json",
    };

    for (default_paths) |path| {
        if (fs.cwd().access(path, .{})) |_| {
            return try allocator.dupe(u8, path);
        } else |_| {}
    }

    return error.ConfigNotFound;
}
