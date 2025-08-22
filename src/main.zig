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
const RuntimeError = errors.Error || std.fs.File.OpenError || std.fs.File.ReadError;
const image = @import("image");
const zfs = @import("zfs");
const json_parser = @import("json_helpers");
const spec_mod = @import("oci").spec;
const RuntimeType = @import("oci").runtime.RuntimeType;

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
    stop,
    state,
    kill,
    delete,
    list,
    info,
    pause,
    resume_container,
    exec,
    ps,
    events,
    spec,
    checkpoint,
    restore,
    update,
    features,
    help,
    generate_config,
    unknown,
};

const ConfigError = error{
    InvalidConfigFormat,
    InvalidLogPath,
    FailedToCreateLogFile,
    FailedToParseConfig,
} || std.fs.File.OpenError || std.fs.File.ReadError;

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "create")) return .create;
    if (std.mem.eql(u8, command, "start")) return .start;
    if (std.mem.eql(u8, command, "stop")) return .stop;
    if (std.mem.eql(u8, command, "state")) return .state;
    if (std.mem.eql(u8, command, "kill")) return .kill;
    if (std.mem.eql(u8, command, "delete")) return .delete;
    if (std.mem.eql(u8, command, "list")) return .list;
    if (std.mem.eql(u8, command, "info")) return .info;
    if (std.mem.eql(u8, command, "pause")) return .pause;
    if (std.mem.eql(u8, command, "resume")) return .resume_container;
    if (std.mem.eql(u8, command, "exec")) return .exec;
    if (std.mem.eql(u8, command, "ps")) return .ps;
    if (std.mem.eql(u8, command, "events")) return .events;
    if (std.mem.eql(u8, command, "spec")) return .spec;
    if (std.mem.eql(u8, command, "checkpoint")) return .checkpoint;
    if (std.mem.eql(u8, command, "restore")) return .restore;
    if (std.mem.eql(u8, command, "update")) return .update;
    if (std.mem.eql(u8, command, "features")) return .features;
    if (std.mem.eql(u8, command, "help")) return .help;
    if (std.mem.eql(u8, command, "generate-config")) return .generate_config;
    return .unknown;
}

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

