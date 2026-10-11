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
        var config = config_loader.loadDefault() catch |err| {
            if (config_loader.problem()) |why| {
                printError("invalid configuration file {s}: {s}", .{ core.config.activePath() orelse "", why });
                failure_reported = true;
            }
            return err;
        };
        errdefer config.deinit();

        // Not a warning, as for runc: no backend is left that runs what such
        // a rule describes, and the default one would make a container where
        // a VM was asked for. The file has to say something nexcage can do.
        if (config.removed_vm_runtime) |name| {
            printError("the configuration names '{s}' as a runtime, and the Proxmox VM backend was removed in 0.14.0; nexcage runs containers -- name lxc or crun", .{name});
            failure_reported = true;
            return error.InvalidConfig;
        }

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

        // --log sends the runtime's own log to a file rather than stderr, which
        // is what a container engine expects: containerd opens that file to
        // report why the runtime failed, and finds nothing if it is not
        // written. A file that cannot be opened falls back to stderr rather
        // than failing the command.
        var log_sink = std.fs.File.stderr();
        if (logging_cfg.runtime_log_path) |path| {
            if (core.logging.openAppend(path)) |f| {
                log_sink = f;
            } else |err| {
                printError("warning: cannot open --log file '{s}' ({s}); logging to stderr", .{ path, @errorName(err) });
            }
        }
        var runtime_logger = core.LogContext.init(allocator, log_sink, logging_cfg.log_level, "nexcage");
        runtime_logger.format = logging_cfg.log_format;
        if (log_sink.handle != std.fs.File.stderr().handle) runtime_logger.echo = std.fs.File.stderr();

        if (config.legacy_runc_runtime) {
            runtime_logger.warn("runc is not a backend since 0.13.0; a rule naming it routes to crun, the OCI backend. Change the rule to say crun", .{}) catch {};
        }

        self.* = AppContext{
            .allocator = allocator,
            .config = config,
            // logging_cfg.log_level already folds in config file, env and --debug/--log-level
            .logger = runtime_logger,
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
    const raw_args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, raw_args);

    // A container engine writes a flag either way: containerd sends
    // `--root <dir>`, CRI-O sends `--root=/run/crio/runc`. Every parser below
    // reads the two-word form only, so CRI-O's very first call came back as
    // `unknown command '--root=/run/nexcage-crio'`. One pass here, before
    // anything looks at the vector, and the rest is unchanged.
    var args = try splitEqualsFlags(allocator, raw_args);
    defer allocator.free(args);

    // The command, past the global options in front of it, and the end of
    // nexcage's own words. What follows is the command `exec` runs in the
    // container, which is the container's: every option below was read from
    // it too, so `exec web grep --config x` loaded x as root's configuration,
    // and `--log /x` there had root write its log into /x. It is handed over
    // as it was given, `=` and all.
    const found = findCommand(args);
    const own_end = ownWordsEnd(args, found.index);
    if (own_end < args.len) args = try restoreCommandWords(allocator, raw_args, args, own_end);
    const own = args[0..own_end];

    // --config, before or after the command, has to be known before anything
    // loads the configuration. It used to be parsed and never read.
    if (try configPathFromArgs(own)) |path| {
        std.fs.cwd().access(path, .{}) catch |err| {
            printError("cannot read config file '{s}': {s}", .{ path, @errorName(err) });
            failure_reported = true;
            return error.InvalidConfig;
        };
        core.config.setExplicitPath(path);
    }

    // --root, likewise: every command that reads or writes per-container state
    // has to see it before it does so.
    if (try flagValueFromArgs(own, "--root", "path")) |root| {
        if (root.len == 0 or root[0] != '/') {
            printError("--root needs an absolute path, got '{s}'", .{root});
            failure_reported = true;
            return error.InvalidInput;
        }
        core.state_root.set(root);
    }

    // Initialize application context in place: commands hold &app.logger
    var app: AppContext = undefined;
    try app.init(allocator, own);
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

    var command_name = args[found.index];
    const command_args = args[found.index + 1 ..];

    // Log command execution start - safely handle logger errors
    if (app.advanced_logger) |*logger| {
        logger.logCommandStart(command_name, command_args) catch {};
    }

    // Handle help command
    if (std.mem.eql(u8, command_name, "--help") or std.mem.eql(u8, command_name, "-h")) {
        try printUsage();
        return;
    }

    // CRI-O asks a runtime its version before it will use one, and asks with
    // the flag rather than the subcommand. Mapped onto the same command, so
    // the two spellings cannot print different things.
    if (std.mem.eql(u8, command_name, "--version")) command_name = "version";

    // Parse runtime options: nexcage's own words only. The command exec runs
    // is handed to it whole.
    var options = try parseRuntimeOptions(allocator, command_name, args[found.index + 1 .. own_end]);
    defer options.deinit();
    if (own_end < args.len) {
        const command = if (std.mem.eql(u8, args[own_end], "--")) args[own_end + 1 ..] else args[own_end..];
        if (command.len > 0) options.args = command;
    }

    // A --runtime before the command never reached the parser: findCommand
    // skips it to find the command, and command_args starts after the command,
    // so the flag was dropped and the routing silently stayed on the default.
    // After the defer, so an unknown value does not leak what is already
    // parsed on its way out.
    if (options.runtime_type == null) {
        if (try flagValueFromArgs(own, "--runtime", "value")) |value| {
            options.runtime_type = parseRuntimeType(value) orelse {
                reportUnknownRuntime(value);
                failure_reported = true;
                return error.InvalidInput;
            };
        }
    }

    // An isolation profile (ADR-005): --profile, before or after the command,
    // or the program name, nexcage@<profile>, which is how a container
    // engine's runtime handler names one. Only create reads it.
    if (options.profile == null) options.profile = try flagValueFromArgs(own, "--profile", "profile name");
    if (core.profile.fromProgramName(args[0])) |named| {
        if (named.len == 0) {
            printError("the program name '{s}' ends in '@' with no profile after it", .{args[0]});
            failure_reported = true;
            return error.InvalidInput;
        }
        if (options.profile) |flag| if (!std.mem.eql(u8, flag, named)) {
            printError("--profile {s} and the program name '{s}' name different profiles", .{ flag, args[0] });
            failure_reported = true;
            return error.InvalidInput;
        };
        options.profile = named;
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
        \\  features  Show what this runtime implements, as an OCI features document
        \\  ps        List the host PIDs of the processes in a container
        \\  images    List the container templates the cluster can create from
        \\  pull      Fetch an OCI image into a Proxmox storage as a template
        \\  rmi       Remove a container template from a Proxmox storage
        \\  pause     Freeze every process in a container
        \\  resume    Thaw a frozen container
        \\  update    Change a running container's resource limits
        \\  snapshot  Take a snapshot of a container, through Proxmox
        \\  snapshots List a container's snapshots
        \\  rollback  Roll a container back to a snapshot
        \\  delsnapshot  Delete a snapshot
        \\  run       Create and start a container
        \\  health    Check the host: pct, state and storage, ZFS pools, configuration
        \\  help      Show this help message
        \\  version   Show version information
        \\
        \\Use 'nexcage <command> --help' for command-specific help.
        \\
    , .{core.version.getVersion()});
    try out.flush();
}

