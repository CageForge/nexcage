/// CLI Extension Plugin Interface
/// 
/// This module defines the interface for CLI plugins that can extend
/// NexCage's command-line functionality with new commands and subcommands.

const std = @import("std");
const plugin = @import("mod.zig");
const core = @import("../core/mod.zig");

/// CLI command argument definition
pub const CliArgument = struct {
    name: []const u8,
    description: []const u8,
    required: bool = false,
    arg_type: ArgumentType = .string,
    
    pub const ArgumentType = enum {
        string,
        number,
        boolean,
        file_path,
        directory_path,
    };
};

/// CLI command option definition (flags)
pub const CliOption = struct {
    name: []const u8,
    short: ?u8 = null, // Single character short option
    description: []const u8,
    required: bool = false,
    has_value: bool = true,
    option_type: OptionType = .string,
    
    pub const OptionType = enum {
        string,
        number,
        boolean,
        flag, // Boolean flag without value
    };
};

/// CLI command execution context
pub const CliContext = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    arguments: std.StringHashMap([]const u8),
    options: std.StringHashMap([]const u8),
    plugin_context: *plugin.PluginContext,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_context: *plugin.PluginContext
    ) CliContext {
        return CliContext{
            .allocator = allocator,
            .arguments = std.StringHashMap([]const u8).init(allocator),
            .options = std.StringHashMap([]const u8).init(allocator),
            .plugin_context = plugin_context,
        };
    }
    
    pub fn deinit(self: *CliContext) void {
        var arg_iter = self.arguments.iterator();
        while (arg_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.arguments.deinit();
        
        var opt_iter = self.options.iterator();
        while (opt_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.options.deinit();
    }
    
    /// Get argument value by name
    pub fn getArgument(self: *const CliContext, name: []const u8) ?[]const u8 {
        return self.arguments.get(name);
    }
    
    /// Get option value by name
    pub fn getOption(self: *const CliContext, name: []const u8) ?[]const u8 {
        return self.options.get(name);
    }
    
    /// Check if flag option is set
    pub fn hasFlag(self: *const CliContext, name: []const u8) bool {
        return self.options.contains(name);
    }
    
    /// Set argument value
    pub fn setArgument(self: *CliContext, name: []const u8, value: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.arguments.put(name_copy, value_copy);
    }
    
    /// Set option value
    pub fn setOption(self: *CliContext, name: []const u8, value: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.options.put(name_copy, value_copy);
    }
    
    /// Log info message if logger is available
    pub fn logInfo(self: *const CliContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.info(format, args);
        }
    }
    
    /// Log warning message if logger is available
    pub fn logWarn(self: *const CliContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.warn(format, args);
        }
    }
    
    /// Log error message if logger is available
    pub fn logError(self: *const CliContext, comptime format: []const u8, args: anytype) !void {
        if (self.logger) |log| {
            try log.err(format, args);
        }
    }
};

/// CLI command execution result
pub const CliResult = struct {
    exit_code: u8 = 0,
    message: ?[]const u8 = null,
    
    pub fn success() CliResult {
        return CliResult{};
    }
    
    pub fn failure(exit_code: u8, message: ?[]const u8) CliResult {
        return CliResult{
            .exit_code = exit_code,
            .message = message,
        };
    }
};

/// CLI command definition
pub const CliCommand = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    arguments: []const CliArgument = &[_]CliArgument{},
    options: []const CliOption = &[_]CliOption{},
    subcommands: []const CliCommand = &[_]CliCommand{},
    execute_fn: ?*const fn(*CliContext) anyerror!CliResult = null,
    
    /// Generate help text for this command
    pub fn generateHelp(self: *const CliCommand, allocator: std.mem.Allocator) ![]const u8 {
        var help_text = std.ArrayList(u8).empty;
        defer help_text.deinit(allocator);
        
        // Command name and description
        try help_text.writer(allocator).print("{s} - {s}\n\n", .{ self.name, self.description });
        
        // Usage
        try help_text.writer(allocator).print("Usage: {s}\n\n", .{self.usage});
        
        // Arguments
        if (self.arguments.len > 0) {
            try help_text.writer(allocator).print("Arguments:\n");
            for (self.arguments) |arg| {
                const required_marker = if (arg.required) "*" else " ";
                try help_text.writer(allocator).print("  {s}{s}  {s}\n", .{ required_marker, arg.name, arg.description });
            }
            try help_text.writer(allocator).print("\n");
        }
        
        // Options
        if (self.options.len > 0) {
            try help_text.writer(allocator).print("Options:\n");
            for (self.options) |opt| {
                const short_opt = if (opt.short) |s| 
                    try std.fmt.allocPrint(allocator, "-{c}, ", .{s})
                else 
                    try allocator.dupe(u8, "    ");
                defer allocator.free(short_opt);
                
                const required_marker = if (opt.required) "*" else " ";
                try help_text.writer(allocator).print("  {s}{s}--{s}  {s}\n", .{ required_marker, short_opt, opt.name, opt.description });
            }
            try help_text.writer(allocator).print("\n");
        }
        
        // Subcommands
        if (self.subcommands.len > 0) {
            try help_text.writer(allocator).print("Subcommands:\n");
            for (self.subcommands) |subcmd| {
                try help_text.writer(allocator).print("  {s}  {s}\n", .{ subcmd.name, subcmd.description });
            }
            try help_text.writer(allocator).print("\n");
        }
        
        return help_text.toOwnedSlice(allocator);
    }
    
    /// Find subcommand by name
    pub fn findSubcommand(self: *const CliCommand, name: []const u8) ?*const CliCommand {
        for (self.subcommands) |*subcmd| {
            if (std.mem.eql(u8, subcmd.name, name)) {
                return subcmd;
            }
        }
        return null;
    }
    
    /// Validate command arguments and options
    pub fn validate(self: *const CliCommand, context: *const CliContext) !void {
        // Check required arguments
        for (self.arguments) |arg| {
            if (arg.required and context.getArgument(arg.name) == null) {
                return error.MissingRequiredArgument;
            }
        }
        
        // Check required options
        for (self.options) |opt| {
            if (opt.required and context.getOption(opt.name) == null) {
                return error.MissingRequiredOption;
            }
        }
    }
    
    /// Execute the command
    pub fn execute(self: *const CliCommand, context: *CliContext) !CliResult {
        try self.validate(context);
        
        if (self.execute_fn) |exec_fn| {
            return exec_fn(context);
        }
        
        return CliResult.failure(1, "Command execution not implemented");
    }
};

