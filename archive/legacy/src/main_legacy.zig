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
const oci = @import("oci");
const image = @import("image");
const RuntimeError = errors.Error || std.fs.File.OpenError || std.fs.File.ReadError;
const json_parser = @import("json_helpers");
const spec_mod = @import("oci").spec;

// Signal constants moved to types.zig
const SIGINT = types.SIGINT;
const SIGTERM = types.SIGTERM;
const SIGHUP = types.SIGHUP;

var shutdown_requested: bool = false;
var last_signal: ?c_int = null;
var proxmox_client: ?*ProxmoxClient = null;

// RuntimeOptions moved to types.zig
const RuntimeOptions = types.RuntimeOptions;

// Command enum moved to types.zig
const Command = types.Command;

// ConfigError moved to types.zig
const ConfigError = types.ConfigError;

const StaticMap = std.StaticStringMap(Command).initComptime(.{
    .{ "create", .create },
    .{ "start", .start },
    .{ "stop", .stop },
    .{ "delete", .delete },
    .{ "list", .list },
    .{ "info", .info },
    .{ "state", .state },
    .{ "kill", .kill },
    .{ "pause", .pause },
    .{ "resume", .resume_container },
    .{ "exec", .exec },
    .{ "ps", .ps },
    .{ "run", .run },
    .{ "events", .events },
    .{ "spec", .spec },
    .{ "checkpoint", .checkpoint },
    .{ "restore", .restore },
    .{ "update", .update },
    .{ "features", .features },
    .{ "generate-config", .generate_config },
    .{ "help", .help },
    .{ "h", .help },
    .{ "--help", .help },
    .{ "-h", .help },
    .{ "--version", .version },
    .{ "-v", .version },
    .{ "-V", .version },
});

/// Parses a command string into a Command enum using StaticStringMap
///
/// Efficiently maps command line arguments to internal command representations
/// using a compile-time generated hash map for maximum performance.
///
/// Arguments:
/// - command: Command string from command line arguments
///
/// Returns: Corresponding Command enum value, or .unknown if not recognized
fn parseCommand(command: []const u8) Command {
    return StaticMap.get(command) orelse .unknown;
}

/// Initializes the global logging system with configuration-based settings
///
/// Sets up logging with proper file handling, directory creation, and fallback
/// mechanisms. Supports both command-line overrides and configuration file settings.
///
/// Arguments:
/// - allocator: Memory allocator for logger operations
/// - options: Runtime options from command line parsing
/// - cfg: Configuration object with logging settings
///
/// Returns: Error if logger initialization fails
fn initLogger(allocator: Allocator, options: RuntimeOptions, cfg: *const config.Config) !void {
    const log_level = if (options.debug) types.LogLevel.debug else types.LogLevel.info;

    // Determine log file path with priority:
    // 1. Command line (--log)
    // 2. Configuration file
    const log_path = if (options.log) |path| path else cfg.runtime.log_path;

    const log_file = blk: {
        // Create log directory if it doesn't exist
        const actual_log_path = log_path orelse "/var/log/proxmox-lxcri/runtime.log";
        const log_dir = std.fs.path.dirname(actual_log_path) orelse ".";

        // Try to create directory with proper permissions
        fs.cwd().makePath(log_dir) catch |err| {
            try logger_mod.err("Failed to create log directory: {s}, falling back to stderr", .{@errorName(err)});
            break :blk null;
        };

        // Try to open existing file first
        const file = fs.cwd().openFile(actual_log_path, .{ .mode = .read_write }) catch |err| {
            // If file doesn't exist, create it
            if (err == error.FileNotFound) {
                const new_file = fs.cwd().createFile(actual_log_path, .{
                    .truncate = false,
                    .mode = 0o644,
                    .exclusive = false,
                }) catch |create_err| {
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
    };

    if (log_file) |file| {
        try logger_mod.initWithFile(allocator, file, log_level, "proxmox-lxcri");
        try logger_mod.info("Logging initialized to file", .{});
    } else {
        try logger_mod.init(allocator, std.io.getStdErr().writer(), log_level);
        try logger_mod.info("Logging initialized to stderr", .{});
    }
}

pub fn parseArgsFromArray(allocator: Allocator, argv: []const []const u8) !struct {
    command: Command,
    options: RuntimeOptions,
    container_id: ?[]const u8,
} {
    var i: usize = 1; // Пропускаємо program name
    var command: ?Command = null;
    var options = RuntimeOptions.init(allocator);
    var container_id: ?[]const u8 = null;
    var has_args = false;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        has_args = true;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            oci.help.printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            oci.help.printVersion();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--debug")) {
            options.debug = true;
        } else if (std.mem.eql(u8, arg, "--systemd-cgroup")) {
            options.systemd_cgroup = true;
        } else if (std.mem.eql(u8, arg, "--root")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.root = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--log")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.log = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--log-format")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.log_format = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.bundle = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--pid-file")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.pid_file = try allocator.dupe(u8, argv[i]);
            }
        } else if (std.mem.eql(u8, arg, "--console-socket")) {
            if (i + 1 < argv.len) {
                i += 1;
                options.console_socket = try allocator.dupe(u8, argv[i]);
            }
        } else if (command == null) {
            command = parseCommand(arg);
            if (command.? == .unknown) {
                try std.io.getStdErr().writer().print("Unknown command: '{s}'\n", .{arg});
                oci.help.printUsage();
                return error.UnknownCommand;
            }
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
        oci.help.printUsage();
        std.process.exit(0);
    }
    return .{
        .command = command.?,
        .options = options,
        .container_id = container_id,
    };
}