/// Where the command is on the command line.
const CommandPosition = struct {
    /// The command's index in argv. On a line of nothing but options it is 1,
    /// so that the first option is the one reported as an unknown command.
    index: usize,
};

/// Steps over the global options to the command. An engine puts its options
/// there, the way runc's command line has them: containerd's shim (go-runc)
/// sends `--root <dir> --log <file> --log-format json --systemd-cgroup create
/// ...`. Each is read where it is used, wherever on the line it appears.
fn findCommand(args: []const []const u8) CommandPosition {
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
            i += 2; // Skip --config and its value, applied in run()
            continue;
        }
        if (std.mem.eql(u8, args[i], "--root") and i + 1 < args.len) {
            i += 2; // Skip --root and its value, applied in run()
            continue;
        }
        if (std.mem.eql(u8, args[i], "--runtime") and i + 1 < args.len) {
            i += 2; // Skip --runtime and its value, read in run()
            continue;
        }
        if (std.mem.eql(u8, args[i], "--profile") and i + 1 < args.len) {
            i += 2; // Skip --profile and its value, read in run()
            continue;
        }
        // What a container engine puts before the command. Without these,
        // `--log` was taken for the command name and containerd got
        // "unknown command '--log'" on its very first call.
        if ((std.mem.eql(u8, args[i], "--log") or std.mem.eql(u8, args[i], "--log-format")) and i + 1 < args.len) {
            i += 2;
            continue;
        }
        if (std.mem.eql(u8, args[i], "--systemd-cgroup")) {
            i += 1;
            continue;
        }
        return .{ .index = i };
    }
    return .{ .index = 1 };
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
        .console_socket = null,
        .pid_file = null,
        .systemd_cgroup = false,
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
        } else if (std.mem.eql(u8, arg, "--console-socket") and i + 1 < args.len) {
            options.console_socket = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--pid-file") and i + 1 < args.len) {
            options.pid_file = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--image") and i + 1 < args.len) {
            // The form 'create --help' shows. It used to work only because an
            // unknown option was skipped and its value taken for the image.
            if (options.image == null) options.image = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--bundle") and i + 1 < args.len) {
            // An OCI bundle directory: config.json plus rootfs/. The backend
            // takes it where the image goes.
            if (options.image == null) options.image = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--runtime") and i + 1 < args.len) {
            const runtime_str = args[i + 1];
            options.runtime_type = parseRuntimeType(runtime_str) orelse {
                reportUnknownRuntime(runtime_str);
                failure_reported = true;
                return error.InvalidInput;
            };
            i += 2;
        } else if (std.mem.eql(u8, arg, "--profile") and i + 1 < args.len) {
            options.profile = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, arg, "--systemd-cgroup")) {
            // cgroup management is libcrun's; accepted so an engine that sends
            // it is not answered with a usage error
            options.systemd_cgroup = true;
            i += 1;
        } else if ((std.mem.eql(u8, arg, "--log-level") or std.mem.eql(u8, arg, "--log-file") or
            std.mem.eql(u8, arg, "--log") or std.mem.eql(u8, arg, "--log-format")) and i + 1 < args.len)
        {
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
        } else if ((std.mem.eql(u8, arg, "--workdir") or std.mem.eql(u8, arg, "--cwd")) and i + 1 < args.len) {
            // --cwd is runc's spelling of the same thing, and `exec` is where
            // it turns up.
            options.workdir = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--format") and i + 1 < args.len) {
            // `ps --format json`, which is how containerd asks. Distinct from
            // --log-format, which shapes nexcage's own log.
            options.format = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--storage") and i + 1 < args.len) {
            options.storage_name = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if ((std.mem.eql(u8, arg, "--resources") or std.mem.eql(u8, arg, "-r")) and i + 1 < args.len) {
            // How a container engine sends a resize: a runtime-spec
            // linux.resources object in a file, "-" for stdin.
            options.resources_path = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if ((options.command == .update or options.command == .create) and updateFlag(arg) != null) {
            // create takes update's limits under update's names (#308)
            if (i + 1 >= args.len) {
                printError("{s} needs a value", .{arg});
                return error.InvalidInput;
            }
            try addResourceUpdate(allocator, &options, updateFlag(arg).?, args[i + 1]);
            i += 2;
        } else if (options.command == .create and createValueFlag(arg) != null) {
            // What pct create is usually given (#308), under pct's names
            if (i + 1 >= args.len) {
                printError("{s} needs a value", .{arg});
                return error.InvalidInput;
            }
            try setCreateOption(allocator, &options.create_options, createValueFlag(arg).?, args[i + 1]);
            i += 2;
        } else if (options.command == .create and std.mem.eql(u8, arg, "--firewall")) {
            options.create_options.firewall = true;
            i += 1;
        } else if (options.command == .create and std.mem.eql(u8, arg, "--onboot")) {
            options.create_options.onboot = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--filename") and i + 1 < args.len) {
            options.filename = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--node") and i + 1 < args.len) {
            // Which node of the Proxmox cluster `create` should make the
            // container on.
            options.node = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--process") and i + 1 < args.len) {
            // How an engine sends an exec: the process spec in a file rather
            // than a command on the command line.
            options.process_file = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--description") and i + 1 < args.len) {
            // `snapshot --description <text>`. Named here so that the generic
            // branch below does not drop it and take its value for the
            // container's name; after the snapshot's name the command reads it
            // from options.args itself.
            options.description = try allocator.dupe(u8, args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "--start")) {
            // `rollback --start`: pct's flag, start the container afterwards.
            options.start_after_rollback = true;
            i += 1;
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
                options.command == .ps or options.command == .pause or options.command == .update or
                options.command == .resume_ or options.command == .snapshot or options.command == .snapshots or
                options.command == .rollback or options.command == .delsnapshot or
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
        } else if (std.mem.eql(u8, arg, "-")) {
            // Not an option: stdin, where a command reads it
            i += 1;
        } else {
            // An option no branch above claimed. It used to be skipped, so a
            // misspelling vanished and its value became the next positional
            // word: `create --memroy 2G` answered "OCI bundle '2G' must be an
            // absolute path", and `kill --al` signalled the init alone (#355).
            // Every option an engine was seen sending has a branch above. A
            // value flag lands here too when it is the last word: its branch
            // wants the value after it.
            if (i + 1 >= args.len) {
                printError("'{s}' is not an option of '{s}', or it needs a value; see 'nexcage {s} --help'", .{ arg, command_name, command_name });
            } else {
                printError("unknown option '{s}' for '{s}'; see 'nexcage {s} --help'", .{ arg, command_name, command_name });
            }
            return error.InvalidInput;
        }
    }

    return options;
}

