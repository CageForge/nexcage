const std = @import("std");
const logger_mod = @import("logger");

pub const RuntimeOptions = struct {
    root: ?[]const u8 = null,
    log: ?[]const u8 = null,
    log_format: ?[]const u8 = null,
    systemd_cgroup: bool = false,
    bundle: ?[]const u8 = null,
    pid_file: ?[]const u8 = null,
    console_socket: ?[]const u8 = null,
    debug: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RuntimeOptions {
        return RuntimeOptions{
            .allocator = allocator,
        };
    }
};

pub const Command = enum {
    create,
    start,
    state,
    kill,
    delete,
    help,
    generate_config,
    unknown,
};

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "create")) return .create;
    if (std.mem.eql(u8, command, "start")) return .start;
    if (std.mem.eql(u8, command, "state")) return .state;
    if (std.mem.eql(u8, command, "kill")) return .kill;
    if (std.mem.eql(u8, command, "delete")) return .delete;
    if (std.mem.eql(u8, command, "help")) return .help;
    if (std.mem.eql(u8, command, "generate-config")) return .generate_config;
    return .unknown;
}

pub fn parseArgsFromArray(allocator: std.mem.Allocator, argv: []const []const u8) !struct {
    command: Command,
    options: RuntimeOptions,
    container_id: ?[]const u8,
} {
    var i: usize = 1; // Skip program name
    var command: ?Command = null;
    var options = RuntimeOptions.init(allocator);
    var container_id: ?[]const u8 = null;
    var has_args = false;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        has_args = true;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            // For tests just return error
            return error.HelpRequested;
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
                return error.UnknownCommand;
            }
        } else {
            if (container_id == null) {
                container_id = try allocator.dupe(u8, arg);
            } else {
                return error.UnexpectedArgument;
            }
        }
    }
    if (!has_args or command == null) {
        return error.NoCommand;
    }
    return .{
        .command = command.?,
        .options = options,
        .container_id = container_id,
    };
} 