fn parseArgs(allocator: Allocator) !struct {
    command: Command,
    options: RuntimeOptions,
    container_id: ?[]const u8,
} {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    while (args.next()) |arg| {
        try argv.append(arg);
    }
    return parseArgsFromArray(allocator, argv.items);
}

fn loadConfig(allocator: Allocator, config_path: ?[]const u8) !config.Config {
    // Якщо вказано конкретний шлях, використовуємо його
    if (config_path) |path| {
        return try loadConfigFromPath(allocator, path);
    }

    // Інакше перевіряємо файли за замовчуванням у порядку пріоритету
    const default_paths = [_][]const u8{
        "./config.json", // Поточна директорія
        "/etc/proxmox-lxcri/config.json", // Системний конфіг
        "/etc/proxmox-lxcri/proxmox-lxcri.json", // Альтернативний системний конфіг
    };

    for (default_paths) |path| {
        const result = loadConfigFromPath(allocator, path) catch |err| {
            // Логуємо помилку, але продовжуємо перевіряти наступні файли
            logger_mod.warn("Failed to load config from '{s}': {s}", .{ path, @errorName(err) }) catch {};
            continue;
        };
        // Якщо успішно завантажили, повертаємо результат
        return result;
    }

    // Якщо жоден файл не знайдено, повертаємо помилку
    try logger_mod.err("No configuration file found. Tried: {s}", .{default_paths[0]});
    for (default_paths[1..]) |path| {
        try logger_mod.err("  {s}", .{path});
    }
    return error.ConfigError;
}

