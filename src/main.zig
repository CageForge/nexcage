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
const process = std.process;
const oci_commands = @import("oci");
const RuntimeError = errors.Error || std.fs.File.OpenError || std.fs.File.ReadError;
const image = @import("image");
const zfs = @import("zfs");
const lxc = @import("lxc");

const SIGINT = posix.SIG.INT;
const SIGTERM = posix.SIG.TERM;
const SIGHUP = posix.SIG.HUP;

var shutdown_requested: bool = false;
var last_signal: ?c_int = null;
var proxmox_client: *ProxmoxClient = undefined;

const RuntimeOptions = struct {
    root: ?[]const u8 = null,
    log: ?[]const u8 = null,
    log_format: ?[]const u8 = null,
    systemd_cgroup: bool = false,
    bundle: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    debug: bool = false,
    allocator: Allocator,

    pub fn init(allocator: Allocator) RuntimeOptions {
        return RuntimeOptions{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeOptions) void {
        if (self.root) |root| {
            self.allocator.free(root);
        }
        if (self.log) |log| {
            self.allocator.free(log);
        }
        if (self.log_format) |log_format| {
            self.allocator.free(log_format);
        }
        if (self.bundle) |bundle| {
            self.allocator.free(bundle);
        }
        if (self.pid_file) |pid_file| {
            self.allocator.free(pid_file);
        }
        if (self.console_socket) |console_socket| {
            self.allocator.free(console_socket);
        }
    }
};

const Command = enum {
    create,
    start,
    state,
    kill,
    delete,
    help,
    unknown,

    pub fn fromString(str: []const u8) Command {
        if (std.mem.eql(u8, str, "create")) return .create;
        if (std.mem.eql(u8, str, "start")) return .start;
        if (std.mem.eql(u8, str, "state")) return .state;
        if (std.mem.eql(u8, str, "kill")) return .kill;
        if (std.mem.eql(u8, str, "delete")) return .delete;
        if (std.mem.eql(u8, str, "help")) return .help;
        return .unknown;
    }
};

const ConfigError = error{
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
} || std.fs.File.OpenError || std.fs.File.ReadError;

fn initLogger(allocator: Allocator, options: RuntimeOptions, cfg: *const config.Config) !void {
    const log_level = if (options.debug) types.LogLevel.debug else types.LogLevel.info;

    // Determine log file path with priority:
    // 1. Command line (--log)
    // 2. Configuration file
    const log_path = if (options.log) |path| path else cfg.runtime.log_path;

    const log_file = if (!options.debug) blk: {
        // Create log directory if it doesn't exist
        const actual_log_path = log_path orelse "/var/log/proxmox-lxcri/runtime.log";
        const log_dir = std.fs.path.dirname(actual_log_path) orelse ".";
        fs.cwd().makePath(log_dir) catch |err| {
            try logger_mod.err("Failed to create log directory: {s}, falling back to stderr", .{@errorName(err)});
            break :blk null;
        };

        const file = fs.cwd().openFile(actual_log_path, .{ .mode = .read_write }) catch |err| {
            // If file doesn't exist, create it
            if (err == error.FileNotFound) {
                const new_file = fs.cwd().createFile(actual_log_path, .{ .truncate = false, .mode = 0o644 }) catch |create_err| {
                    try logger_mod.err("Failed to create log file: {s}, falling back to stderr", .{@errorName(create_err)});
                    break :blk null;
                };
                break :blk new_file;
            }
            try logger_mod.err("Failed to open log file: {s}, falling back to stderr", .{@errorName(err)});
            break :blk null;
        };
        // Move cursor to end of file for appending
        file.seekFromEnd(0) catch |err| {
            try logger_mod.err("Failed to seek to end of log file: {s}, falling back to stderr", .{@errorName(err)});
            file.close();
            break :blk null;
        };
        break :blk file;
    } else null;

    if (log_file) |file| {
        try logger_mod.initWithFile(allocator, file, log_level);
    } else {
        try logger_mod.init(allocator, std.io.getStdErr().writer(), log_level);
    }
}

fn printUsage() !void {
    const usage =
        \\Usage: proxmox-lxcri <command> [options] [container_id]
        \\
        \\Commands:
        \\  create    Create a new container
        \\  start     Start a container
        \\  state     Get container state
        \\  kill      Kill a container
        \\  delete    Delete a container
        \\  help      Show this help message
        \\
        \\Options:
        \\  --help, -h              Show this help message
        \\  --debug                 Enable debug logging
        \\  --systemd-cgroup        Use systemd cgroup
        \\  --root <path>           Root directory for container state
        \\  --log <path>            Log file path
        \\  --log-format <format>   Log format
        \\  --bundle, -b <path>     Path to OCI bundle
        \\  --pid-file <path>       Path to pid file
        \\  --console-socket <path> Path to console socket
        \\
    ;
    try std.io.getStdOut().writer().print("{s}", .{usage});
}

fn parseArgs(allocator: Allocator) !struct {
    command: Command,
    options: RuntimeOptions,
    container_id: ?[]const u8,
} {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip program name

    var command: ?Command = null;
    var options = RuntimeOptions.init(allocator);
    var container_id: ?[]const u8 = null;

    // Перевіряємо, чи є аргументи
    var has_args = false;
    while (args.next()) |arg| {
        has_args = true;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--debug")) {
            options.debug = true;
        } else if (std.mem.eql(u8, arg, "--systemd-cgroup")) {
            options.systemd_cgroup = true;
        } else if (std.mem.eql(u8, arg, "--root")) {
            if (args.next()) |value| {
                options.root = try allocator.dupe(u8, value);
            }
        } else if (std.mem.eql(u8, arg, "--log")) {
            if (args.next()) |value| {
                options.log = try allocator.dupe(u8, value);
            }
        } else if (std.mem.eql(u8, arg, "--log-format")) {
            if (args.next()) |value| {
                options.log_format = try allocator.dupe(u8, value);
            }
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (args.next()) |value| {
                options.bundle = try allocator.dupe(u8, value);
            }
        } else if (std.mem.eql(u8, arg, "--pid-file")) {
            if (args.next()) |value| {
                options.pid_file = try allocator.dupe(u8, value);
            }
        } else if (std.mem.eql(u8, arg, "--console-socket")) {
            if (args.next()) |value| {
                options.console_socket = try allocator.dupe(u8, value);
            }
        } else if (command == null) {
            command = std.meta.stringToEnum(Command, arg) orelse {
                try std.io.getStdErr().writer().print("Unknown command: '{s}'\n", .{arg});
                try printUsage();
                return error.UnknownCommand;
            };
        } else {
            if (container_id == null) {
                container_id = try allocator.dupe(u8, arg);
            } else {
                try logger_mod.err("Unexpected argument: {s}", .{arg});
                return error.UnexpectedArgument;
            }
        }
    }

    if (!has_args or command == null) {
        try printUsage();
        std.process.exit(0);
    }

    return .{
        .command = command.?,
        .options = options,
        .container_id = container_id,
    };
}

