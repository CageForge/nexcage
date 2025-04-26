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

const SIGINT = posix.SIG.INT;
const SIGTERM = posix.SIG.TERM;
const SIGHUP = posix.SIG.HUP;

var shutdown_requested: bool = false;
var last_signal: ?c_int = null;
var logger_instance: logger_mod.Logger = undefined;
var proxmox_client: *ProxmoxClient = undefined;

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

fn printHelp() !void {
    const help_text =
        \\proxmox-lxcri - Proxmox LXC OCI Runtime Interface
        \\
        \\Usage:
        \\  proxmox-lxcri <command> [command options] <container-id>
        \\
        \\Commands:
        \\  create     Create a container
        \\  start      Start a container
        \\  state      Query the state of a container
        \\  kill       Signal a container
        \\  delete     Delete a container
        \\
        \\Options:
        \\  --bundle value, -b value     Path to the root of the bundle directory
        \\  --pid-file value            File to write the process id to
        \\  --console-socket value      Path to an AF_UNIX socket to send the console FD
        \\  --debug                     Enable debug logging
        \\  --help, -h                  Show help
        \\
        \\Example:
        \\  proxmox-lxcri create --bundle /path/to/bundle container-id
        \\  proxmox-lxcri start container-id
        \\  proxmox-lxcri state container-id
        \\
    ;
    try std.io.getStdOut().writeAll(help_text);
}

fn loadConfig(allocator: Allocator, config_path: []const u8) !config.Config {
    const config_content = fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024) catch |err| {
        try logger_instance.err("Failed to read config file: {s}", .{@errorName(err)});
        return ConfigError.FailedToParseConfig;
    };
    defer allocator.free(config_content);

    var scanner = std.json.Scanner.initCompleteInput(allocator, config_content);
    defer scanner.deinit();

    var token = try scanner.next();
    if (token != .object_begin) return ConfigError.InvalidConfigFormat;

    var hosts: ?[]const []const u8 = null;
    var token_str: ?[]const u8 = null;
    var port: ?u16 = null;
    var node: ?[]const u8 = null;
    var node_cache_duration: ?u64 = null;

    while (true) {
        token = try scanner.next();
        if (token == .object_end) break;
        if (token != .string) return ConfigError.InvalidConfigFormat;

        const key = token.string;
        if (std.mem.eql(u8, key, "proxmox")) {
            token = try scanner.next();
            if (token != .object_begin) return ConfigError.InvalidConfigFormat;

            while (true) {
                token = try scanner.next();
                if (token == .object_end) break;
                if (token != .string) return ConfigError.InvalidConfigFormat;

                const proxmox_key = token.string;
                token = try scanner.next();

                if (std.mem.eql(u8, proxmox_key, "hosts")) {
                    if (token != .array_begin) return ConfigError.InvalidConfigFormat;
                    var hosts_list = std.ArrayList([]const u8).init(allocator);
                    
                    while (true) {
                        token = try scanner.next();
                        if (token == .array_end) break;
                        if (token != .string) return ConfigError.InvalidConfigFormat;
                        try hosts_list.append(try allocator.dupe(u8, token.string));
                    }
                    
                    hosts = try hosts_list.toOwnedSlice();
                } else if (std.mem.eql(u8, proxmox_key, "token")) {
                    if (token != .string) return ConfigError.InvalidConfigFormat;
                    token_str = try allocator.dupe(u8, token.string);
                } else if (std.mem.eql(u8, proxmox_key, "port")) {
                    if (token != .number) return ConfigError.InvalidConfigFormat;
                    port = @intCast(try std.fmt.parseInt(i64, token.number, 10));
                } else if (std.mem.eql(u8, proxmox_key, "node")) {
                    if (token != .string) return ConfigError.InvalidConfigFormat;
                    node = try allocator.dupe(u8, token.string);
                } else if (std.mem.eql(u8, proxmox_key, "node_cache_duration")) {
                    if (token != .number) return ConfigError.InvalidConfigFormat;
                    node_cache_duration = @intCast(try std.fmt.parseInt(i64, token.number, 10));
                } else {
                    try skipValue(&scanner);
                }
            }
        } else {
            try skipValue(&scanner);
        }
    }

    if (hosts == null or token_str == null or port == null or node == null or node_cache_duration == null) {
        try logger_instance.err("Missing required configuration fields", .{});
        return ConfigError.InvalidConfigFormat;
    }

    return config.Config{
        .allocator = allocator,
        .hosts = hosts.?,
        .token = token_str.?,
        .port = port.?,
        .node = node.?,
        .node_cache_duration = node_cache_duration.?,
        .timeout = 30_000,
        .logger = &logger_instance,
    };
}