/// The value of --config anywhere on the command line, or null. A --config
/// with nothing after it is a usage error.
fn configPathFromArgs(args: []const []const u8) !?[]const u8 {
    return flagValueFromArgs(args, "--config", "path");
}

/// `--flag=value` as two words, `--flag` and `value`, so that every parser
/// which reads the two-word form reads both spellings. runc and crun accept
/// either, and an engine picks one without asking: containerd passes
/// `--root <dir>`, CRI-O passes `--root=<dir>`.
///
/// The words are subslices of argv, so no string is copied; only the vector
/// is allocated, and the caller frees it. Anything after a bare `--` is the
/// command `exec` runs inside the container and is passed through untouched --
/// `env FOO=bar` is not a flag.
fn splitEqualsFlags(allocator: std.mem.Allocator, args: []const []const u8) ![][]const u8 {
    var out = std.ArrayListUnmanaged([]const u8){};
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, args.len + 4);

    var past_separator = false;
    for (args) |arg| {
        if (!past_separator and std.mem.eql(u8, arg, "--")) past_separator = true;
        if (!past_separator and arg.len > 2 and std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.indexOfScalar(u8, arg[2..], '=')) |rel| {
                const eq = rel + 2;
                try out.append(allocator, arg[0..eq]);
                try out.append(allocator, arg[eq + 1 ..]);
                continue;
            }
        }
        try out.append(allocator, arg);
    }

    return out.toOwnedSlice(allocator);
}