fn loadConfigFromPath(allocator: Allocator, path: []const u8) !config.Config {
    const file = fs.cwd().openFile(path, .{}) catch |err| {
        try logger_mod.err("Failed to open config file '{s}': {s}", .{ path, @errorName(err) });
        return error.ConfigError;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        try logger_mod.err("Failed to read config file: {s}", .{@errorName(err)});
        return error.ConfigError;
    };
    defer allocator.free(content);

    // Use arena allocator for JSON parsing to avoid memory leaks
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const parsed = try json_parser.parseWithUnknownFields(config.JsonConfig, arena_allocator, content);
    // No need to manually free arena-allocated memory

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

// Import zfs module for ZFSManager type
const zfs = @import("zfs");

fn executeCreate(
    allocator: Allocator,
    args: []const []const u8,
    _image_manager: *image.ImageManager,
    _zfs_manager: *zfs.ZFSManager,
    _lxc_manager: ?*oci.lxc.LXCManager,
    temp_logger: *logger_mod.Logger,
    _proxmox_client: ?*ProxmoxClient,
) !void {
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: create requires --bundle and container-id arguments\n");
        return error.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
    var runtime_type: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, arg, "--runtime") or std.mem.eql(u8, arg, "-r")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --runtime requires a type argument\n");
                return error.InvalidArguments;
            }
            runtime_type = args[i + 1];
            i += 1;
        } else {
            container_id = arg;
        }
    }

    if (bundle_path == null or container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: both --bundle and container-id are required\n");
        return error.InvalidArguments;
    }

    // Create bundle directory if it does not exist
    var bundle_dir = std.fs.cwd().openDir(bundle_path.?, .{}) catch |err| {
        try std.io.getStdErr().writer().print("Cannot access bundle directory '{s}': {s}\n", .{ bundle_path.?, @errorName(err) });
        return error.InvalidBundle;
    };
    defer bundle_dir.close();

    // Create OCI config file
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_path.?, "config.json" });
    defer allocator.free(config_path);

    bundle_dir.access("config.json", .{}) catch |err| {
        try logger_mod.err("Failed to access config.json in bundle: {s}", .{@errorName(err)});
        return error.InvalidBundle;
    };

    // Create temporary logger for config initialization
    var config_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer config_logger.deinit();

    // Initialize configuration
    var cfg = try loadConfig(allocator, null);
    defer cfg.deinit();

    // Determine runtime type based on CLI args, config, or container ID pattern
    var actual_runtime_type: types.RuntimeType = .lxc; // Default fallback

    if (runtime_type) |rt| {
        // CLI argument takes precedence
        if (std.mem.eql(u8, rt, "crun") or std.mem.eql(u8, rt, "runc")) {
            actual_runtime_type = .crun;
        } else if (std.mem.eql(u8, rt, "lxc") or std.mem.eql(u8, rt, "proxmox-lxc")) {
            actual_runtime_type = .lxc;
        } else if (std.mem.eql(u8, rt, "vm")) {
            actual_runtime_type = .vm;
        }
    } else if (cfg.default_runtime) |default_rt| {
        // Use default from config
        if (std.mem.eql(u8, default_rt, "crun") or std.mem.eql(u8, default_rt, "runc")) {
            actual_runtime_type = .crun;
        } else if (std.mem.eql(u8, default_rt, "lxc") or std.mem.eql(u8, default_rt, "proxmox-lxc")) {
            actual_runtime_type = .lxc;
        } else if (std.mem.eql(u8, default_rt, "vm")) {
            actual_runtime_type = .vm;
        }
    } else {
        // Auto-detect based on container ID pattern
        if (std.mem.startsWith(u8, container_id.?, "lxc-") or
            std.mem.startsWith(u8, container_id.?, "db-") or
            std.mem.startsWith(u8, container_id.?, "vm-"))
        {
            actual_runtime_type = .lxc;
        }
    }

    cfg.setRuntimeType(actual_runtime_type);

    // Create container specification
    var container_spec = spec_mod.Spec.init();

    // Create Process and Root
    var container_process = try types.Process.init();
    defer container_process.deinit(allocator);

    var container_root = spec_mod.Root.init();
    defer container_root.deinit(allocator);

    // Set basic parameters
    const oci_version = try allocator.dupe(u8, "1.0.2");
    defer allocator.free(oci_version);
    container_spec.ociVersion = oci_version;

    const hostname = try allocator.dupe(u8, "container");
    defer allocator.free(hostname);
    container_spec.hostname = hostname;

    const args_array2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(args_array2);

    const shell_path = try allocator.dupe(u8, "/bin/sh");
    defer allocator.free(shell_path);
    args_array2[0] = shell_path;

    container_process.args = args_array2;

    const cwd_path = try allocator.dupe(u8, "/");
    defer allocator.free(cwd_path);
    container_process.cwd = cwd_path;

    container_spec.process = container_process;

    const root_path = try allocator.dupe(u8, "/var/lib/containers/rootfs");
    defer allocator.free(root_path);
    container_root.path = root_path;
    container_root.readonly = false;
    container_spec.root = container_root;

    // Create runtime managers based on runtime type
    var crun_manager: ?*oci.crun.CrunManager = null;
    var crun_logger: ?logger_mod.Logger = null;

    if (actual_runtime_type == .crun) {
        // Create dedicated logger for CrunManager
        crun_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "crun");
        crun_manager = try oci.crun.CrunManager.init(allocator, &crun_logger.?);
    }

    // Create container
    const create = try oci.create.Create.init(
        allocator,
        _image_manager,
        _zfs_manager,
        _lxc_manager,
        if (actual_runtime_type == .crun) crun_manager else null,
        _proxmox_client.?,
        .{
            .container_id = container_id.?,
            .bundle_path = bundle_path.?,
            .image_name = "test-image",
            .image_tag = "latest",
            .zfs_dataset = "rpool/lxc",
            .proxmox_node = cfg.proxmox.node orelse "pve",
            .proxmox_storage = "local-lvm",
        },
        temp_logger,
        actual_runtime_type,
    );
    defer create.deinit();
    if (crun_manager) |cm| {
        defer cm.deinit();
    }
    if (crun_logger) |*cl| {
        defer cl.deinit();
    }

    try create.create();
}