fn skipValue(scanner: *std.json.Scanner) !void {
    var token = try scanner.next();
    switch (token) {
        .object_begin => {
            var depth: u32 = 1;
            while (depth > 0) {
                token = try scanner.next();
                switch (token) {
                    .object_begin => depth += 1,
                    .object_end => depth -= 1,
                    else => {},
                }
            }
        },
        .array_begin => {
            var depth: u32 = 1;
            while (depth > 0) {
                token = try scanner.next();
                switch (token) {
                    .array_begin => depth += 1,
                    .array_end => depth -= 1,
                    else => {},
                }
            }
        },
        else => {},
    }
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

fn executeCreate(allocator: Allocator, args: []const []const u8) !void {
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

    try oci_commands.create.create(allocator, .{
        .bundle_path = bundle_path.?,
        .id = container_id.?,
        .pid_file = pid_file,
        .allocator = allocator,
        .config_path = try std.fs.path.join(allocator, &[_][]const u8{ bundle_path.?, "config.json" }),
    }, proxmox_client);
}

fn executeStart(container_id: []const u8) !void {
    try oci_commands.start.start(container_id, proxmox_client);
}

fn executeState(allocator: Allocator, container_id: []const u8) !void {
    const container_state = try oci_commands.state.getState(
        proxmox_client,
        container_id,
    );
    var container_state_mut = container_state;
    defer container_state_mut.deinit(allocator);

    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();

    // Format container state as JSON
    try string.writer().writeAll("{\n");
    try string.writer().print("  \"ociVersion\": \"{s}\",\n", .{container_state.ociVersion});
    try string.writer().print("  \"id\": \"{s}\",\n", .{container_state.id});
    try string.writer().print("  \"status\": \"{s}\",\n", .{container_state.status});
    try string.writer().print("  \"pid\": {d},\n", .{container_state.pid});
    try string.writer().print("  \"bundle\": \"{s}\"", .{container_state.bundle});
    
    if (container_state.annotations) |annotations| {
        try string.writer().writeAll(",\n  \"annotations\": {\n");
        for (annotations, 0..) |annotation, i| {
            try string.writer().print("    \"{s}\": \"{s}\"", .{annotation.key, annotation.value});
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
    try oci_commands.delete.delete(container_id, proxmox_client);
}

pub fn main() !void {
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

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) {
        try printHelp();
        return;
    }

    var debug_mode = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--debug")) {
            debug_mode = true;
            break;
        }
    }

    // Initialize logger
    logger_instance = try initLogger(allocator, debug_mode);
    defer logger_instance.deinit();

    // Читаємо конфігурацію
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Load configuration
    var cfg = try config.Config.init(allocator, &logger_instance);
    defer cfg.deinit();
    try cfg.loadFromFile(config_path);

    // Initialize Proxmox client
    var client = try ProxmoxClient.init(
        allocator,
        cfg.proxmox.hosts[0],
        cfg.proxmox.port,
        cfg.proxmox.token,
        cfg.proxmox.node,
        &logger_instance,
    );
    proxmox_client = &client;
    defer proxmox_client.deinit();

    // Parse command
    const command = Command.fromString(args[1]);

    // Execute command
    switch (command) {
        .create => try executeCreate(allocator, args),
        .start => {
            if (args.len < 3) {
                try std.io.getStdErr().writer().writeAll("Error: start requires a container-id argument\n");
                return error.InvalidArguments;
            }
            try executeStart(args[2]);
        },
        .state => {
            if (args.len < 3) {
                try std.io.getStdErr().writer().writeAll("Error: state requires a container-id argument\n");
                return error.InvalidArguments;
            }
            try executeState(allocator, args[2]);
        },
        .kill => {
            var container_id: ?[]const u8 = null;
            var signal: ?[]const u8 = null;
            
            var i: usize = 2;
            while (i < args.len) : (i += 1) {
                const arg = args[i];
                if (std.mem.eql(u8, arg, "--signal")) {
                    i += 1;
                    if (i >= args.len) {
                        try std.io.getStdErr().writer().writeAll("Error: --signal requires a value\n");
                        return error.InvalidArguments;
                    }
                    signal = args[i];
                } else if (container_id == null) {
                    container_id = arg;
                } else {
                    try std.io.getStdErr().writer().print("Error: unexpected argument '{s}'\n", .{arg});
                    return error.InvalidArguments;
                }
            }

            if (container_id == null) {
                try std.io.getStdErr().writer().writeAll("Error: kill requires a container-id argument\n");
                return error.InvalidArguments;
            }

            try executeKill(container_id.?, signal);
        },
        .delete => {
            if (args.len < 3) {
                try std.io.getStdErr().writer().writeAll("Error: delete requires a container-id argument\n");
                return error.InvalidArguments;
            }
            try executeDelete(args[2]);
        },
        .help => try printHelp(),
        .unknown => {
            try std.io.getStdErr().writer().print("Error: unknown command '{s}'\n", .{args[1]});
            try printHelp();
            return error.UnknownCommand;
        },
    }
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