fn loadConfig(allocator: Allocator, config_path: ?[]const u8) !config.Config {
    const path = config_path orelse "/etc/proxmox-lxcri/config.json";
    const file = fs.cwd().openFile(path, .{}) catch |err| {
        try logger_mod.err("Failed to open config file '{s}': {s}", .{path, @errorName(err)});
        return error.ConfigError;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        try logger_mod.err("Failed to read config file: {s}", .{@errorName(err)});
        return error.ConfigError;
    };
    defer allocator.free(content);

    var parsed = json.parseFromSlice(config.JsonConfig, allocator, content, .{}) catch |err| {
        try logger_mod.err("Failed to parse config file: {s}", .{@errorName(err)});
        return error.ConfigError;
    };
    defer parsed.deinit();

    // Create temporary logger for configuration initialization
    var temp_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer temp_logger.deinit();

    return try config.Config.fromJson(allocator, parsed.value, &temp_logger);
}

fn cleanup() !void {
    try logger_mod.info("Starting cleanup process...", .{});

    // Stop all active operations
    if (proxmox_client != undefined) {
        try proxmox_client.stopAllOperations();
        try proxmox_client.closeConnections();
    }

    try logger_mod.info("Cleanup completed", .{});
}

fn handleSignal(sig: c_int) callconv(.C) void {
    last_signal = sig;
    shutdown_requested = true;
    // Log signal receipt - using async-signal-safe functions only
    const msg = "Received signal, initiating shutdown...\n";
    const stderr = std.io.getStdErr();
    _ = stderr.write(msg) catch return;
}