fn executeStart(container_id: []const u8) !void {
    try oci.start.start(container_id, proxmox_client);
}

fn executeState(allocator: Allocator, container_id: []const u8) !void {
    var container_state = try oci.state.getState(
        proxmox_client,
        container_id,
    );
    defer container_state.deinit();

    // Створюємо структуру для серіалізації
    const StateResponse = struct {
        ociVersion: []const u8,
        id: []const u8,
        status: []const u8,
        pid: i64,
        bundle: []const u8,
    };

    const response = StateResponse{
        .ociVersion = container_state.state.oci_version,
        .id = container_state.state.id,
        .status = container_state.state.status,
        .pid = container_state.state.pid,
        .bundle = container_state.state.bundle,
    };

    const state_json = try std.json.stringifyAlloc(allocator, response, .{});
    defer allocator.free(state_json);
    try std.io.getStdOut().writer().print("{s}\n", .{state_json});
}

fn executeStop(container_id: []const u8) !void {
    try oci.stop.stop(container_id, proxmox_client);
}

fn executeKill(container_id: []const u8, signal: ?[]const u8) !void {
    const sig = if (signal) |s| s else "SIGTERM";
    try oci.kill.kill(container_id, sig, proxmox_client);
}

fn executeDelete(container_id: []const u8) !void {
    try oci.delete.delete(container_id, proxmox_client);
}

fn executeGenerateConfig(
    allocator: Allocator,
    args: []const []const u8,
) !void {
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: generate-config requires --bundle and container-id arguments\n");
        return error.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
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
        } else {
            container_id = arg;
        }
    }

    if (bundle_path == null or container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: both --bundle and container-id are required\n");
        return error.InvalidArguments;
    }

    // Створюємо директорію bundle якщо не існує
    try std.fs.cwd().makePath(bundle_path.?);

    // Створюємо файл конфігурації OCI
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_path.?, "config.json" });
    defer allocator.free(config_path);

    const oci_config = try std.json.stringifyAlloc(allocator, .{
        .ociVersion = "1.0.2",
        .process = .{
            .terminal = false,
            .user = .{
                .uid = 0,
                .gid = 0,
            },
            .args = &[_][]const u8{"/bin/sh"},
            .env = &[_][]const u8{"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
            .cwd = "/",
        },
        .root = .{
            .path = "rootfs",
            .readonly = false,
        },
        .hostname = container_id.?,
        .mounts = &[_]struct {
            destination: []const u8,
            type: []const u8,
            source: []const u8,
            options: []const []const u8,
        }{
            .{
                .destination = "/proc",
                .type = "proc",
                .source = "proc",
                .options = &[_][]const u8{},
            },
            .{
                .destination = "/dev",
                .type = "tmpfs",
                .source = "tmpfs",
                .options = &[_][]const u8{ "nosuid", "strictatime", "mode=755", "size=65536k" },
            },
            .{
                .destination = "/dev/pts",
                .type = "devpts",
                .source = "devpts",
                .options = &[_][]const u8{ "nosuid", "noexec", "newinstance", "ptmxmode=0666", "mode=0620", "gid=5" },
            },
            .{
                .destination = "/dev/shm",
                .type = "tmpfs",
                .source = "shm",
                .options = &[_][]const u8{ "nosuid", "noexec", "nodev", "mode=1777", "size=65536k" },
            },
            .{
                .destination = "/dev/mqueue",
                .type = "mqueue",
                .source = "mqueue",
                .options = &[_][]const u8{ "nosuid", "noexec", "nodev" },
            },
            .{
                .destination = "/sys",
                .type = "sysfs",
                .source = "sysfs",
                .options = &[_][]const u8{ "nosuid", "noexec", "nodev", "ro" },
            },
            .{
                .destination = "/sys/fs/cgroup",
                .type = "cgroup",
                .source = "cgroup",
                .options = &[_][]const u8{ "nosuid", "noexec", "nodev", "relatime", "ro" },
            },
        },
        .linux = .{
            .namespaces = &[_]struct {
                type: []const u8,
            }{
                .{ .type = "pid" },
                .{ .type = "network" },
                .{ .type = "ipc" },
                .{ .type = "uts" },
                .{ .type = "mount" },
            },
            .resources = .{
                .devices = &[_]struct {
                    allow: bool,
                    access: []const u8,
                }{
                    .{
                        .allow = false,
                        .access = "rwm",
                    },
                },
            },
        },
    }, .{});
    defer allocator.free(oci_config);

    try std.fs.cwd().writeFile(.{
        .data = oci_config,
        .sub_path = config_path,
    });

    try std.io.getStdOut().writer().print("Generated OCI config at {s}\n", .{config_path});
}

