const std = @import("std");
const core = @import("core");
const cli = @import("cli");
const backends = @import("backends");
const utils = @import("utils");

/// Main entry point for the modular architecture
/// Application context
pub const AppContext = struct {
    allocator: std.mem.Allocator,
    config: core.Config,
    logger: core.LogContext,
    advanced_logger: ?core.simple_advanced_logging.SimpleAdvancedLogging = null,
    logging_config: core.logging_config.LoggingConfig,
    command_registry: cli.CommandRegistry,

    /// Initializes the context in place.
    ///
    /// Every command keeps a pointer to `self.logger`, so the logger has to
    /// live at its final address before commands are registered. This used to
    /// build the logger as a local, register `&logger`, and return the context
    /// by value — leaving each command pointing into a dead stack frame. That
    /// is the "logger allocator" segfault the CLI worked around by not logging.
    pub fn init(self: *AppContext, allocator: std.mem.Allocator, args: []const []const u8) !void {
        var config_loader = core.ConfigLoader.init(allocator);
        var config = try config_loader.loadDefault();
        errdefer config.deinit();

        // Priority: command line args > environment > config file > defaults
        var logging_cfg = try core.logging_config.LoggingConfig.loadWithPriority(allocator, args, &config);
        errdefer logging_cfg.deinit(allocator);

        var advanced_logger: ?core.simple_advanced_logging.SimpleAdvancedLogging = null;
        if (logging_cfg.debug_mode or logging_cfg.enable_file_logging) {
            // Open a file only when one was asked for. log_file_path always
            // holds a default (/tmp/nexcage-<timestamp>.log), and --debug on
            // its own used to create a new one on every run.
            const log_path = if (logging_cfg.enable_file_logging) logging_cfg.log_file_path else null;
            advanced_logger = core.simple_advanced_logging.SimpleAdvancedLogging.init(allocator, logging_cfg.debug_mode, log_path) catch |err| blk: {
                // A log file that cannot be opened must not stop the command.
                // A config or NEXCAGE_LOG_FILE pointing into a missing or
                // unwritable directory made every invocation, --help included,
                // fail with "nexcage: FileNotFound".
                printError("warning: cannot open log file '{s}' ({s}); logging to stderr only", .{ log_path orelse "", @errorName(err) });
                break :blk if (logging_cfg.debug_mode)
                    core.simple_advanced_logging.SimpleAdvancedLogging.init(allocator, true, null) catch null
                else
                    null;
            };
        }
        errdefer if (advanced_logger) |*logger| logger.deinit();

        self.* = AppContext{
            .allocator = allocator,
            .config = config,
            // logging_cfg.log_level already folds in config file, env and --debug/--log-level
            .logger = core.LogContext.init(allocator, std.fs.File.stderr(), logging_cfg.log_level, "nexcage"),
            .advanced_logger = advanced_logger,
            .logging_config = logging_cfg,
            .command_registry = cli.CommandRegistry.init(allocator),
        };
        errdefer self.command_registry.deinit();

        try cli.registerBuiltinCommandsWithLogger(&self.command_registry, &self.logger);
    }

    pub fn deinit(self: *AppContext) void {
        // Cleanup advanced logger
        if (self.advanced_logger) |*logger| {
            logger.deinit();
        }

        // Cleanup logging configuration
        self.logging_config.deinit(self.allocator);

        // Cleanup main configuration
        self.config.deinit();

        self.command_registry.deinit();
        self.logger.deinit();
        // config.deinit() already called above
    }

    // Backend routing is now handled by BackendRouter in core/router.zig
    // Network, storage, and image providers are integrated via backends
    // Legacy provider initialization methods removed - functionality moved to modular backend system
};

/// Set once a failure has been reported to the user, so main() does not add a
/// second, less specific line for the same error.
var failure_reported = false;

