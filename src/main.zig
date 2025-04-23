const std = @import("std");
const c = std.c;
const os = std.os;
const linux = os.linux;
const posix = std.posix;
const logger_mod = @import("logger");
const config = @import("config.zig");
const types = @import("types");
const fs = std.fs;
const builtin = @import("builtin");
const ProxmoxClient = @import("proxmox").ProxmoxClient;
const errors = @import("error");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Client = http.Client;
const network = @import("network");
const pod = @import("pod");
const oci = @import("oci");
const process = std.process;

const RuntimeError = errors.Error || std.fs.File.OpenError || std.fs.File.ReadError;

const SIGINT = posix.SIG.INT;
const SIGTERM = posix.SIG.TERM;
const SIGHUP = posix.SIG.HUP;

var shutdown_requested: bool = false;
var last_signal: ?c_int = null;
var logger_instance: logger_mod.Logger = undefined;
var proxmox_client: *ProxmoxClient = undefined;

const ConfigError = error{
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
} || std.fs.File.OpenError || std.fs.File.ReadError;

fn printHelp() !void {
    const help_text =
        \\proxmox-lxcri - Proxmox LXC OCI Runtime Interface
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
    if (proxmox_client != undefined) {
        try proxmox_client.stopAllOperations();
        try proxmox_client.closeConnections();
    }
    
    try logger_instance.info("Cleanup completed", .{});
}

fn handleSignal(sig: c_int) callconv(.C) void {
    last_signal = sig;
    shutdown_requested = true;
    // Log signal receipt - using async-signal-safe functions only
    const msg = "Received signal, initiating shutdown...\n";
    const stderr = std.io.getStdErr();
    _ = stderr.write(msg) catch return;
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
            std.debug.print("Memory leak detected!\n", .{});
            process.exit(1);
        }
    }
    const allocator = gpa.allocator();

    // Отримуємо аргументи командного рядка
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

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

    // Читаємо конфігурацію
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Створюємо менеджери
    var network_manager = network.NetworkManager.init(allocator);
    defer network_manager.deinit();

    try logger_instance.info("Starting proxmox-lxcri...", .{});

    // Load configuration
    var cfg = try config.Config.init(allocator, &logger_instance);
    defer cfg.deinit();
    try cfg.loadFromFile(config_path);

    // Initialize Proxmox client
    var client = try ProxmoxClient.init(
        allocator,
        cfg.proxmox.hosts,
        cfg.proxmox.token,
        &logger_instance,
        cfg.proxmox.port,
        cfg.proxmox.node,
    );
    proxmox_client = &client;
    defer proxmox_client.deinit();

    // List and log all LXC containers
    const containers = try proxmox_client.listLXCs();
    defer allocator.free(containers);

    try logger_instance.info("Found {d} LXC containers:", .{containers.len});
    for (containers) |container| {
        try logger_instance.info("Container {d}: {s} (Status: {s})", .{ 
            container.vmid, container.name, @tagName(container.status) 
        });
    }

    // Set up signal handling
    try posix.sigaction(
        posix.SIG.INT,
        &posix.Sigaction{
            .handler = .{ .handler = handleSignal },
            .mask = posix.empty_sigset,
            .flags = 0,
        },
        null,
    );
    try posix.sigaction(
        posix.SIG.TERM,
        &posix.Sigaction{
            .handler = .{ .handler = handleSignal },
            .mask = posix.empty_sigset,
            .flags = 0,
        },
        null,
    );

    // Wait for shutdown signal
    while (!shutdown_requested) {
        std.time.sleep(std.time.ns_per_s);
    }

    if (last_signal) |sig| {
        try logger_instance.info("Received signal: {d}", .{sig});
    }
    try logger_instance.info("Shutting down...", .{});
}

fn getConfigPath(allocator: Allocator) ![]const u8 {
    // Check environment variable first
    if (process.getEnvVarOwned(allocator, "PROXMOX_LXCRI_CONFIG")) |path| {
        // Verify that the file exists and is accessible
        fs.cwd().access(path, .{}) catch |err| {
            try logger_instance.warn("Config file from env var not accessible: {s}", .{@errorName(err)});
            allocator.free(path);
            return errors.Error.FileSystemError;
        };
        return path;
    } else |_| {
        try logger_instance.debug("Environment variable not set, checking default locations", .{});
    }

    // Check default locations
    const default_paths = [_][]const u8{
        "/etc/proxmox-lxcri/config.json",
        "./config.json",
    };

    for (default_paths) |path| {
        fs.cwd().access(path, .{}) catch continue;
        return try allocator.dupe(u8, path);
    }

    return errors.Error.ConfigNotFound;
}