// Helper function to execute create command logic
fn executeCreateCommand(allocator: Allocator, args: []const []const u8, temp_logger: *logger_mod.Logger) !void {
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: create requires --bundle and container-id arguments\n");
        return error.InvalidArguments;
    }

    var bundle_path: ?[]const u8 = null;
    var container_id: ?[]const u8 = null;
    var runtime_type: ?[]const u8 = null;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        try temp_logger.info("Parsing arg[{d}]: {s}", .{ i, arg });

        if (std.mem.startsWith(u8, arg, "--bundle=")) {
            bundle_path = arg[9..]; // Skip "--bundle="
            try temp_logger.info("Set bundle_path: {s}", .{bundle_path.?});
        } else if (std.mem.startsWith(u8, arg, "-b=")) {
            bundle_path = arg[3..]; // Skip "-b="
            try temp_logger.info("Set bundle_path: {s}", .{bundle_path.?});
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --bundle requires a path argument\n");
                return error.InvalidArguments;
            }
            bundle_path = args[i + 1];
            try temp_logger.info("Set bundle_path: {s}", .{bundle_path.?});
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--runtime=")) {
            runtime_type = arg[10..]; // Skip "--runtime="
            try temp_logger.info("Set runtime_type: {s}", .{runtime_type.?});
        } else if (std.mem.eql(u8, arg, "--runtime")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --runtime requires a type argument\n");
                return error.InvalidArguments;
            }
            runtime_type = args[i + 1];
            try temp_logger.info("Set runtime_type: {s}", .{runtime_type.?});
            i += 1;
        } else if (!std.mem.eql(u8, arg, "create")) {
            // This should be the container ID
            if (container_id == null) {
                container_id = arg;
                try temp_logger.info("Set container_id: {s}", .{container_id.?});
            }
        }
    }

    if (bundle_path == null) {
        try std.io.getStdErr().writer().writeAll("Error: --bundle argument is required\n");
        return error.InvalidArguments;
    }

    if (container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: container-id argument is required\n");
        return error.InvalidArguments;
    }

    try temp_logger.info("Creating container: {s} with bundle: {s}", .{ container_id.?, bundle_path.? });

    // Load configuration
    var cfg = try loadConfig(allocator, null);
    defer cfg.deinit();

    // Determine runtime type
    var actual_runtime_type: types.RuntimeType = .lxc; // Default to lxc for Proxmox integration
    if (runtime_type) |rt| {
        if (std.mem.eql(u8, rt, "crun") or std.mem.eql(u8, rt, "runc")) {
            actual_runtime_type = .crun;
        } else if (std.mem.eql(u8, rt, "lxc") or std.mem.eql(u8, rt, "proxmox-lxc")) {
            actual_runtime_type = .lxc;
        } else if (std.mem.eql(u8, rt, "vm")) {
            actual_runtime_type = .vm;
        }
    }

    cfg.setRuntimeType(actual_runtime_type);

    // Create appropriate runtime manager based on runtime type
    switch (actual_runtime_type) {
        .crun => {
            var crun_manager = try oci.crun.CrunManager.init(allocator, temp_logger);
            defer crun_manager.deinit();

            // Execute create
            try crun_manager.createContainer(container_id.?, bundle_path.?, null);
            try temp_logger.info("Successfully created crun container: {s}", .{container_id.?});
        },
        .lxc => {
            // For LXC, we need to use the full create flow from src/oci/create.zig
            // This requires more complex setup with image manager, zfs manager, etc.
            try temp_logger.info("LXC runtime requires full create flow - not implemented in simple command", .{});
            try std.io.getStdErr().writer().writeAll("Error: LXC runtime requires full create flow. Use the main create function instead.\n");
            return error.RuntimeNotImplemented;
        },
        .vm => {
            try temp_logger.info("VM runtime not implemented in simple command", .{});
            try std.io.getStdErr().writer().writeAll("Error: VM runtime not implemented in simple command.\n");
            return error.RuntimeNotImplemented;
        },
    }
}