/// The value of a global flag wherever it appears, or null. The flag with
/// nothing after it is a usage error: taking the next command-line word would
/// silently use a container name as the value. `noun` names what is
/// expected, so each flag keeps its own message.
fn flagValueFromArgs(args: []const []const u8, flag: []const u8, noun: []const u8) !?[]const u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        // After a bare --, the words are the command exec runs, not nexcage's.
        if (std.mem.eql(u8, args[i], "--")) break;
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

/// Where nexcage's own words end: at the command `exec` runs in the
/// container, or at the end of the line for any other command. That command
/// is the first word after the container id that is neither an option nor an
/// option's value, or what follows a bare `--` after the id; the container id
/// is the first such word after `exec`, or the value of --name, as
/// parseRuntimeOptions reads them. runc and crun read none of their own
/// options in the command either.
fn ownWordsEnd(args: []const []const u8, command_index: usize) usize {
    if (command_index >= args.len or !std.mem.eql(u8, args[command_index], "exec")) return args.len;
    var id_seen = false;
    var i = command_index + 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (id_seen and std.mem.eql(u8, arg, "--")) return i;
        // An option, and its value if it takes one. A lone "-" is stdin,
        // which parseRuntimeOptions passes over too.
        if (std.mem.startsWith(u8, arg, "-")) {
            if (!takesValue(arg)) continue;
            if (std.mem.eql(u8, arg, "--name")) id_seen = true;
            i += 1;
            continue;
        }
        if (id_seen) return i;
        id_seen = true;
    }
    return args.len;
}

