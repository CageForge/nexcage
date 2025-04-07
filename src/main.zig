const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger = @import("logger.zig");
const config = @import("config.zig");
const types = @import("types.zig");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const proxmox = @import("proxmox");
const Error = @import("error.zig").Error;

const SIGINT = 2;
const SIGTERM = 15;

var shutdown_requested: bool = false;
var last_signal: c_int = 0;
var logger_instance: logger.Logger = undefined;
var proxmox_client: proxmox.Client = undefined;

fn signalHandler(sig: c_int) callconv(.C) void {
    shutdown_requested = true;
    last_signal = sig;
}

fn waitForShutdown() !void {
    var act = std.mem.zeroes(c.Sigaction);
    act.handler.handler = signalHandler;
    act.mask = c.empty_sigset;
    act.flags = 0;

    const rc1 = c.sigaction(SIGINT, &act, null);
    if (rc1 < 0) {
        try logger_instance.err("Failed to set SIGINT handler: {}", .{posix.errno(rc1)});
        return Error.ProxmoxOperationFailed;
    }

    const rc2 = c.sigaction(SIGTERM, &act, null);
    if (rc2 < 0) {
        try logger_instance.err("Failed to set SIGTERM handler: {}", .{posix.errno(rc2)});
        return Error.ProxmoxOperationFailed;
    }

    // Wait for signal
    while (!shutdown_requested) {
        std.time.sleep(100 * std.time.ns_per_ms);
    }

    try logger_instance.info("Received signal {}, shutting down...", .{last_signal});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize configuration
    var cfg = try config.Config.init(allocator);
    defer cfg.deinit();

    // Load configuration from file
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    try cfg.loadFromFile(config_path);

    // Initialize logger
    logger_instance = try logger.Logger.init(allocator, cfg.runtime.log_level, std.io.getStdOut().writer());

    try logger_instance.info("Starting Proxmox LXCRI...", .{});

    // Initialize Proxmox client
    proxmox_client = try proxmox.Client.init(.{
        .allocator = allocator,
        .hosts = cfg.proxmox.hosts,
        .port = cfg.proxmox.port,
        .token = cfg.proxmox.token,
        .node = cfg.proxmox.node,
        .node_cache_duration = cfg.proxmox.node_cache_duration,
    });
    defer proxmox_client.deinit();

    try logger_instance.info("Connected to Proxmox API at {s}:{}", .{ cfg.proxmox.hosts[0], cfg.proxmox.port });

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