// Helper function to execute start command logic
fn executeStartCommand(allocator: Allocator, args: []const []const u8, temp_logger: *logger_mod.Logger) !void {
    if (args.len < 3) {
        try std.io.getStdErr().writer().writeAll("Error: start requires container-id argument\n");
        return error.InvalidArguments;
    }

    const container_id = args[2];
    // Create crun manager
    var crun_manager = try oci.crun.CrunManager.init(allocator, temp_logger);
    defer crun_manager.deinit();

    // Start container using crun
    try crun_manager.startContainer(container_id);
    try temp_logger.info("Successfully started container: {s}", .{container_id});
}

// Helper function to execute spec command logic
fn executeSpecCommand(allocator: Allocator, args: []const []const u8, temp_logger: *logger_mod.Logger) !void {
    var bundle_path: ?[]const u8 = null;
    var i: usize = 1;

    // Parse arguments
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--bundle=")) {
            bundle_path = arg[9..]; // Skip "--bundle="
        } else if (std.mem.startsWith(u8, arg, "-b=")) {
            bundle_path = arg[3..]; // Skip "-b="
        } else if (std.mem.eql(u8, arg, "--bundle") or std.mem.eql(u8, arg, "-b")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --bundle requires a path argument\n");
                return error.InvalidArguments;
            }
            bundle_path = args[i + 1];
            i += 1;
        } else if (!std.mem.eql(u8, arg, "spec") and !std.mem.startsWith(u8, arg, "-")) {
            // If no --bundle specified, treat as bundle path
            if (bundle_path == null) {
                bundle_path = arg;
            }
        }
    }

    // Default to current directory if no bundle specified
    if (bundle_path == null) {
        bundle_path = ".";
    }

    try temp_logger.info("Generating OCI spec in bundle: {s}", .{bundle_path.?});

    // Create crun manager
    var crun_manager = try oci.crun.CrunManager.init(allocator, temp_logger);
    defer crun_manager.deinit();

    // Generate spec
    try crun_manager.generateSpec(bundle_path.?);
    try temp_logger.info("Successfully generated OCI spec in bundle: {s}", .{bundle_path.?});
}

// Helper function to execute restore command logic
fn executeRestoreCommand(allocator: Allocator, args: []const []const u8, temp_logger: *logger_mod.Logger) !void {
    if (args.len < 3) {
        try std.io.getStdErr().writer().writeAll("Error: restore requires container-id argument\n");
        return error.InvalidArguments;
    }

    var container_id: ?[]const u8 = null;
    var checkpoint_path: ?[]const u8 = null;
    var snapshot_name: ?[]const u8 = null;
    var i: usize = 1;

    // Parse arguments
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--image-path=")) {
            checkpoint_path = arg[13..]; // Skip "--image-path="
        } else if (std.mem.eql(u8, arg, "--image-path")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --image-path requires a path argument\n");
                return error.InvalidArguments;
            }
            checkpoint_path = args[i + 1];
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--snapshot=")) {
            snapshot_name = arg[11..]; // Skip "--snapshot="
        } else if (std.mem.eql(u8, arg, "--snapshot")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --snapshot requires a name argument\n");
                return error.InvalidArguments;
            }
            snapshot_name = args[i + 1];
            i += 1;
        } else if (!std.mem.eql(u8, arg, "restore") and !std.mem.startsWith(u8, arg, "-")) {
            // This should be the container ID
            if (container_id == null) {
                container_id = arg;
            }
        }
    }

    if (container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: container-id argument is required\n");
        return error.InvalidArguments;
    }

    try temp_logger.info("Restoring container from checkpoint: {s}", .{container_id.?});

    // Create crun manager
    var crun_manager = try oci.crun.CrunManager.init(allocator, temp_logger);
    defer crun_manager.deinit();

    // Restore container
    try crun_manager.restoreContainer(container_id.?, checkpoint_path, snapshot_name);
    try temp_logger.info("Successfully restored container: {s}", .{container_id.?});
}