/// Exit status: 0 on success, 1 when an operation failed, 2 for usage errors.
/// Returning the error from main instead would print Zig's error return trace,
/// which tells a user nothing about their container.
pub fn main() u8 {
    run() catch |err| {
        if (!failure_reported) printError("{s}", .{describeError(err)});
        return exitCodeFor(err);
    };
    // `exec` exits with the status of the command it ran, the way an OCI
    // runtime does; every other command leaves this null.
    return core.exit_status.propagated orelse 0;
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // --config, before or after the command, has to be known before anything
    // loads the configuration. It used to be parsed and never read.
    if (try configPathFromArgs(args)) |path| {
        std.fs.cwd().access(path, .{}) catch |err| {
            printError("cannot read config file '{s}': {s}", .{ path, @errorName(err) });
            failure_reported = true;
            return error.InvalidConfig;
        };
        core.config.setExplicitPath(path);
    }

    // --root, likewise: every command that reads or writes per-container state
    // has to see it before it does so.
    if (try flagValueFromArgs(args, "--root", "path")) |root| {
        if (root.len == 0 or root[0] != '/') {
            printError("--root needs an absolute path, got '{s}'", .{root});
            failure_reported = true;
            return error.InvalidInput;
        }
        core.state_root.set(root);
    }

    // Initialize application context in place: commands hold &app.logger
    var app: AppContext = undefined;
    try app.init(allocator, args);
    defer app.deinit();

    // Log application startup
    if (app.advanced_logger) |*logger| {
        try logger.info("Starting nexcage v{s}", .{core.version.getVersion()});
        try logger.logSystemInfo();
    }

    if (args.len < 2) {
        try printUsage();
        return;
    }

    // Find the actual command (skip flags)
    var command_name = args[1];
    var command_args = args[2..];

    // Skip debug/verbose flags to find the actual command
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--debug") or std.mem.eql(u8, args[i], "--verbose")) {
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--log-file") and i + 1 < args.len) {
            i += 2; // Skip --log-file and its value
            continue;
        }
        if (std.mem.eql(u8, args[i], "--log-level") and i + 1 < args.len) {
            i += 2; // Skip --log-level and its value
            continue;
        }
        if (std.mem.eql(u8, args[i], "--config") and i + 1 < args.len) {
            i += 2; // Skip --config and its value, applied above
            continue;
        }
        if (std.mem.eql(u8, args[i], "--root") and i + 1 < args.len) {
            i += 2; // Skip --root and its value, applied above
            continue;
        }
        if (std.mem.eql(u8, args[i], "--runtime") and i + 1 < args.len) {
            i += 2; // Skip --runtime and its value; parseRuntimeOptions reads it
            continue;
        }
        // Found the actual command
        command_name = args[i];
        command_args = args[i + 1 ..];
        break;
    }

    // Log command execution start - safely handle logger errors
    if (app.advanced_logger) |*logger| {
        logger.logCommandStart(command_name, command_args) catch {};
    }

    // Handle help command
    if (std.mem.eql(u8, command_name, "--help") or std.mem.eql(u8, command_name, "-h")) {
        try printUsage();
        return;
    }

    // Parse runtime options
    var options = try parseRuntimeOptions(allocator, command_name, command_args);
    defer options.deinit();

    // A --runtime before the command never reached the parser: the loop above
    // skips it to find the command, and command_args starts after the command,
    // so the flag was dropped and the routing silently stayed on the default.
    // After the defer, so an unknown value does not leak what is already
    // parsed on its way out.
    if (options.runtime_type == null) {
        if (try flagValueFromArgs(args, "--runtime", "value")) |value| {
            options.runtime_type = parseRuntimeType(value) orelse {
                printError("unknown runtime '{s}'; expected lxc, crun, runc or vm", .{value});
                failure_reported = true;
                return error.InvalidInput;
            };
        }
    }

    // Check if help was requested
    if (options.help) {
        // Execute command (which will handle help)
        try executeCommand(&app, command_name, options, allocator);

        // Log command completion - safely handle logger errors
        if (app.advanced_logger) |*logger| {
            logger.logCommandComplete(command_name, true) catch {};
        }
        return;
    }

    // Execute command
    try executeCommand(&app, command_name, options, allocator);

    // Log command completion - safely handle logger errors
    if (app.advanced_logger) |*logger| {
        logger.logCommandComplete(command_name, true) catch {};
    }
}

/// Runs a command and reports a failure as one line on stderr. The detail —
/// which pct call failed and what it printed — was already logged by the layer
/// that saw it; this line names the command and the outcome.
fn executeCommand(app: *AppContext, command_name: []const u8, options: core.RuntimeOptions, allocator: std.mem.Allocator) !void {
    app.command_registry.execute(command_name, options, allocator) catch |err| {
        const any_err: anyerror = err;
        switch (any_err) {
            error.CommandNotFound => printError("unknown command '{s}'; run 'nexcage --help' for the list of commands", .{command_name}),
            error.InvalidInput => printError("{s}: invalid arguments; run 'nexcage {s} --help'", .{ command_name, command_name }),
            else => printError("{s}: {s}", .{ command_name, describeError(any_err) }),
        }
        failure_reported = true;
        return err;
    };
}

