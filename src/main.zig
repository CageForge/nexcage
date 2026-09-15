const std = @import("std");
const core = @import("core");
const cli = @import("cli");
const backends = @import("backends");
const integrations = @import("integrations");
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
            advanced_logger = try core.simple_advanced_logging.SimpleAdvancedLogging.init(allocator, logging_cfg.debug_mode, logging_cfg.log_file_path);
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
    return 0;
}

fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
    var options = try parseRuntimeOptions(allocator, command_name, command_args, &app.config);
    defer options.deinit();

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
        \\Usage: nexcage [--debug] [--log-level <level>] [--log-file <path>] <command> [options]
        \\
        \\Commands:
        \\  create    Create a new container
        \\  start     Start a container
        \\  stop      Stop a container
        \\  delete    Delete a container
        \\  list      List containers
        \\  state     Show container state as OCI JSON
        \\  kill      Send a signal to a container
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
fn parseRuntimeOptions(allocator: std.mem.Allocator, command_name: []const u8, args: []const []const u8, config: *core.Config) !core.RuntimeOptions {
    var options = core.RuntimeOptions{
        .allocator = allocator,
        .command = parseCommand(command_name),
        .container_id = null,
        .image = null,
        .runtime_type = config.runtime_type,
        .config_file = null,
        .verbose = false,
        .debug = false,
        .detach = false,
        .interactive = false,
        .tty = false,
        .user = null,
        .workdir = null,
        .env = null,
        .args = null,
    };

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
        } else if (std.mem.eql(u8, arg, "--runtime") and i + 1 < args.len) {
            const runtime_str = args[i + 1];
            options.runtime_type = parseRuntimeType(runtime_str);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--config") and i + 1 < args.len) {
            options.config_file = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            options.verbose = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            options.debug = true;
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
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            // This is likely the image name, container ID, or command
            if (options.command == .start or options.command == .stop or options.command == .delete or options.command == .state or options.command == .kill) {
                // For start/stop/delete/state, first argument is container ID
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

/// Parse runtime type from string
fn parseRuntimeType(runtime_str: []const u8) core.RuntimeType {
    if (std.mem.eql(u8, runtime_str, "lxc") or std.mem.eql(u8, runtime_str, "proxmox-lxc")) return .lxc;
    if (std.mem.eql(u8, runtime_str, "qemu") or std.mem.eql(u8, runtime_str, "vm")) return .qemu;
    if (std.mem.eql(u8, runtime_str, "crun") or std.mem.eql(u8, runtime_str, "runc")) return .crun;
    return .lxc; // Default to LXC
}