// Helper function to execute checkpoint command logic
fn executeCheckpointCommand(allocator: Allocator, args: []const []const u8, temp_logger: *logger_mod.Logger) !void {
    if (args.len < 3) {
        try std.io.getStdErr().writer().writeAll("Error: checkpoint requires container-id argument\n");
        return error.InvalidArguments;
    }

    var container_id: ?[]const u8 = null;
    var checkpoint_path: ?[]const u8 = null;
    var i: usize = 1;

    // Parse arguments
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.startsWith(u8, arg, "--image-path=")) {
            checkpoint_path = arg[13..]; // Skip "--image-path="
        } else if (std.mem.eql(u8, arg, "--image-path")) {
            if (i + 1 >= args.len) {
                try std.io.getStdErr().writer().writeAll("Error: --image-path requires a path argument\n");
                return error.InvalidArguments;
            }
            checkpoint_path = args[i + 1];
            i += 1;
        } else if (!std.mem.eql(u8, arg, "checkpoint") and !std.mem.startsWith(u8, arg, "-")) {
            // This should be the container ID
            if (container_id == null) {
                container_id = arg;
            }
        }
    }

    if (container_id == null) {
        try std.io.getStdErr().writer().writeAll("Error: container-id argument is required\n");
        return error.InvalidArguments;
    }

    try temp_logger.info("Creating checkpoint for container: {s}", .{container_id.?});

    // Create crun manager
    var crun_manager = try oci.crun.CrunManager.init(allocator, temp_logger);
    defer crun_manager.deinit();

    // Create checkpoint
    try crun_manager.checkpointContainer(container_id.?, checkpoint_path);
    try temp_logger.info("Successfully created checkpoint for container: {s}", .{container_id.?});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    defer {
        // Ensure global proxmox_client is cleaned on any exit path
        if (proxmox_client) |pc| {
            pc.deinit();
            allocator.destroy(pc);
            proxmox_client = null;
        }
    }

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        oci.help.printUsage();
        return;
    }

    const command = parseCommand(args[1]);

    // Create temporary logger
    var temp_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer temp_logger.deinit();

    // Initialize managers for create command
    var image_manager: ?*image.ImageManager = null;
    var zfs_manager: ?*zfs.ZFSManager = null;
    var lxc_manager: ?*oci.lxc.LXCManager = null;

    if (command == .create) {
        // Initialize image manager
        const umoci_path = "/usr/bin/umoci";
        const images_dir = "./images";
        image_manager = try image.ImageManager.init(allocator, umoci_path, images_dir);
        defer if (image_manager) |img_mgr| img_mgr.deinit();

        // Initialize ZFS manager
        zfs_manager = try zfs.ZFSManager.init(allocator, &temp_logger);
        defer if (zfs_manager) |zfs_mgr| zfs_mgr.deinit();

        // Initialize LXC manager
        lxc_manager = try oci.lxc.LXCManager.init(allocator);
        defer if (lxc_manager) |lxc_mgr| lxc_mgr.deinit();

        // Initialize Proxmox client
        var cfg = try loadConfig(allocator, null);
        defer cfg.deinit();

        const node = cfg.proxmox.node orelse "localhost";
        try temp_logger.info("Proxmox node from config: '{s}'", .{node});

        proxmox_client = try allocator.create(ProxmoxClient);
        proxmox_client.?.* = try ProxmoxClient.init(allocator, "/usr/bin/pct", node, &temp_logger);
    }

    // Create temporary logger for command execution
    var main_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer main_logger.deinit();

    // Execute command
    switch (command) {
        .create => {
            try executeCreate(allocator, args, image_manager.?, zfs_manager.?, lxc_manager, &main_logger, proxmox_client.?);
        },
        .list => {
            try temp_logger.info("Listing containers...", .{});

            // Create crun manager
            var crun_manager = try oci.crun.CrunManager.init(allocator, &temp_logger);
            defer crun_manager.deinit();

            try std.io.getStdOut().writer().print("\n=== CRUN Containers ===\n", .{});
            // List containers using crun
            try crun_manager.listContainers();

            try std.io.getStdOut().writer().print("\n=== PROXMOX LXC Containers ===\n", .{});
            // Try to load configuration and create proxmox client
            var cfg = loadConfig(allocator, null) catch |err| {
                try temp_logger.info("Could not load config for proxmox: {s}", .{@errorName(err)});
                try std.io.getStdOut().writer().print("No proxmox configuration found\n", .{});
                return;
            };
            defer cfg.deinit();

            // Create proxmox client
            const node = cfg.proxmox.node orelse "localhost";

            var local_proxmox_client = ProxmoxClient.init(allocator, "/usr/bin/pct", node, &temp_logger) catch |err| {
                try temp_logger.info("Could not create proxmox client: {s}", .{@errorName(err)});
                try std.io.getStdOut().writer().print("Could not connect to proxmox\n", .{});
                return;
            };
            defer local_proxmox_client.deinit();

            // List containers using proxmox
            oci.list.list(&local_proxmox_client) catch |err| {
                try temp_logger.info("Could not list proxmox containers: {s}", .{@errorName(err)});
                try std.io.getStdOut().writer().print("Error listing proxmox containers\n", .{});
            };
        },
        .state => {
            if (args.len < 3) {
                try std.io.getStdErr().writer().writeAll("Error: state requires container-id argument\n");
                return error.InvalidArguments;
            }

            const container_id = args[2];
            try temp_logger.info("Getting state for container: {s}", .{container_id});

            // Create crun manager
            var crun_manager = try oci.crun.CrunManager.init(allocator, &temp_logger);
            defer crun_manager.deinit();

            // Get container state using crun
            const state = try crun_manager.getContainerState(container_id);
            try temp_logger.info("Container {s} state: {s}", .{ container_id, @tagName(state) });
        },
        .start => {
            try executeStartCommand(allocator, args, &temp_logger);
        },
        .run => {
            try oci.run.executeRun(allocator, args, &temp_logger);
        },
        .help => {
            if (args.len >= 3) {
                // Show help for specific command: help <command>
                oci.help.printCommandHelp(args[2]);
            } else {
                // Show general help
                oci.help.printUsage();
            }
        },
        .version => {
            oci.help.printVersion();
        },
        .spec => {
            try executeSpecCommand(allocator, args, &temp_logger);
        },
        .checkpoint => {
            try executeCheckpointCommand(allocator, args, &temp_logger);
        },
        .restore => {
            try executeRestoreCommand(allocator, args, &temp_logger);
        },
        .unknown => {
            try std.io.getStdErr().writer().writeAll("Error: Unknown command. Use 'help' for usage information.\n");
            return error.InvalidCommand;
        },
        else => {
            try std.io.getStdErr().writer().writeAll("Command not implemented in this test version\n");
        },
    }

    // Cleanup proxmox_client at the end
    if (proxmox_client) |pc| {
        pc.deinit();
        allocator.destroy(pc);
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

// Additional command execution functions
fn executeList(allocator: Allocator, logger: *logger_mod.Logger) !void {
    _ = allocator;
    _ = logger;
    try oci.list.list(proxmox_client);
}

fn executeInfo(allocator: Allocator, container_id: ?[]const u8, logger: *logger_mod.Logger) !void {
    _ = allocator;
    _ = logger;
    try oci.info.info(container_id, proxmox_client);
}

// fn executeExec(allocator: Allocator, container_id: []const u8, command: []const u8, args: ?[]const []const u8, logger: *logger_mod.Logger) !void {
//     TODO: Implement exec functionality
// }