fn executeCreate(
    allocator: Allocator,
    args: []const []const u8,
    image_manager: *image.ImageManager,
    zfs_manager: *zfs.ZFSManager,
    lxc_manager: *lxc.LXCManager,
) !void {
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: create requires --bundle and container-id arguments\n");
        return error.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
    var pid_file: ?[]const u8 = null;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --bundle requires a path argument\n");
                return error.InvalidArguments;
            }
            bundle_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--pid-file")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --pid-file requires a path argument\n");
                return error.InvalidArguments;
            }
            pid_file = args[i + 1];
            i += 1;
        } else {
            container_id = arg;
        }
    }

    if (bundle_path == null or container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: both --bundle and container-id are required\n");
        return error.InvalidArguments;
    }

    const cfg = loadConfig(allocator, null) catch |err| {
        try logger_mod.err("Failed to load config: {s}", .{@errorName(err)});
        return err;
    };

    const create = try oci_commands.create.Create.init(
        allocator,
        image_manager,
        zfs_manager,
        lxc_manager,
        null,
        proxmox_client,
        .{
            .container_id = container_id.?,
            .bundle_path = bundle_path.?,
            .image_name = "test-image",
            .image_tag = "latest",
            .zfs_dataset = "rpool/lxc",
            .proxmox_node = cfg.proxmox.node orelse "pve",
            .proxmox_storage = "local-lvm",
        },
        cfg.logger,
        .lxc,
    );
    defer create.deinit();

    try create.create();
}

fn executeStart(container_id: []const u8) !void {
    try oci_commands.start.start(container_id.?, proxmox_client);
}

fn executeState(allocator: Allocator, container_id: []const u8) !void {
    const container_state = try oci_commands.state.getState(
        proxmox_client,
        container_id,
    );
    var container_state_mut = container_state;
    defer container_state_mut.deinit();

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    // Format container state as JSON
    try string.writer().writeAll("{\n");
    try string.writer().print("  \"id\": \"{s}\",\n", .{container_state.id});
    try string.writer().print("  \"name\": \"{s}\",\n", .{container_state.name});
    try string.writer().print("  \"status\": \"{s}\",\n", .{@tagName(container_state.state)});
    try string.writer().print("  \"pid\": {?d},\n", .{container_state.pid});
    try string.writer().print("  \"bundle\": \"{s}\"", .{container_state.bundle});

    if (container_state.annotations) |annotations| {
        try string.writer().writeAll(",\n  \"annotations\": {\n");
        for (annotations, 0..) |annotation, i| {
            try string.writer().print("    \"{s}\": \"{s}\"", .{ annotation.key, annotation.value });
            if (i < annotations.len - 1) {
                try string.writer().writeAll(",\n");
            } else {
                try string.writer().writeAll("\n");
            }
        }
        try string.writer().writeAll("  }\n");
    }
    try string.writer().writeAll("}\n");

    try std.io.getStdOut().writeAll(string.items);
}

fn executeKill(container_id: []const u8, signal: ?[]const u8) !void {
    const sig = if (signal) |s| s else "SIGTERM";
    try oci_commands.kill.kill(container_id, sig, proxmox_client);
}

