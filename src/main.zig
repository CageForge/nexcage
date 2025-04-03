const std = @import("std");
const cri = @import("cri");
const proxmox = @import("proxmox");
const config = @import("config");
const logger = @import("logger");
const fs = std.fs;
const os = std.os;
const mem = std.mem;
const fmt = std.fmt;

pub fn main() !void {
    // Initialize allocator
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
    const log_file = try fs.cwd().createFile("proxmox-lxcri.log", .{});
    defer log_file.close();
    var log = try logger.Logger.init(allocator, cfg.runtime.log_level, log_file.writer());

    try log.info("Starting Proxmox LXCRI...", .{});

    // Initialize Proxmox client
    var proxmox_client = try proxmox.Client.init(.{
        .allocator = allocator,
        .host = cfg.proxmox.host,
        .port = cfg.proxmox.port,
        .token = cfg.proxmox.token,
    });
    defer proxmox_client.deinit();

    try log.info("Connected to Proxmox VE at {s}:{d}", .{ cfg.proxmox.host, cfg.proxmox.port });

    // Initialize CRI service
    var cri_service = try cri.Service.init(.{
        .allocator = allocator,
        .proxmox_client = &proxmox_client,
    });
    defer cri_service.deinit();

    try log.info("CRI service initialized", .{});

    // Start the service
    try cri_service.start();
    try log.info("CRI service started on {s}", .{cfg.runtime.socket_path});

    // Wait for shutdown signal
    try waitForShutdown(&log);
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    // Check environment variable first
    if (os.getenv("PROXMOX_LXCRI_CONFIG")) |path| {
        return try allocator.dupe(u8, path);
    }

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

fn waitForShutdown(log: *logger.Logger) !void {
    var signal_set = os.SigSet.initEmpty();
    try signal_set.add(.SIGINT);
    try signal_set.add(.SIGTERM);

    var sig: i32 = undefined;
    while (true) {
        try os.sigwait(&signal_set, &sig);
        try log.info("Received signal {d}, shutting down...", .{sig});
        break;
    }
} 