/// The options parseRuntimeOptions reads the next word for, whatever the
/// command. One missing here makes ownWordsEnd take its value for the
/// container id, and exec then fails for want of one rather than misread the
/// line; a test holds every name here to the parser.
const value_options = [_][]const u8{
    "--name",       "--console-socket", "--pid-file",  "--image",       "--bundle",
    "--runtime",    "--profile",        "--log-level", "--log-file",    "--log",
    "--log-format", "--config",         "--root",      "--user",        "--workdir",
    "--cwd",        "--format",         "--storage",   "--resources",   "-r",
    "--filename",   "--node",           "--process",   "--description", "--signal",
    "-s",
};

fn takesValue(arg: []const u8) bool {
    for (value_options) |o| if (std.mem.eql(u8, o, arg)) return true;
    return false;
}

/// `args` with the command exec runs as the caller wrote it. splitEqualsFlags
/// made `--color=auto` in it two words, which the command would have read as
/// two. That command starts with a whole word of argv -- one with no dash, or
/// the bare `--` -- so it is found there by its address. Frees `args`.
fn restoreCommandWords(allocator: std.mem.Allocator, raw: []const []const u8, args: [][]const u8, own_end: usize) ![][]const u8 {
    const first = args[own_end].ptr;
    const from = for (raw, 0..) |word, k| {
        if (word.ptr == first) break k;
    } else unreachable;
    const out = try allocator.alloc([]const u8, own_end + raw.len - from);
    @memcpy(out[0..own_end], args[0..own_end]);
    @memcpy(out[own_end..], raw[from..]);
    allocator.free(args);
    return out;
}

fn expectWords(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try std.testing.expectEqualStrings(e, a);
}

/// What run() makes of a command line before anything reads it: nexcage's
/// own words, then the command exec runs.
fn expectOwnWords(raw: []const []const u8, own: []const []const u8, command: []const []const u8) !void {
    const allocator = std.testing.allocator;
    var args = try splitEqualsFlags(allocator, raw);
    defer allocator.free(args);
    const end = ownWordsEnd(args, findCommand(args).index);
    if (end < args.len) args = try restoreCommandWords(allocator, raw, args, end);
    try expectWords(own, args[0..end]);
    try expectWords(command, args[end..]);
}

test "the command exec runs is the container's, flags, values and = included" {
    // Without --: the command starts at the word after the container id
    try expectOwnWords(
        &.{ "nexcage", "exec", "web", "grep", "--config", "x", "--log", "/x", "--root", "rel", "--debug" },
        &.{ "nexcage", "exec", "web" },
        &.{ "grep", "--config", "x", "--log", "/x", "--root", "rel", "--debug" },
    );
    try expectOwnWords(
        &.{ "nexcage", "exec", "web", "grep", "--color=auto", "--config=x" },
        &.{ "nexcage", "exec", "web" },
        &.{ "grep", "--color=auto", "--config=x" },
    );
    // --name names the container as the word after exec would
    try expectOwnWords(
        &.{ "nexcage", "exec", "--name", "web", "grep", "--config", "x" },
        &.{ "nexcage", "exec", "--name", "web" },
        &.{ "grep", "--config", "x" },
    );
    // With --
    try expectOwnWords(
        &.{ "nexcage", "exec", "web", "--", "env", "--log=/x" },
        &.{ "nexcage", "exec", "web" },
        &.{ "--", "env", "--log=/x" },
    );
    // nexcage's options before the container id and between it and the
    // command stay nexcage's, values and all
    try expectOwnWords(
        &.{ "nexcage", "--config=c.json", "exec", "--user", "1000", "web", "--log", "/l", "-t", "-", "sh", "-c", "--root=x" },
        &.{ "nexcage", "--config", "c.json", "exec", "--user", "1000", "web", "--log", "/l", "-t", "-" },
        &.{ "sh", "-c", "--root=x" },
    );
}

test "a command line with no command for exec to run is nexcage's to the end" {
    // How containerd's shim sends an exec
    try expectOwnWords(
        &.{ "nexcage", "--root", "/r", "--log", "/l", "exec", "--process", "/p.json", "--detach", "--pid-file", "/pid", "abc" },
        &.{ "nexcage", "--root", "/r", "--log", "/l", "exec", "--process", "/p.json", "--detach", "--pid-file", "/pid", "abc" },
        &.{},
    );
    try expectOwnWords(&.{ "nexcage", "exec", "web" }, &.{ "nexcage", "exec", "web" }, &.{});
    // Only exec runs a command: another command's words after its arguments
    // are nexcage's options still
    try expectOwnWords(&.{ "nexcage", "kill", "web", "KILL", "--root", "/x" }, &.{ "nexcage", "kill", "web", "KILL", "--root", "/x" }, &.{});
    // "exec" as an option's value is not the command
    try expectOwnWords(&.{ "nexcage", "--root", "exec", "list", "a", "b" }, &.{ "nexcage", "--root", "exec", "list", "a", "b" }, &.{});
}

