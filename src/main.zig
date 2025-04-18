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
const proxmox = @import("proxmox.zig").ProxmoxClient;
const error_module = @import("error");
const Error = error_module.Error;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Client = http.Client;

// Додаємо нові типи помилок
const RuntimeError = error{
    SignalHandlerError,
    NetworkError,
    ResourceInitError,
    ConfigurationError,
    CleanupError,
} || std.fs.File.OpenError || std.fs.File.ReadError;

const SIGINT = posix.SIG.INT;
const SIGTERM = posix.SIG.TERM;
const SIGHUP = posix.SIG.HUP;

var shutdown_requested: bool = false;
var last_signal: c_int = 0;
var logger_instance: logger_mod.Logger = undefined;

// Додаємо нові типи помилок
const ConfigError = error{
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
} || std.fs.File.OpenError || std.fs.File.ReadError;

fn printHelp() !void {
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
    try std.io.getStdOut().writeAll(help_text);
}

fn initLogger(allocator: Allocator, debug_mode: bool) !logger_mod.Logger {
    const log_level = if (debug_mode) types.LogLevel.debug else types.LogLevel.info;
    
    const log_file = if (!debug_mode) blk: {
        const file = fs.cwd().createFile("/var/log/proxmox-lxcri.log", .{ .truncate = false }) catch |err| {
            std.log.err("Failed to create log file: {s}, falling back to stderr", .{@errorName(err)});
            break :blk null;
        };
        break :blk file;
    } else null;
    
    const log_writer = if (debug_mode or log_file == null) 
        std.io.getStdErr().writer() 
    else 
        log_file.?.writer();
        
    return try logger_mod.Logger.init(
        allocator,
        log_writer,
        log_level,
    );
}

fn loadConfig(allocator: Allocator, config_path: []const u8) !config.Config {
    const config_content = fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| {
        try logger_instance.err("Failed to read config file: {s}", .{@errorName(err)});
        return ConfigError.FailedToParseConfig;
    };
    defer allocator.free(config_content);

    var config_json = json.parseFromSlice(json.Value, allocator, config_content, .{}) catch |err| {
        try logger_instance.err("Failed to parse config JSON: {s}", .{@errorName(err)});
        return ConfigError.InvalidConfigFormat;
    };
    defer config_json.deinit();

    const config_data = config_json.value.object;
    const proxmox_config = config_data.get("proxmox") orelse {
        try logger_instance.err("Missing proxmox configuration section", .{});
        return ConfigError.InvalidConfigFormat;
    };
    const proxmox_config_obj = proxmox_config.object;

    var hosts = try allocator.alloc([]const u8, 1);
    errdefer allocator.free(hosts);
    const hosts_array = proxmox_config_obj.get("hosts") orelse {
        try logger_instance.err("Missing hosts configuration", .{});
        return ConfigError.InvalidConfigFormat;
    };
    hosts[0] = try allocator.dupe(u8, hosts_array.array.items[0].string);

    return config.Config{
        .allocator = allocator,
        .hosts = hosts,
        .token = try allocator.dupe(u8, proxmox_config_obj.get("token").?.string),
        .port = @intCast(proxmox_config_obj.get("port").?.integer),
        .node = try allocator.dupe(u8, proxmox_config_obj.get("node").?.string),
        .node_cache_duration = @intCast(proxmox_config_obj.get("node_cache_duration").?.integer),
        .timeout = 30_000,
        .logger = &logger_instance,
    };
}

fn cleanup() !void {
    try logger_instance.info("Starting cleanup process...", .{});
    
    // Зупиняємо всі активні операції
    if (@hasDecl(proxmox_client, "stopAllOperations")) {
        proxmox_client.stopAllOperations() catch |err| {
            try logger_instance.err("Failed to stop all operations: {s}", .{@errorName(err)});
        };
    }
    
    // Закриваємо всі відкриті з'єднання
    if (@hasDecl(proxmox_client, "closeConnections")) {
        proxmox_client.closeConnections() catch |err| {
            try logger_instance.err("Failed to close connections: {s}", .{@errorName(err)});
        };
    }
    
    try logger_instance.info("Cleanup completed", .{});
}