fn printUsage() void {
    const usage =
        \\Proxmox LXC Runtime Interface (proxmox-lxcri)
        \\
        \\Usage: proxmox-lxcri [OPTIONS] COMMAND [ARGS]...
        \\
        \\COMMANDS:
        \\  create <container_id>    Create a new container
        \\  start <container_id>     Start a container
        \\  stop <container_id>      Stop a container
        \\  delete <container_id>    Delete a container
        \\  list                     List all containers
        \\  info <container_id>      Show container information
        \\  state <container_id>     Get container state
        \\  kill <container_id>      Kill a container
        \\  pause <container_id>     Pause a running container
        \\  resume <container_id>    Resume a paused container
        \\  exec <container_id>      Execute new process inside the container
        \\  ps <container_id>        Display processes running inside a container
        \\  events <container_id>    Display container events and statistics
        \\  spec                     Create a new specification file
        \\  checkpoint <container_id> Create a checkpoint of a running container
        \\  restore <container_id>   Restore a container from a checkpoint
        \\  update <container_id>    Update container resource constraints
        \\  features                 Show the enabled features
        \\  generate-config          Generate OCI config for a container
        \\
        \\GLOBAL OPTIONS:
        \\  --debug                  Enable debug logging
        \\  --log <path>             Set the log file to write logs to (default: '/dev/stderr')
        \\  --log-format <format>    Set the log format ('text' (default), or 'json') (default: "text")
        \\  --root <path>            Root directory for storage of container state (default: "/run/proxmox-lxcri")
        \\  --systemd-cgroup         Enable systemd cgroup support
        \\  --config <path>          Path to configuration file
        \\  --bundle, -b <path>      Path to OCI bundle
        \\  --pid-file <path>        Path to pid file
        \\  --console-socket <path>  Path to console socket
        \\  --help, -h               Show this help message
        \\  --version, -v            Print the version
        \\
        \\Examples:
        \\  proxmox-lxcri --config /path/to/config.json create my-container
        \\  proxmox-lxcri --config /path/to/config.json start my-container
        \\  proxmox-lxcri list
        \\
        \\Configuration files are loaded in this order:
        \\  1. File specified with --config
        \\  2. ./config.json (current directory)
        \\  3. /etc/proxmox-lxcri/config.json
        \\  4. /etc/proxmox-lxcri/proxmox-lxcri.json
        \\
    ;
    std.io.getStdOut().writer().print(usage, .{}) catch {};
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
            try printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
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
                try printUsage();
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
        try printUsage();
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
        "./config.json",                           // Поточна директорія
        "/etc/proxmox-lxcri/config.json",         // Системний конфіг
        "/etc/proxmox-lxcri/proxmox-lxcri.json",  // Альтернативний системний конфіг
    };

    for (default_paths) |path| {
        const result = loadConfigFromPath(allocator, path) catch |err| {
            // Логуємо помилку, але продовжуємо перевіряти наступні файли
            logger_mod.warn("Failed to load config from '{s}': {s}", .{path, @errorName(err)}) catch {};
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
        try logger_mod.err("Failed to open config file '{s}': {s}", .{path, @errorName(err)});
        return error.ConfigError;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        try logger_mod.err("Failed to read config file: {s}", .{@errorName(err)});
        return error.ConfigError;
    };
    defer allocator.free(content);

    var parsed = try json_parser.parseWithUnknownFields(config.JsonConfig, allocator, content);
    defer {
        config.deinitJsonConfig(&parsed.value, allocator);
        for (parsed.unknown_fields) |field| {
            allocator.free(field);
        }
        allocator.free(parsed.unknown_fields);
    }

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
    _lxc_manager: ?*void,
) !void {
    _ = _lxc_manager;
    if (args.len < 4) {
        try std.io.getStdErr().writer().writeAll("Error: create requires --bundle and container-id arguments\n");
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

    // Create bundle directory if it does not exist
    var bundle_dir = try std.fs.cwd().openDir(bundle_path.?, .{});
    defer bundle_dir.close();

    // Create OCI config file
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_path.?, "config.json" });
    defer allocator.free(config_path);

    bundle_dir.access("config.json", .{}) catch |err| {
        try logger_mod.err("Failed to access config.json in bundle: {s}", .{@errorName(err)});
        return error.InvalidBundle;
    };

    // Create temporary logger for config initialization
    var temp_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer temp_logger.deinit();

    // Initialize configuration
    var cfg = try loadConfig(allocator, null);
    defer cfg.deinit();

    // Set runtime type (default runc)
    cfg.setRuntimeType(.runc);

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

    // var container_instance = try container_mod.Container.init(allocator, &cfg, &container_spec, "test-container");
    // defer container_instance.deinit();

    // Create container
    const create = try oci.create.Create.init(
        allocator,
        image_manager,
        zfs_manager,
        null,
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

fn executeStop(container_id: []const u8, logger_ctx: *types.LogContext) !void {
    const id = container_id;
    try logger_ctx.info("Stopping container: {s}", .{id});
    
    // Отримуємо список контейнерів щоб знайти VMID за іменем
    const containers = try proxmox_client.listLXCs();
    defer {
        for (containers) |*container| {
            container.deinit(proxmox_client.allocator);
        }
        proxmox_client.allocator.free(containers);
    }

    // Шукаємо контейнер за іменем
    var vmid: ?u32 = null;
    for (containers) |container| {
        if (std.mem.eql(u8, container.name, id)) {
            vmid = container.vmid;
            break;
        }
    }

    if (vmid == null) {
        try logger_ctx.err("Container with name {s} not found", .{id});
        return error.ContainerNotFound;
    }

    // Отримуємо поточний статус контейнера
    const status = try proxmox_client.getContainerStatus(.lxc, vmid.?);
    
    if (status == .stopped) {
        try logger_ctx.info("Container {s} is already stopped", .{id});
        return;
    }

    // Зупиняємо контейнер
    try proxmox_client.stopContainer(.lxc, vmid.?, null);
    try logger_ctx.info("Container {s} stopped successfully", .{id});
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
            .args = &[_][]const u8{ "/bin/sh" },
            .env = &[_][]const u8{ "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" },
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Створюємо тимчасовий логер для ініціалізації конфігурації
    var temp_logger = try logger_mod.Logger.init(allocator, std.io.getStdErr().writer(), .info, "main");
    defer temp_logger.deinit();

    // Додаю dispatch для команд
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len <= 1) {
        printUsage();
        return;
    }
    
    // Обробляємо глобальні опції
    var config_path: ?[]const u8 = null;
    var i: usize = 1;
    
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 >= args.len) {
                std.io.getStdErr().writer().print("Error: --config requires a path argument\n", .{}) catch {};
                return error.InvalidArguments;
            }
            config_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return;
        } else {
            // Це команда, виходимо з циклу
            break;
        }
    }
    
    if (i >= args.len) {
        printUsage();
        return;
    }

    // Ініціалізуємо конфігурацію
    var cfg: config.Config = undefined;
    if (config_path) |path| {
        cfg = try loadConfig(allocator, path);
    } else {
        cfg = try loadConfig(allocator, null); // Завантажуємо з файлів за замовчуванням
    }
    defer cfg.deinit();

    // Ініціалізуємо ProxmoxClient
    const default_host = "localhost";
    const host = if (cfg.proxmox.hosts) |hosts| hosts[0] else default_host;
    var proxmox_client_instance = try ProxmoxClient.init(
        allocator,
        host,
        cfg.proxmox.port orelse 8006,
        cfg.proxmox.token orelse "default-token",
        cfg.proxmox.node orelse "pve",
        &temp_logger,
    );
    defer proxmox_client_instance.deinit();
    
    // Присвоюємо глобальну змінну
    proxmox_client = &proxmox_client_instance;

    // Встановлюємо тип runtime (за замовчуванням runc)
    cfg.setRuntimeType(.runc);

    // Обробляємо команди
    if (std.mem.eql(u8, args[i], "create")) {
        const container_id = if (args.len > i + 1) args[i + 1] else "unknown";
        // Додаю тег container_id
        const tag = std.fmt.allocPrint(allocator, "container_id={s}", .{container_id}) catch "container_id=unknown";
        defer allocator.free(tag);
        temp_logger.setTags(&[_][]const u8{tag});
        executeCreate(allocator, args, undefined, undefined, null) catch |err| {
            temp_logger.err("Create command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "list")) {
        executeList(allocator, &temp_logger) catch |err| {
            temp_logger.err("List command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "start")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for start command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        executeStart(container_id) catch |err| {
            temp_logger.err("Start command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "stop")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for stop command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        executeStop(container_id, &temp_logger) catch |err| {
            temp_logger.err("Stop command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "delete")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for delete command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        executeDelete(container_id) catch |err| {
            temp_logger.err("Delete command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "info")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for info command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        executeInfo(allocator, container_id, &temp_logger) catch |err| {
            temp_logger.err("Info command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "state")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for state command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        executeState(allocator, container_id) catch |err| {
            temp_logger.err("State command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "kill")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for kill command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        const signal = if (args.len > i + 2) args[i + 2] else null;
        executeKill(container_id, signal) catch |err| {
            temp_logger.err("Kill command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
    }
    
    if (std.mem.eql(u8, args[i], "pause")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for pause command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Pausing container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "resume")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for resume command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Resuming container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "exec")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for exec command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Executing command in container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "ps")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for ps command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Listing processes in container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "events")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for events command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Showing events for container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "spec")) {
        temp_logger.info("Creating new specification file (not implemented yet)", .{}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "checkpoint")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for checkpoint command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Creating checkpoint for container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "restore")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for restore command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Restoring container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "update")) {
        const container_id = if (args.len > i + 1) args[i + 1] else {
            std.io.getStdErr().writer().print("Error: container_id required for update command\n", .{}) catch {};
            return error.MissingContainerId;
        };
        temp_logger.info("Updating container: {s} (not implemented yet)", .{container_id}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "features")) {
        temp_logger.info("Showing enabled features (not implemented yet)", .{}) catch {};
        return;
    }
    
    if (std.mem.eql(u8, args[i], "generate-config")) {
        executeGenerateConfig(allocator, args) catch |err| {
            temp_logger.err("Generate-config command failed: {s}", .{@errorName(err)}) catch {};
            return err;
        };
        return;
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

fn printVersion() void {
    const version = "proxmox-lxcri version 0.1.1\n";
    std.io.getStdOut().writer().print(version, .{}) catch {};
}

// Additional command execution functions
fn executeList(allocator: Allocator, logger: *logger_mod.Logger) !void {
    _ = allocator;
    _ = logger;
    try oci.list.list(proxmox_client);
}

fn executeInfo(allocator: Allocator, container_id: []const u8, logger: *logger_mod.Logger) !void {
    _ = allocator;
    _ = logger;
    try oci.info.info(container_id, proxmox_client);
}