/// exec's line `option [value] web ls`: parseRuntimeOptions finds the
/// container id `id`, and ownWordsEnd starts the command at `command`.
fn expectExecLine(option: []const u8, value: ?[]const u8, id: []const u8, command: []const []const u8) !void {
    var line: [6][]const u8 = undefined;
    var n: usize = 0;
    for ([_]?[]const u8{ "nexcage", "exec", option, value, "web", "ls" }) |word| if (word) |w| {
        line[n] = w;
        n += 1;
    };
    var options = try parseRuntimeOptions(std.testing.allocator, "exec", line[2..n]);
    defer options.deinit();
    errdefer std.debug.print("exec {s}: ", .{option});
    try std.testing.expectEqualStrings(id, options.container_id orelse "");
    try expectWords(command, line[ownWordsEnd(line[0..n], 1)..n]);
}

test "ownWordsEnd reads exec's options as parseRuntimeOptions does" {
    // Each option it steps over with its value is one the parser reads a
    // value for: the word after is not the container id
    for (value_options) |option| {
        if (std.mem.eql(u8, option, "--name")) continue;
        try expectExecLine(option, "lxc", "web", &.{"ls"});
    }
    // except --name's, which is the container id
    try expectExecLine("--name", "lxc", "lxc", &.{ "web", "ls" });
    // and options that take no value, the other way round
    for ([_][]const u8{ "-t", "--tty", "-d", "--detach", "-i", "--interactive", "--debug", "-v", "--verbose", "-f", "--force", "-a", "--all", "--systemd-cgroup", "--start", "-" }) |option| {
        try expectExecLine(option, null, "web", &.{"ls"});
    }
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
    if (std.mem.eql(u8, command_str, "features")) return .features;
    if (std.mem.eql(u8, command_str, "ps")) return .ps;
    if (std.mem.eql(u8, command_str, "images")) return .images;
    if (std.mem.eql(u8, command_str, "pull")) return .pull;
    if (std.mem.eql(u8, command_str, "rmi")) return .rmi;
    if (std.mem.eql(u8, command_str, "pause")) return .pause;
    if (std.mem.eql(u8, command_str, "resume")) return .resume_;
    if (std.mem.eql(u8, command_str, "update")) return .update;
    if (std.mem.eql(u8, command_str, "snapshot")) return .snapshot;
    if (std.mem.eql(u8, command_str, "snapshots")) return .snapshots;
    if (std.mem.eql(u8, command_str, "rollback")) return .rollback;
    if (std.mem.eql(u8, command_str, "delsnapshot")) return .delsnapshot;
    return .help; // Default to help
}

/// Parse a --runtime value; null for one nexcage does not know
fn parseRuntimeType(runtime_str: []const u8) ?core.RuntimeType {
    if (std.mem.eql(u8, runtime_str, "lxc") or std.mem.eql(u8, runtime_str, "proxmox-lxc")) return .lxc;
    if (std.mem.eql(u8, runtime_str, "crun")) return .crun;
    return null;
}

/// A removed backend gets the reason and what to use instead, not a list that
/// merely no longer contains it: runc went in 0.13.0, and crun runs the same
/// OCI containers; the Proxmox VM backend went in 0.14.0, and nexcage runs
/// containers only.
fn reportUnknownRuntime(value: []const u8) void {
    if (std.mem.eql(u8, value, "runc")) {
        printError("runc is not a backend since 0.13.0; the crun backend runs OCI containers -- use --runtime crun", .{});
    } else if (std.mem.eql(u8, value, "vm") or std.mem.eql(u8, value, "qemu")) {
        printError("the Proxmox VM backend was removed in 0.14.0; nexcage runs containers -- use --runtime lxc or crun", .{});
    } else {
        printError("unknown runtime '{s}'; expected lxc or crun", .{value});
    }
}

