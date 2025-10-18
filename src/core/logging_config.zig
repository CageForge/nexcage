const std = @import("std");

/// Logging configuration
pub const LoggingConfig = struct {
    debug_mode: bool = false,
    log_file_path: ?[]const u8 = null,
    log_level: LogLevel = .info,
    enable_file_logging: bool = false,
    enable_console_logging: bool = true,
    enable_performance_tracking: bool = false,
    enable_memory_tracking: bool = false,
    log_rotation: bool = false,
    max_log_file_size: u64 = 10 * 1024 * 1024, // 10MB
    max_log_files: u32 = 5,

    const Self = @This();

    /// Load logging configuration from environment variables
    pub fn loadFromEnv(allocator: std.mem.Allocator) !Self {
        var config = Self{};

        // Check for debug mode
        if (std.process.getEnvVarOwned(allocator, "NEXCAGE_DEBUG")) |debug_str| {
            defer allocator.free(debug_str);
            config.debug_mode = std.mem.eql(u8, debug_str, "1") or std.mem.eql(u8, debug_str, "true");
        } else |_| {}

        // Check for log file path
        if (std.process.getEnvVarOwned(allocator, "NEXCAGE_LOG_FILE")) |log_file| {
            config.log_file_path = log_file;
            config.enable_file_logging = true;
        } else |_| {}

        // Check for log level
        if (std.process.getEnvVarOwned(allocator, "NEXCAGE_LOG_LEVEL")) |level_str| {
            defer allocator.free(level_str);
            config.log_level = parseLogLevel(level_str) orelse .info;
        } else |_| {}

        // Check for performance tracking
        if (std.process.getEnvVarOwned(allocator, "NEXCAGE_PERF_TRACKING")) |perf_str| {
            defer allocator.free(perf_str);
            config.enable_performance_tracking = std.mem.eql(u8, perf_str, "1") or std.mem.eql(u8, perf_str, "true");
        } else |_| {}

        // Check for memory tracking
        if (std.process.getEnvVarOwned(allocator, "NEXCAGE_MEMORY_TRACKING")) |mem_str| {
            defer allocator.free(mem_str);
            config.enable_memory_tracking = std.mem.eql(u8, mem_str, "1") or std.mem.eql(u8, mem_str, "true");
        } else |_| {}

        return config;
    }

    /// Load logging configuration from command line arguments
    pub fn loadFromArgs(allocator: std.mem.Allocator, args: []const []const u8) !Self {
        var config = Self{};

        var i: usize = 0;
        while (i < args.len) {
            const arg = args[i];
            
            if (std.mem.eql(u8, arg, "--debug")) {
                config.debug_mode = true;
                config.log_level = .debug;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                config.log_level = .debug;
            } else if (std.mem.eql(u8, arg, "--log-file")) {
                if (i + 1 < args.len) {
                    config.log_file_path = try allocator.dupe(u8, args[i + 1]);
                    config.enable_file_logging = true;
                    i += 1; // Skip next argument as it's the file path
                }
            } else if (std.mem.eql(u8, arg, "--log-level")) {
                if (i + 1 < args.len) {
                    config.log_level = parseLogLevel(args[i + 1]) orelse .info;
                    i += 1; // Skip next argument as it's the log level
                }
            } else if (std.mem.eql(u8, arg, "--perf-tracking")) {
                config.enable_performance_tracking = true;
            } else if (std.mem.eql(u8, arg, "--memory-tracking")) {
                config.enable_memory_tracking = true;
            }
            
            i += 1;
        }

        return config;
    }

    /// Load logging configuration from config file
    pub fn loadFromConfig(allocator: std.mem.Allocator, config: *const @import("config.zig").Config) !Self {
        var logging_config = Self{};

        // Load from config file
        logging_config.debug_mode = config.log_level == .debug;
        logging_config.log_level = config.log_level;
        
        if (config.log_file) |log_file| {
            logging_config.log_file_path = try allocator.dupe(u8, log_file);
            logging_config.enable_file_logging = true;
        }

        return logging_config;
    }

    /// Load logging configuration with priority: command line args > config file > environment > defaults
    pub fn loadWithPriority(allocator: std.mem.Allocator, args: []const []const u8, config: ?*const @import("config.zig").Config) !Self {
        // Start with defaults
        var logging_config = try createDefault(allocator);

        // Load from config file if available (lowest priority)
        if (config) |cfg| {
            const file_config = try loadFromConfig(allocator, cfg);
            // Merge file config into our config
            logging_config.debug_mode = file_config.debug_mode;
            logging_config.log_level = file_config.log_level;
            if (file_config.log_file_path) |log_file| {
                if (logging_config.log_file_path) |old_path| {
                    allocator.free(old_path);
                }
                logging_config.log_file_path = log_file;
                logging_config.enable_file_logging = true;
            }
            logging_config.enable_performance_tracking = file_config.enable_performance_tracking;
            logging_config.enable_memory_tracking = file_config.enable_memory_tracking;
        }

        // Load from environment variables (medium priority)
        const env_config = loadFromEnv(allocator) catch logging_config;
        // Merge environment config, but only if values are set
        if (env_config.debug_mode) {
            logging_config.debug_mode = true;
            logging_config.log_level = .debug;
        }
        if (env_config.log_file_path) |log_file| {
            if (logging_config.log_file_path) |old_path| {
                allocator.free(old_path);
            }
            logging_config.log_file_path = log_file;
            logging_config.enable_file_logging = true;
        }
        if (env_config.log_level != .info) { // Only override if not default
            logging_config.log_level = env_config.log_level;
        }
        if (env_config.enable_performance_tracking) {
            logging_config.enable_performance_tracking = true;
        }
        if (env_config.enable_memory_tracking) {
            logging_config.enable_memory_tracking = true;
        }

        // Load from command line arguments (highest priority)
        const args_config = try loadFromArgs(allocator, args);
        // Merge command line config, overriding everything else
        if (args_config.debug_mode) {
            logging_config.debug_mode = true;
            logging_config.log_level = .debug;
        }
        if (args_config.log_file_path) |log_file| {
            if (logging_config.log_file_path) |old_path| {
                allocator.free(old_path);
            }
            logging_config.log_file_path = log_file;
            logging_config.enable_file_logging = true;
        }
        if (args_config.log_level != .info) { // Only override if not default
            logging_config.log_level = args_config.log_level;
        }
        if (args_config.enable_performance_tracking) {
            logging_config.enable_performance_tracking = true;
        }
        if (args_config.enable_memory_tracking) {
            logging_config.enable_memory_tracking = true;
        }

        return logging_config;
    }

    /// Create default logging configuration
    pub fn createDefault(allocator: std.mem.Allocator) !Self {
        return Self{
            .debug_mode = false,
            .log_file_path = try createDefaultLogPath(allocator),
            .log_level = .info,
            .enable_file_logging = false,
            .enable_console_logging = true,
            .enable_performance_tracking = false,
            .enable_memory_tracking = false,
        };
    }

    /// Create default log file path
    fn createDefaultLogPath(allocator: std.mem.Allocator) ![]const u8 {
        const timestamp = std.time.timestamp();
        return try std.fmt.allocPrint(allocator, "/tmp/nexcage-{d}.log", .{timestamp});
    }

    /// Parse log level from string
    fn parseLogLevel(level_str: []const u8) ?LogLevel {
        if (std.mem.eql(u8, level_str, "trace")) return .trace;
        if (std.mem.eql(u8, level_str, "debug")) return .debug;
        if (std.mem.eql(u8, level_str, "info")) return .info;
        if (std.mem.eql(u8, level_str, "warn")) return .warn;
        if (std.mem.eql(u8, level_str, "error")) return .@"error";
        if (std.mem.eql(u8, level_str, "fatal")) return .fatal;
        return null;
    }

    /// Deinitialize configuration
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.log_file_path) |path| {
            allocator.free(path);
        }
    }
};

/// Re-export LogLevel
pub const LogLevel = @import("logging.zig").LogLevel;
