/// CLI Plugin Manager
/// 
/// This module manages CLI plugins and integrates them with the main
/// NexCage CLI system, providing dynamic command registration and execution.

const std = @import("std");
const plugin = @import("mod.zig");
const cli_extension = @import("cli_extension.zig");
const core = @import("../core/mod.zig");

/// Registered CLI plugin information
pub const RegisteredCliPlugin = struct {
    name: []const u8,
    commands: []cli_extension.CliCommand,
    extension: *const cli_extension.CliExtension,
    plugin_context: *plugin.PluginContext,
    
    pub fn deinit(self: *RegisteredCliPlugin, allocator: std.mem.Allocator) void {
        self.extension.cleanup(allocator, self.commands);
        allocator.free(self.commands);
        allocator.free(self.name);
        self.plugin_context.deinit();
        allocator.destroy(self.plugin_context);
    }
};

/// CLI Plugin Manager
pub const CliPluginManager = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(RegisteredCliPlugin),
    plugin_manager: *plugin.PluginManager,
    logger: ?*core.LogContext = null,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_manager: *plugin.PluginManager
    ) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.StringHashMap(RegisteredCliPlugin).init(allocator),
            .plugin_manager = plugin_manager,
        };
    }
    
    pub fn deinit(self: *Self) void {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.plugins.deinit();
    }
    
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
    }
    
    /// Register a CLI plugin
    pub fn registerCliPlugin(
        self: *Self,
        plugin_name: []const u8,
        extension: *const cli_extension.CliExtension
    ) !void {
        if (self.logger) |log| {
            try log.info("Registering CLI plugin: {s}", .{plugin_name});
        }
        
        // Create plugin context for CLI extension
        const metadata = extension.getMetadata();
        const plugin_context = try self.allocator.create(plugin.PluginContext);
        plugin_context.* = try plugin.PluginContext.init(self.allocator, metadata);
        
        // Initialize the extension
        try extension.init(self.allocator, plugin_context);
        
        // Register commands from the extension
        const commands = try extension.registerCommands(self.allocator, plugin_context);
        
        const registered_plugin = RegisteredCliPlugin{
            .name = try self.allocator.dupe(u8, plugin_name),
            .commands = commands,
            .extension = extension,
            .plugin_context = plugin_context,
        };
        
        try self.plugins.put(registered_plugin.name, registered_plugin);
        
        if (self.logger) |log| {
            try log.info("Registered CLI plugin '{s}' with {d} commands", .{ plugin_name, commands.len });
        }
    }
    
    /// Unregister a CLI plugin
    pub fn unregisterCliPlugin(self: *Self, plugin_name: []const u8) !void {
        if (self.plugins.fetchRemove(plugin_name)) |kv| {
            if (self.logger) |log| {
                try log.info("Unregistering CLI plugin: {s}", .{plugin_name});
            }
            
            // Deinitialize the extension
            kv.value.extension.deinit(self.allocator, kv.value.plugin_context);
            
            // Cleanup the registered plugin
            kv.value.deinit(self.allocator);
            
            self.allocator.free(kv.key);
        }
    }
    
    /// Find a command by name across all registered plugins
    pub fn findCommand(self: *Self, command_name: []const u8) ?*const cli_extension.CliCommand {
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            for (entry.value_ptr.commands) |*command| {
                if (std.mem.eql(u8, command.name, command_name)) {
                    return command;
                }
                
                // Check subcommands too
                if (command.findSubcommand(command_name)) |subcmd| {
                    return subcmd;
                }
            }
        }
        return null;
    }
    
    /// Get all available commands from all plugins
    pub fn getAllCommands(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var commands = std.ArrayList([]const u8).empty;
        defer commands.deinit(allocator);
        
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            for (entry.value_ptr.commands) |command| {
                try commands.append(allocator, try allocator.dupe(u8, command.name));
                
                // Add subcommands
                for (command.subcommands) |subcmd| {
                    const full_name = try std.fmt.allocPrint(allocator, "{s} {s}", .{ command.name, subcmd.name });
                    try commands.append(allocator, full_name);
                }
            }
        }
        
        return commands.toOwnedSlice(allocator);
    }
    
    /// Get commands from a specific plugin
    pub fn getPluginCommands(self: *Self, plugin_name: []const u8) ?[]const cli_extension.CliCommand {
        if (self.plugins.get(plugin_name)) |registered_plugin| {
            return registered_plugin.commands;
        }
        return null;
    }
    
    /// Execute a command from a registered plugin
    pub fn executeCommand(
        self: *Self,
        command_name: []const u8,
        args: []const []const u8,
        allocator: std.mem.Allocator
    ) !cli_extension.CliResult {
        const command = self.findCommand(command_name) orelse {
            return cli_extension.CliResult.failure(1, "Command not found");
        };
        
        // Find the plugin that owns this command
        var plugin_context: ?*plugin.PluginContext = null;
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            for (entry.value_ptr.commands) |*cmd| {
                if (cmd == command) {
                    plugin_context = entry.value_ptr.plugin_context;
                    break;
                }
            }
            if (plugin_context != null) break;
        }
        
        if (plugin_context == null) {
            return cli_extension.CliResult.failure(1, "Plugin context not found");
        }
        
        // Create CLI context and parse arguments
        var cli_context = cli_extension.CliContext.init(allocator, plugin_context.?);
        defer cli_context.deinit();
        
        if (self.logger) |log| {
            cli_context.logger = log;
        }
        
        // Simple argument parsing (would be more sophisticated in real implementation)
        try self.parseArguments(command, args, &cli_context);
        
        // Execute the command
        return command.execute(&cli_context);
    }
    
    /// Simple argument parser (basic implementation)
    fn parseArguments(
        self: *Self,
        command: *const cli_extension.CliCommand,
        args: []const []const u8,
        context: *cli_extension.CliContext
    ) !void {
        _ = self;
        var arg_index: usize = 0;
        var i: usize = 0;
        
        while (i < args.len) {
            const arg = args[i];
            
            if (std.mem.startsWith(u8, arg, "--")) {
                // Long option
                const option_name = arg[2..];
                
                // Find option definition
                var option_def: ?cli_extension.CliOption = null;
                for (command.options) |opt| {
                    if (std.mem.eql(u8, opt.name, option_name)) {
                        option_def = opt;
                        break;
                    }
                }
                
                if (option_def) |opt| {
                    if (opt.has_value and i + 1 < args.len) {
                        // Option with value
                        i += 1;
                        try context.setOption(option_name, args[i]);
                    } else {
                        // Flag option
                        try context.setOption(option_name, "true");
                    }
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
                // Short option
                const short_char = arg[1];
                
                // Find option definition
                var option_def: ?cli_extension.CliOption = null;
                for (command.options) |opt| {
                    if (opt.short == short_char) {
                        option_def = opt;
                        break;
                    }
                }
                
                if (option_def) |opt| {
                    if (opt.has_value and i + 1 < args.len) {
                        // Option with value
                        i += 1;
                        try context.setOption(opt.name, args[i]);
                    } else {
                        // Flag option
                        try context.setOption(opt.name, "true");
                    }
                }
            } else {
                // Positional argument
                if (arg_index < command.arguments.len) {
                    try context.setArgument(command.arguments[arg_index].name, arg);
                    arg_index += 1;
                }
            }
            
            i += 1;
        }
    }
    
    /// List all registered plugins
    pub fn listPlugins(self: *Self, allocator: std.mem.Allocator) ![][]const u8 {
        var plugin_names = std.ArrayList([]const u8).empty;
        defer plugin_names.deinit(allocator);
        
        var iterator = self.plugins.iterator();
        while (iterator.next()) |entry| {
            try plugin_names.append(allocator, try allocator.dupe(u8, entry.key_ptr.*));
        }
        
        return plugin_names.toOwnedSlice(allocator);
    }
    
    /// Get plugin information
    pub fn getPluginInfo(self: *Self, plugin_name: []const u8) ?plugin.PluginMetadata {
        if (self.plugins.get(plugin_name)) |registered_plugin| {
            return registered_plugin.extension.getMetadata();
        }
        return null;
    }
    
    /// Auto-discover and load CLI plugins from the plugin system
    pub fn loadCliPlugins(self: *Self) !void {
        if (self.logger) |log| {
            try log.info("Auto-discovering CLI plugins...", .{});
        }
        
        // Get all loaded plugins from the plugin manager
        const loaded_plugins = try self.plugin_manager.listPlugins(self.allocator);
        defer {
            for (loaded_plugins) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(loaded_plugins);
        }
        
        for (loaded_plugins) |plugin_name| {
            if (self.plugin_manager.getPlugin(plugin_name)) |loaded_plugin| {
                // Check if plugin provides CLI commands
                const metadata = loaded_plugin.metadata;
                if (metadata.provides_cli_commands) {
                    if (self.logger) |log| {
                        try log.info("Found CLI plugin: {s}", .{plugin_name});
                    }
                    
                    // Note: In a real implementation, we would load the CLI extension
                    // from the plugin's dynamic library or registered extension points
                    // For now, this is a placeholder for the discovery mechanism
                }
            }
        }
    }
};

