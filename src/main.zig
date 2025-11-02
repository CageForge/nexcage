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

    pub fn init(allocator: std.mem.Allocator, args: []const []const u8) !AppContext {
        // Load main configuration first
        var config_loader = core.ConfigLoader.init(allocator);
        var config = try config_loader.loadDefault();
        
        // Load logging configuration with priority: command line args > config file > environment > defaults
        const logging_cfg = try core.logging_config.LoggingConfig.loadWithPriority(allocator, args, &config);

        // Initialize basic logger
        // Use stdout writer with empty buffer (Zig 0.15.1 requires buffer parameter)
        const stdout = std.fs.File.stdout();
        var empty_buffer: [0]u8 = undefined;
        const logger = core.LogContext.init(allocator, stdout.writer(&empty_buffer), config.log_level, "nexcage");

        // Initialize advanced logger if debug mode or file logging is enabled
        var advanced_logger: ?core.simple_advanced_logging.SimpleAdvancedLogging = null;
        if (logging_cfg.debug_mode or logging_cfg.enable_file_logging) {
            advanced_logger = try core.simple_advanced_logging.SimpleAdvancedLogging.init(allocator, logging_cfg.debug_mode, logging_cfg.log_file_path);
        }

        // Error handling is done through core.errors.ErrorHandler interface
        // DefaultErrorHandler is available in core.errors module

        // Initialize global command registry
        try cli.initGlobalRegistry(allocator);

        // Initialize command registry
        var command_registry = cli.CommandRegistry.init(allocator);

        // Register built-in commands
        try cli.registerBuiltinCommandsWithLogger(&command_registry, &logger);

        return AppContext{
            .allocator = allocator,
            .config = config,
            .logger = logger,
            .advanced_logger = advanced_logger,
            .logging_config = logging_cfg,
            .command_registry = command_registry,
        };
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
        cli.deinitGlobalRegistry();
        self.logger.deinit();
        // config.deinit() already called above
    }

    // Backend routing is now handled by BackendRouter in core/router.zig
    // Network, storage, and image providers are integrated via backends
    // Legacy provider initialization methods removed - functionality moved to modular backend system
};

/// Main function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments first
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize application context with command line arguments
    var app = try AppContext.init(allocator, args);
    defer app.deinit();

    // Log application startup
    if (app.advanced_logger) |*logger| {
        try logger.info("Starting nexcage v{s}", .{core.version.getVersion()});
        try logger.logSystemInfo();
    }

    if (args.len < 2) {
        try app.logger.err("No command specified. Use 'help' for available commands.", .{});
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
        command_args = args[i + 1..];
        break;
    }
    
    // Log command execution start - safely handle logger errors
    if (app.advanced_logger) |*logger| {
        logger.logCommandStart(command_name, command_args) catch {};
    }
    
    // Handle help command
    if (std.mem.eql(u8, command_name, "--help") or std.mem.eql(u8, command_name, "-h")) {
        try app.logger.info("Proxmox LXC Runtime Interface v{s}", .{core.version.getVersion()});
        try app.logger.info("", .{});
        try app.logger.info("Available commands:", .{});
        try app.logger.info("  create    Create a new container", .{});
        try app.logger.info("  start     Start a container", .{});
        try app.logger.info("  stop      Stop a container", .{});
        try app.logger.info("  delete    Delete a container", .{});
        try app.logger.info("  list      List containers", .{});
        try app.logger.info("  kill      Send a signal to a container", .{});
        try app.logger.info("  run       Run a command in a container", .{});
        try app.logger.info("  help      Show this help message", .{});
        try app.logger.info("  version   Show version information", .{});
        try app.logger.info("", .{});
        try app.logger.info("Use 'nexcage <command> --help' for command-specific help", .{});
        return;
    }

    // Parse runtime options
    var options = try parseRuntimeOptions(allocator, command_name, command_args, &app.config);
    defer options.deinit();

    // Check if help was requested
    if (options.help) {
        // Help is handled by individual commands
        // Backend and provider initialization handled by BackendRouter in core/router.zig

        // Execute command (which will handle help)
        try app.command_registry.execute(command_name, options, allocator);
        
        // Log command completion - safely handle logger errors
        if (app.advanced_logger) |*logger| {
            logger.logCommandComplete(command_name, true) catch {};
        }
        return;
    }

    // Backend and provider initialization handled by BackendRouter in core/router.zig
    // Execute command
    try app.command_registry.execute(command_name, options, allocator);
    
    // Log command completion - safely handle logger errors
    if (app.advanced_logger) |*logger| {
        logger.logCommandComplete(command_name, true) catch {};
    }
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