/// CLI Extension Plugin Interface
pub const CliExtension = struct {
    /// Register commands provided by this plugin
    register_commands_fn: *const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) anyerror![]CliCommand,
    
    /// Cleanup resources allocated by this plugin
    cleanup_fn: ?*const fn(allocator: std.mem.Allocator, commands: []CliCommand) void = null,
    
    /// Get plugin metadata for CLI extension
    get_metadata_fn: *const fn() plugin.PluginMetadata,
    
    /// Initialize CLI extension
    init_fn: ?*const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) anyerror!void = null,
    
    /// Deinitialize CLI extension
    deinit_fn: ?*const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) void = null,
    
    /// Register commands
    pub fn registerCommands(
        self: *const CliExtension,
        allocator: std.mem.Allocator,
        plugin_context: *plugin.PluginContext
    ) ![]CliCommand {
        return self.register_commands_fn(allocator, plugin_context);
    }
    
    /// Initialize extension
    pub fn init(
        self: *const CliExtension,
        allocator: std.mem.Allocator,
        plugin_context: *plugin.PluginContext
    ) !void {
        if (self.init_fn) |init_fn| {
            try init_fn(allocator, plugin_context);
        }
    }
    
    /// Deinitialize extension
    pub fn deinit(
        self: *const CliExtension,
        allocator: std.mem.Allocator,
        plugin_context: *plugin.PluginContext
    ) void {
        if (self.deinit_fn) |deinit_fn| {
            deinit_fn(allocator, plugin_context);
        }
    }
    
    /// Cleanup commands
    pub fn cleanup(
        self: *const CliExtension,
        allocator: std.mem.Allocator,
        commands: []CliCommand
    ) void {
        if (self.cleanup_fn) |cleanup_fn| {
            cleanup_fn(allocator, commands);
        }
    }
    
    /// Get metadata
    pub fn getMetadata(self: *const CliExtension) plugin.PluginMetadata {
        return self.get_metadata_fn();
    }
};

/// Test helper functions
const testing = std.testing;

test "CLI context creation and usage" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create mock plugin context
    const metadata = plugin.PluginMetadata{
        .name = "test-cli-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Test CLI plugin",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = true,
    };
    
    var plugin_context = try plugin.PluginContext.init(allocator, metadata);
    defer plugin_context.deinit();
    
    var cli_context = CliContext.init(allocator, &plugin_context);
    defer cli_context.deinit();
    
    // Test setting and getting arguments
    try cli_context.setArgument("container", "test-container");
    try cli_context.setOption("verbose", "true");
    
    try testing.expect(std.mem.eql(u8, cli_context.getArgument("container").?, "test-container"));
    try testing.expect(std.mem.eql(u8, cli_context.getOption("verbose").?, "true"));
    try testing.expect(cli_context.hasFlag("verbose"));
    try testing.expect(!cli_context.hasFlag("nonexistent"));
}

test "CLI command help generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const command = CliCommand{
        .name = "test",
        .description = "Test command",
        .usage = "nexcage test [options] <container>",
        .arguments = &[_]CliArgument{
            CliArgument{
                .name = "container",
                .description = "Container name or ID",
                .required = true,
            },
        },
        .options = &[_]CliOption{
            CliOption{
                .name = "verbose",
                .short = 'v',
                .description = "Enable verbose output",
                .option_type = .flag,
                .has_value = false,
            },
        },
    };
    
    const help_text = try command.generateHelp(allocator);
    defer allocator.free(help_text);
    
    try testing.expect(std.mem.indexOf(u8, help_text, "test - Test command") != null);
    try testing.expect(std.mem.indexOf(u8, help_text, "container") != null);
    try testing.expect(std.mem.indexOf(u8, help_text, "verbose") != null);
}

test "CLI command validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create mock plugin context
    const metadata = plugin.PluginMetadata{
        .name = "test-cli-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Test CLI plugin",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{.logging},
        .resource_requirements = plugin.ResourceRequirements{},
        .provides_cli_commands = true,
    };
    
    var plugin_context = try plugin.PluginContext.init(allocator, metadata);
    defer plugin_context.deinit();
    
    var cli_context = CliContext.init(allocator, &plugin_context);
    defer cli_context.deinit();
    
    const command = CliCommand{
        .name = "test",
        .description = "Test command",
        .usage = "nexcage test <container>",
        .arguments = &[_]CliArgument{
            CliArgument{
                .name = "container",
                .description = "Container name",
                .required = true,
            },
        },
    };
    
    // Test validation failure with missing required argument
    try testing.expectError(error.MissingRequiredArgument, command.validate(&cli_context));
    
    // Test validation success with required argument
    try cli_context.setArgument("container", "test-container");
    try command.validate(&cli_context);
}