fn executeDelete(container_id: []const u8) !void {
    try oci_commands.delete.delete(container_id.?, proxmox_client);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments first
    var args = parseArgs(allocator) catch |err| {
        if (err == error.UnknownCommand) {
            std.process.exit(1);
        }
        return err;
    };
    defer {
        args.options.deinit();
        if (args.container_id) |id| {
            allocator.free(id);
        }
    }

    // If help command, show usage and exit
    if (args.command == .help) {
        try printUsage();
        return;
    }

    // Create temporary logger for configuration initialization
    var temp_logger = try logger_mod.LogContext.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer temp_logger.deinit();

    // Create temporary configuration for logger initialization
    var temp_config = try config.Config.init(allocator, &temp_logger);
    defer temp_config.deinit();

    // Initialize logger before loading configuration
    try initLogger(allocator, args.options, &temp_config);

    // Load main configuration
    var cfg = loadConfig(allocator, null) catch |err| {
        if (err == error.ConfigError) {
            try std.io.getStdErr().writer().writeAll("Error: Failed to load configuration. Check the log file for details.\n");
            std.process.exit(1);
        }
        return err;
    };
    defer cfg.deinit();

    // Create separate logger for ProxmoxClient
    var proxmox_logger = try logger_mod.Logger.init(allocator, if (args.options.debug) std.io.getStdErr().writer() else std.io.getStdOut().writer(), if (args.options.debug) types.LogLevel.debug else types.LogLevel.info, "proxmox");
    defer proxmox_logger.deinit();

    // Check for hosts in configuration
    if (cfg.proxmox.hosts.len == 0) {
        try logger_mod.err("No Proxmox hosts configured", .{});
        return error.InvalidConfig;
    }

    // If --root is specified, create directory
    if (args.options.root) |root| {
        try fs.cwd().makePath(root);
    }

    // Initialize Proxmox client
    var proxmox_client_instance = try ProxmoxClient.init(allocator, cfg.proxmox.hosts[0], cfg.proxmox.port, cfg.proxmox.token orelse "", cfg.proxmox.node orelse "pve", &proxmox_logger);
    proxmox_client = &proxmox_client_instance;
    defer proxmox_client_instance.deinit();

    // Initialize managers
    var image_manager_instance = try image.ImageManager.init(allocator, "/var/lib/proxmox-lxcri/images", cfg.logger);
    defer image_manager_instance.deinit();

    var zfs_manager_instance = try zfs.ZFSManager.init(allocator, cfg.logger);
    defer zfs_manager_instance.deinit();

    var lxc_manager_instance = try lxc.LXCManager.init(allocator, cfg.logger);
    defer lxc_manager_instance.deinit();

    // Execute command
    switch (args.command) {
        .create => {
            if (args.container_id == null or args.options.bundle == null) {
                try logger_mod.err("create command requires --bundle and container-id", .{});
                return error.InvalidArguments;
            }
            const bundle_path = try std.fs.cwd().realpathAlloc(allocator, args.options.bundle.?);
            defer allocator.free(bundle_path);
            const config_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_path, "config.json" });
            defer allocator.free(config_path);
            try executeCreate(allocator, &[_][]const u8{
                bundle_path,
                config_path,
            }, image_manager_instance, zfs_manager_instance, lxc_manager_instance);
        },
        .start => {
            if (args.container_id == null) {
                try logger_mod.err("start command requires container-id", .{});
                return error.InvalidArguments;
            }
            try oci_commands.start.start(args.container_id.?, proxmox_client);
        },
        .state => {
            if (args.container_id == null) {
                try logger_mod.err("state command requires container-id", .{});
                return error.InvalidArguments;
            }
            try executeState(allocator, args.container_id.?);
        },
        .kill => {
            if (args.container_id == null) {
                try logger_mod.err("kill command requires container-id", .{});
                return error.InvalidArguments;
            }
            try oci_commands.kill.kill(args.container_id.?, "SIGTERM", proxmox_client);
        },
        .delete => {
            if (args.container_id == null) {
                try logger_mod.err("delete command requires container-id", .{});
                return error.InvalidArguments;
            }
            try oci_commands.delete.delete(args.container_id.?, proxmox_client);
        },
        .help => unreachable, // Already handled above
        .unknown => {
            try logger_mod.err("Unknown command", .{});
            try printUsage();
            return error.UnknownCommand;
        },
    }
}

fn getConfigPath(allocator: Allocator) ![]const u8 {
    // Check environment variable first
    if (process.getEnvVarOwned(allocator, "PROXMOX_LXCRI_CONFIG")) |path| {
        // Verify that the file exists and is accessible
        fs.cwd().access(path, .{}) catch |err| {
            try logger_mod.warn("Config file from env var not accessible: {s}", .{@errorName(err)});
            allocator.free(path);
            return errors.Error.FileSystemError;
        };
        return path;
    } else |_| {
        try logger_mod.debug("Environment variable not set, checking default locations", .{});
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