/// Test suite
const testing = std.testing;

test "CLI plugin manager basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_manager = CliPluginManager.init(allocator, &plugin_manager);
    defer cli_manager.deinit();
    
    // Test that manager initializes correctly
    try testing.expect(cli_manager.plugins.count() == 0);
    
    // Test listing empty plugins
    const empty_list = try cli_manager.listPlugins(allocator);
    defer {
        for (empty_list) |name| {
            allocator.free(name);
        }
        allocator.free(empty_list);
    }
    try testing.expect(empty_list.len == 0);
}

test "CLI command finding and execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_manager = CliPluginManager.init(allocator, &plugin_manager);
    defer cli_manager.deinit();
    
    // Test finding non-existent command
    const not_found = cli_manager.findCommand("nonexistent");
    try testing.expect(not_found == null);
    
    // Test executing non-existent command
    const result = try cli_manager.executeCommand("nonexistent", &[_][]const u8{}, allocator);
    try testing.expect(result.exit_code == 1);
}

test "CLI argument parsing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_manager = CliPluginManager.init(allocator, &plugin_manager);
    defer cli_manager.deinit();
    
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
    
    var cli_context = cli_extension.CliContext.init(allocator, &plugin_context);
    defer cli_context.deinit();
    
    const command = cli_extension.CliCommand{
        .name = "test",
        .description = "Test command",
        .usage = "nexcage test [options] <container>",
        .arguments = &[_]cli_extension.CliArgument{
            cli_extension.CliArgument{
                .name = "container",
                .description = "Container name",
                .required = true,
            },
        },
        .options = &[_]cli_extension.CliOption{
            cli_extension.CliOption{
                .name = "verbose",
                .short = 'v',
                .description = "Enable verbose output",
                .option_type = .flag,
                .has_value = false,
            },
        },
    };
    
    const args = [_][]const u8{ "--verbose", "test-container" };
    try cli_manager.parseArguments(&command, &args, &cli_context);
    
    try testing.expect(cli_context.hasFlag("verbose"));
    try testing.expect(std.mem.eql(u8, cli_context.getArgument("container").?, "test-container"));
}