/// `update`'s value flags, named as runc and crun name them, and the section
/// and field of the runtime-spec linux.resources object each one sets. This is
/// crun's own table, so what a caller can say to crun it can say here.
const UpdateFlag = struct { flag: []const u8, section: []const u8, name: []const u8, numeric: bool };
const update_flags = [_]UpdateFlag{
    .{ .flag = "--blkio-weight", .section = "blockIO", .name = "weight", .numeric = true },
    .{ .flag = "--cpu-period", .section = "cpu", .name = "period", .numeric = true },
    .{ .flag = "--cpu-quota", .section = "cpu", .name = "quota", .numeric = true },
    .{ .flag = "--cpu-share", .section = "cpu", .name = "shares", .numeric = true },
    // runc's spelling of the same flag
    .{ .flag = "--cpu-shares", .section = "cpu", .name = "shares", .numeric = true },
    .{ .flag = "--cpu-rt-period", .section = "cpu", .name = "realtimePeriod", .numeric = true },
    .{ .flag = "--cpu-rt-runtime", .section = "cpu", .name = "realtimeRuntime", .numeric = true },
    .{ .flag = "--cpuset-cpus", .section = "cpu", .name = "cpus", .numeric = false },
    .{ .flag = "--cpuset-mems", .section = "cpu", .name = "mems", .numeric = false },
    .{ .flag = "--kernel-memory", .section = "memory", .name = "kernel", .numeric = true },
    .{ .flag = "--kernel-memory-tcp", .section = "memory", .name = "kernelTCP", .numeric = true },
    .{ .flag = "--memory", .section = "memory", .name = "limit", .numeric = true },
    .{ .flag = "--memory-reservation", .section = "memory", .name = "reservation", .numeric = true },
    .{ .flag = "--memory-swap", .section = "memory", .name = "swap", .numeric = true },
    .{ .flag = "--pids-limit", .section = "pids", .name = "limit", .numeric = true },
};

/// `create`'s pct options that take a value (#308). --mp may be given more
/// than once; each of the others is the last one given.
const CreateValueFlag = enum { cores, ip, gw, vlan, tags, mp };
fn createValueFlag(arg: []const u8) ?CreateValueFlag {
    const names = [_]struct { []const u8, CreateValueFlag }{
        .{ "--cores", .cores }, .{ "--ip", .ip },     .{ "--gw", .gw },
        .{ "--vlan", .vlan },   .{ "--tags", .tags }, .{ "--mp", .mp },
    };
    for (names) |n| if (std.mem.eql(u8, n[0], arg)) return n[1];
    return null;
}

fn setCreateOption(allocator: std.mem.Allocator, co: *core.types.ProxmoxCreateOptions, which: CreateValueFlag, raw: []const u8) !void {
    const value = try allocator.dupe(u8, raw);
    errdefer allocator.free(value);
    const slot: *?[]const u8 = switch (which) {
        .cores => &co.cores,
        .ip => &co.ip,
        .gw => &co.gw,
        .vlan => &co.vlan,
        .tags => &co.tags,
        .mp => {
            const grown = try allocator.alloc([]const u8, co.mount_points.len + 1);
            @memcpy(grown[0..co.mount_points.len], co.mount_points);
            grown[co.mount_points.len] = value;
            if (co.mount_points.len > 0) allocator.free(co.mount_points);
            co.mount_points = grown;
            return;
        },
    };
    if (slot.*) |old| allocator.free(old);
    slot.* = value;
}

fn updateFlag(arg: []const u8) ?UpdateFlag {
    for (update_flags) |f| if (std.mem.eql(u8, f.flag, arg)) return f;
    return null;
}

/// Append one setting, keeping the order the flags were given in: the
/// Proxmox backend turns the list into one `pct set`, and a caller reading
/// the recorded call expects to recognise the order.
fn addResourceUpdate(allocator: std.mem.Allocator, options: *core.RuntimeOptions, desc: UpdateFlag, raw: []const u8) !void {
    const old = options.resource_updates orelse &[_]core.types.ResourceUpdate{};
    var grown = try allocator.alloc(core.types.ResourceUpdate, old.len + 1);
    errdefer allocator.free(grown);
    @memcpy(grown[0..old.len], old);
    grown[old.len] = .{ .section = desc.section, .name = desc.name, .value = try allocator.dupe(u8, raw), .numeric = desc.numeric };
    if (options.resource_updates) |o| allocator.free(o);
    options.resource_updates = grown;
}