fn describeError(err: anyerror) []const u8 {
    return switch (err) {
        error.NotFound => "not found",
        error.PermissionDenied => "permission denied; nexcage needs root on the Proxmox host",
        error.UnsupportedOperation => "not supported on this host or by this build",
        error.Timeout => "timed out",
        error.InvalidInput, error.ValidationError => "invalid input",
        error.InvalidConfig => "invalid configuration file",
        error.OperationFailed => "operation failed",
        error.OutOfMemory => "out of memory",
        else => @errorName(err),
    };
}

fn exitCodeFor(err: anyerror) u8 {
    return switch (err) {
        error.CommandNotFound, error.InvalidInput, error.ValidationError => 2,
        else => 1,
    };
}

fn printError(comptime format: []const u8, args: anytype) void {
    var buffer: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writerStreaming(&buffer);
    const out = &stderr_writer.interface;
    out.print("nexcage: " ++ format ++ "\n", args) catch return;
    out.flush() catch return;
}

/// Top-level usage. This is command output, not a log message: it goes to
/// stdout without timestamps and regardless of the configured log level.
fn printUsage() !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writerStreaming(&buffer);
    const out = &stdout_writer.interface;
    try out.print(
        \\nexcage v{s} - container runtime for Proxmox VE (LXC)
        \\
        \\Usage: nexcage [--debug] [--log-level <level>] [--log-file <path>] [--config <path>] [--root <dir>] <command> [options]
        \\
        \\Commands:
        \\  create    Create a new container
        \\  start     Start a container
        \\  stop      Stop a container
        \\  delete    Delete a container
        \\  list      List containers
        \\  state     Show container state as OCI JSON
        \\  kill      Send a signal to a container
        \\  exec      Run a command inside a running container
        \\  run       Create and start a container
        \\  help      Show this help message
        \\  version   Show version information
        \\
        \\Use 'nexcage <command> --help' for command-specific help.
        \\
    , .{core.version.getVersion()});
    try out.flush();
}

/// Parse runtime options from command line arguments
fn parseRuntimeOptions(allocator: std.mem.Allocator, command_name: []const u8, args: []const []const u8) !core.RuntimeOptions {
    var options = core.RuntimeOptions{
        .allocator = allocator,
        .command = parseCommand(command_name),
        .container_id = null,
        .image = null,
        // Set only by an explicit --runtime; without one the routing rules in
        // the config file choose. The config's runtime_type used to be copied
        // here, and neither it nor --runtime was ever read.
        .runtime_type = null,
        .config_file = null,
        .verbose = false,
        .debug = false,
        .detach = false,
        .force = false,
        .all = false,
        .interactive = false,
        .tty = false,
        .user = null,
        .workdir = null,
        .env = null,
        .args = null,
    };
    errdefer options.deinit();

    // The runtime-spec form is `create <id> --bundle <dir>`, so --bundle
    // decides what the first positional word is: the container id, not the
    // image. Known before the loop because --bundle may come after it.
    var bundle_given = false;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--bundle")) bundle_given = true;
    }

    // Parse arguments
    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.help = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--name") and i + 1 < args.len) {
            options.container_id = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--bundle") and i + 1 < args.len) {
            // An OCI bundle directory: config.json plus rootfs/. The backend
            // takes it where the image goes.
            if (options.image == null) options.image = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--runtime") and i + 1 < args.len) {
            const runtime_str = args[i + 1];
            options.runtime_type = parseRuntimeType(runtime_str) orelse {
                printError("unknown runtime '{s}'; expected lxc, crun, runc or vm", .{runtime_str});
                failure_reported = true;
                return error.InvalidInput;
            };
            i += 2;
        } else if ((std.mem.eql(u8, arg, "--log-level") or std.mem.eql(u8, arg, "--log-file")) and i + 1 < args.len) {
            // Global options, which LoggingConfig reads wherever they appear.
            // After the command name they used to reach the generic "-..."
            // branch below, which skipped only the flag, so its value became
            // the container name: "start --log-level debug web" started "debug".
            i += 2;
        } else if (std.mem.eql(u8, arg, "--config") and i + 1 < args.len) {
            // Applied in run() before the configuration was loaded; skipped
            // here so its value is not taken as a name or an image
            i += 2;
        } else if (std.mem.eql(u8, arg, "--root") and i + 1 < args.len) {
            // Where per-container state goes. An OCI runtime takes this from
            // the caller: containerd gives each namespace its own directory.
            // Applied in run() before any command sees it; skipped here so
            // its value is not taken as a name or an image.
            i += 2;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            options.debug = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            options.force = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--all") or std.mem.eql(u8, arg, "-a")) {
            options.all = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--detach")) {
            options.detach = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--interactive")) {
            options.interactive = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--tty")) {
            options.tty = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--user") and i + 1 < args.len) {
            options.user = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--workdir") and i + 1 < args.len) {
            options.workdir = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if ((std.mem.eql(u8, arg, "--signal") or std.mem.eql(u8, arg, "-s")) and i + 1 < args.len) {
            // kill reads the signal from options.args. This flag used to fall
            // into the generic "-..." branch below, which dropped it and left
            // its value to be taken as the container name.
            if (options.args == null) options.args = args[i .. i + 2];
            i += 2;
        } else if (std.mem.eql(u8, arg, "--") and options.command == .exec and options.container_id != null) {
            // For exec, everything after "--" is the command to run, even
            // where it starts with a dash. Without this the generic branch
            // below drops such a token and exec sees no command at all.
            if (i + 1 < args.len) options.args = args[i + 1 ..];
            break;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // This is likely the image name, container ID, or command
            const id_first = options.command == .start or options.command == .stop or
                options.command == .delete or options.command == .state or
                options.command == .kill or options.command == .exec or
                (bundle_given and (options.command == .create or options.command == .run));
            if (id_first) {
                // For start/stop/delete/state/kill/exec, first argument is
                // the container ID; for exec the rest is the command to run
                if (options.container_id == null) {
                    options.container_id = try allocator.dupe(u8, arg);
                } else {
                    // This is a command argument
                    if (options.args == null) {
                        options.args = args[i..];
                    }
                    break;
                }
            } else if (options.image == null) {
                options.image = try allocator.dupe(u8, arg);
            } else {
                // This is a command argument
                if (options.args == null) {
                    options.args = args[i..];
                }
                break;
            }
            i += 1;
        } else {
            i += 1;
        }
    }

    return options;
}

