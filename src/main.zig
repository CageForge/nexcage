const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger_mod = @import("logger");
const config = @import("config");
const types = @import("types");
const fs = std.fs;
const builtin = @import("builtin");
const log = std.log;
const proxmox = @import("proxmox");
const error_mod = @import("error");
const Error = error_mod.Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Client = http.Client;

const SIGINT = 2;
const SIGTERM = 15;

var shutdown_requested: bool = false;
var last_signal: c_int = 0;
var logger_instance: logger_mod.Logger = undefined;
var proxmox_client: proxmox.Client = undefined;

fn printHelp() void {
    const help_text = 
        \\proxmox-lxcri - Proxmox LXC Container Runtime Interface
        \\
        \\Usage:
        \\  proxmox-lxcri [OPTIONS]
        \\
        \\OPTIONS:
        \\  -h, --help          Show this help message
        \\  -d, --debug         Enable debug mode
        \\  --no-daemon         Run without daemonization
        \\
        \\Examples:
        \\  proxmox-lxcri --debug --no-daemon  # Run with debug mode without daemonization
        \\  proxmox-lxcri                       # Run as a daemon
        \\
        \\Configuration:
        \\  The program looks for configuration file in the following order:
        \\  1. Environment variable PROXMOX_LXCRI_CONFIG
        \\  2. /etc/proxmox-lxcri/config.json
        \\  3. ./config.json
        \\
    ;
    std.io.getStdOut().writeAll(help_text) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    var debug_mode = false;
    var no_daemon = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-daemon")) {
            no_daemon = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        }
    }

    // Initialize logger with appropriate level and output
    const log_level = if (debug_mode) types.LogLevel.debug else types.LogLevel.info;
    const log_file = if (!debug_mode) blk: {
        const file = fs.cwd().createFile("/var/log/proxmox-lxcri.log", .{ .truncate = false }) catch |err| {
            std.log.err("Failed to create log file: {s}", .{@errorName(err)});
            return err;
        };
        break :blk file;
    } else null;
    defer if (log_file) |file| file.close();
    
    const log_writer = if (debug_mode) std.io.getStdErr().writer() else log_file.?.writer();
    
    logger_instance = try logger_mod.Logger.init(allocator, log_level, log_writer);
    defer logger_instance.deinit();

    // Load configuration
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    
    const config_content = try fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(config_content);
    
    const config_json = try json.parseFromSlice(json.Value, allocator, config_content, .{});
    defer config_json.deinit();
    
    const config_data = config_json.value.object;
    const proxmox_config = config_data.get("proxmox").?.object;

    var hosts = try allocator.alloc([]const u8, 1);
    hosts[0] = try allocator.dupe(u8, proxmox_config.get("hosts").?.array.items[0].string);

    var config_instance = config.Config{
        .allocator = allocator,
        .hosts = hosts,
        .token = try allocator.dupe(u8, proxmox_config.get("token").?.string),
        .port = @intCast(proxmox_config.get("port").?.integer),
        .node = try allocator.dupe(u8, proxmox_config.get("node").?.string),
        .node_cache_duration = @intCast(proxmox_config.get("node_cache_duration").?.integer),
        .timeout = 30_000,
        .logger = &logger_instance,
    };
    defer config_instance.deinit();

    proxmox_client = try proxmox.Client.init(allocator, config_instance.hosts, config_instance.token, &logger_instance, config_instance.port, config_instance.node, config_instance.node_cache_duration);
    defer proxmox_client.deinit();

    try logger_instance.info("Starting proxmox-lxcri...", .{});

    // List and log all LXC containers
    const containers = try proxmox_client.listLXCs();
    defer allocator.free(containers);

    try logger_instance.info("Found {d} LXC containers:", .{containers.len});
    for (containers) |container| {
        try logger_instance.info("Container {d}: {s} (Status: {s})", .{ container.vmid, container.name, @tagName(container.status) });
    }

    // Setup signal handlers
    const sa = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    posix.sigaction(SIGINT, &sa, null);
    posix.sigaction(SIGTERM, &sa, null);

    if (!no_daemon) {
        while (!shutdown_requested) {
            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    try logger_instance.info("Shutting down proxmox-lxcri...", .{});
}

fn handleSignal(sig: c_int) callconv(.C) void {
    last_signal = sig;
    shutdown_requested = true;
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
        if (fs.cwd().access(path, .{})) {
            return try allocator.dupe(u8, path);
        } else |_| {}
    }

    return Error.ConfigNotFound;
}