fn signalHandler(sig: c_int) callconv(.C) void {
    shutdown_requested = true;
    last_signal = sig;
}

pub fn main() !void {
    // Ініціалізація аллокатора з перевіркою витоків пам'яті
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .enable_memory_limit = true,
        .safety = true,
        .never_unmap = false,
    }){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            std.log.err("Memory leak detected!", .{});
            os.exit(1);
        }
    }
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var debug_mode = false;
    var no_daemon = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-daemon")) {
            no_daemon = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printHelp();
            return;
        } else {
            try std.io.getStdErr().writer().print("Невідомий аргумент: {s}\nВикористовуйте --help для отримання довідки\n", .{arg});
            return error.InvalidArgument;
        }
    }

    // Initialize logger
    logger_instance = try initLogger(allocator, debug_mode);
    defer logger_instance.deinit();

    try logger_instance.info("Starting proxmox-lxcri...", .{});

    // Load configuration
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    var config_instance = loadConfig(allocator, config_path) catch |err| {
        try logger_instance.err("Failed to load configuration: {s}", .{@errorName(err)});
        return err;
    };
    defer config_instance.deinit();

    proxmox_client = try proxmox.ProxmoxClient.init(
        allocator,
        config_instance.hosts,
        config_instance.token,
        &logger_instance,
        config_instance.port,
        config_instance.node,
    );
    defer proxmox_client.deinit();

    // List and log all LXC containers
    const containers = proxmox_client.listLXCs() catch |err| {
        try logger_instance.err("Failed to list LXC containers: {s}", .{@errorName(err)});
        return err;
    };
    defer allocator.free(containers);

    try logger_instance.info("Found {d} LXC containers:", .{containers.len});
    for (containers) |container| {
        logger_instance.info("Container {d}: {s} (Status: {s})", .{ 
            container.vmid, container.name, @tagName(container.status) 
        }) catch |err| {
            try logger_instance.warn("Failed to log container info: {s}", .{@errorName(err)});
        };
    }

    // Setup signal handlers
    const sa = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    try posix.sigaction(SIGINT, &sa, null);
    try posix.sigaction(SIGTERM, &sa, null);
    try posix.sigaction(SIGHUP, &sa, null);

    if (!no_daemon) {
        while (!shutdown_requested) {
            std.time.sleep(1 * std.time.ns_per_s);
            if (last_signal != 0) {
                try logger_instance.info("Received signal {d}, initiating graceful shutdown...", .{last_signal});
            }
        }
    }

    // Cleanup and shutdown
    try logger_instance.info("Shutting down proxmox-lxcri...", .{});
    try cleanup();
}

fn handleSignal(sig: c_int) callconv(.C) void {
    last_signal = sig;
    shutdown_requested = true;
    // Log signal receipt - using async-signal-safe functions only
    const msg = "Received signal, initiating shutdown...\n";
    _ = posix.write(posix.STDERR_FILENO, msg, msg.len);
}

fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    // Check environment variable first
    if (std.process.getEnvVarOwned(allocator, "PROXMOX_LXCRI_CONFIG")) |path| {
        // Verify that the file exists and is accessible
        fs.cwd().access(path, .{}) catch |err| {
            try logger_instance.warn("Config file from env var not accessible: {s}", .{@errorName(err)});
            allocator.free(path);
            return err;
        };
        return path;
    } else |err| {
        try logger_instance.debug("Environment variable not set: {s}", .{@errorName(err)});
    }

    // Check default locations
    const default_paths = [_][]const u8{
        "/etc/proxmox-lxcri/config.json",
        "./config.json",
    };

    for (default_paths) |path| {
        if (fs.cwd().access(path, .{})) {
            return try allocator.dupe(u8, path);
        } else |err| {
            logger_instance.debug("Failed to access {s}: {s}", .{ path, @errorName(err) }) catch {};
        }
    }

    return Error.ConfigNotFound;
}