/// The value of --config anywhere on the command line, or null. A --config
/// with nothing after it is a usage error.
fn configPathFromArgs(args: []const []const u8) !?[]const u8 {
    return flagValueFromArgs(args, "--config", "path");
}

/// The value of a global flag wherever it appears, or null. The flag with
/// nothing after it is a usage error: taking the next command-line word would
/// silently use a container name as the value. `noun` names what is
/// expected, so each flag keeps its own message.
fn flagValueFromArgs(args: []const []const u8, flag: []const u8, noun: []const u8) !?[]const u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (!std.mem.eql(u8, args[i], flag)) continue;
        if (i + 1 >= args.len) {
            printError("{s} needs a {s}", .{ flag, noun });
            failure_reported = true;
            return error.InvalidInput;
        }
        return args[i + 1];
    }
    return null;
}

/// Parse command from string
fn parseCommand(command_str: []const u8) core.Command {
    if (std.mem.eql(u8, command_str, "create")) return .create;
    if (std.mem.eql(u8, command_str, "start")) return .start;
    if (std.mem.eql(u8, command_str, "stop")) return .stop;
    if (std.mem.eql(u8, command_str, "delete")) return .delete;
    if (std.mem.eql(u8, command_str, "list")) return .list;
    if (std.mem.eql(u8, command_str, "info")) return .info;
    if (std.mem.eql(u8, command_str, "exec")) return .exec;
    if (std.mem.eql(u8, command_str, "run")) return .run;
    if (std.mem.eql(u8, command_str, "help")) return .help;
    if (std.mem.eql(u8, command_str, "version")) return .version;
    if (std.mem.eql(u8, command_str, "state")) return .state;
    if (std.mem.eql(u8, command_str, "kill")) return .kill;
    return .help; // Default to help
}

/// Parse a --runtime value; null for one nexcage does not know
fn parseRuntimeType(runtime_str: []const u8) ?core.RuntimeType {
    if (std.mem.eql(u8, runtime_str, "lxc") or std.mem.eql(u8, runtime_str, "proxmox-lxc")) return .lxc;
    // The router sends only .vm to the VM backend; .qemu went to LXC
    if (std.mem.eql(u8, runtime_str, "vm") or std.mem.eql(u8, runtime_str, "qemu")) return .vm;
    if (std.mem.eql(u8, runtime_str, "crun")) return .crun;
    // "runc" used to select crun
    if (std.mem.eql(u8, runtime_str, "runc")) return .runc;
    return null;
}
