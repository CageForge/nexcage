/// CLI Plugin Integration
/// 
/// This module integrates the new CLI plugin system with the existing
/// CLI command registry, providing a bridge between plugin commands
/// and the legacy CommandInterface.

const std = @import("std");
const core = @import("core");
const types = core.types;
const interfaces = core.interfaces;
const plugin = @import("plugin");
const cli_plugins = @import("cli_plugins");
const registry = @import("registry.zig");

/// Plugin command wrapper that implements CommandInterface
pub const PluginCommandWrapper = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    plugin_command: *const plugin.CliCommand,
    cli_manager: *plugin.CliPluginManager,
    command_name: []const u8,
    
    pub fn init(
        allocator: std.mem.Allocator,
        plugin_command: *const plugin.CliCommand,
        cli_manager: *plugin.CliPluginManager
    ) !*Self {
        const wrapper = try allocator.create(Self);
        wrapper.* = Self{
            .allocator = allocator,
            .plugin_command = plugin_command,
            .cli_manager = cli_manager,
            .command_name = try allocator.dupe(u8, plugin_command.name),
        };
        return wrapper;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.command_name);
        self.allocator.destroy(self);
    }
    
    /// Convert to CommandInterface
    pub fn toInterface(self: *Self) interfaces.CommandInterface {
        return interfaces.CommandInterface{
            .name = self.command_name,
            .description = self.plugin_command.description,
            .ctx = self,
            .execute = wrapperExecute,
            .help = wrapperHelp,
            .validate = wrapperValidate,
        };
    }

    fn wrapperExecute(iface: *interfaces.CommandInterface, options: types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        const self = @as(*Self, @ptrCast(@alignCast(iface.ctx)));
        
        // Reconstruct args from options
        var args = std.ArrayList([]const u8).init(allocator);
        defer args.deinit();
        
        // If container_id is set and not default, pass it as an argument
        if (options.container_id.len > 0 and !std.mem.eql(u8, options.container_id, "default")) {
            try args.append(options.container_id);
        }
        
        _ = try self.executeWithContext(args.items);
    }

    fn wrapperHelp(iface: *interfaces.CommandInterface, allocator: std.mem.Allocator) ![]const u8 {
        _ = allocator;
        const self = @as(*Self, @ptrCast(@alignCast(iface.ctx)));
        return self.helpWithContext();
    }

    fn wrapperValidate(iface: *interfaces.CommandInterface, args: []const []const u8) !void {
        _ = iface;
        _ = args;
        // Validation delegated to plugin execution
    }
    
    /// Execute command with access to self
    pub fn executeWithContext(self: *Self, args: []const []const u8) !plugin.CliResult {
        return self.cli_manager.executeCommand(self.command_name, args, self.allocator);
    }
    
    /// Get help with access to self
    pub fn helpWithContext(self: *Self) ![]const u8 {
        return self.plugin_command.generateHelp(self.allocator);
    }
};

/// Enhanced CLI registry that supports both legacy commands and plugin commands
pub const EnhancedCommandRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    legacy_registry: registry.CommandRegistry,
    cli_plugin_manager: *plugin.CliPluginManager,
    cli_plugin_registry: *cli_plugins.CliPluginRegistry,
    plugin_wrappers: std.ArrayList(*PluginCommandWrapper),
    logger: ?*core.LogContext = null,
    
    pub fn init(
        allocator: std.mem.Allocator,
        cli_plugin_manager: *plugin.CliPluginManager,
        cli_plugin_registry: *cli_plugins.CliPluginRegistry
    ) Self {
        return Self{
            .allocator = allocator,
            .legacy_registry = registry.CommandRegistry.init(allocator),
            .cli_plugin_manager = cli_plugin_manager,
            .cli_plugin_registry = cli_plugin_registry,
            .plugin_wrappers = std.ArrayList(*PluginCommandWrapper).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        // Clean up plugin wrappers
        for (self.plugin_wrappers.items) |wrapper| {
            wrapper.deinit();
        }
        self.plugin_wrappers.deinit();
        
        // Clean up legacy registry
        self.legacy_registry.deinit();
    }
    
    pub fn setLogger(self: *Self, logger: *core.LogContext) void {
        self.logger = logger;
        self.cli_plugin_manager.setLogger(logger);
    }
    
    /// Register legacy command
    pub fn registerLegacyCommand(self: *Self, command: *interfaces.CommandInterface) !void {
        try self.legacy_registry.register(command);
        
        if (self.logger) |log| {
            try log.info("Registered legacy command: {s}", .{command.name});
        }
    }
    
    /// Register all built-in legacy commands
    pub fn registerBuiltinLegacyCommands(self: *Self) !void {
        try registry.registerBuiltinCommands(&self.legacy_registry);
        
        if (self.logger) |log| {
            try log.info("Registered all legacy builtin commands", .{});
        }
    }
    
    /// Register all built-in legacy commands with logger
    pub fn registerBuiltinLegacyCommandsWithLogger(self: *Self, logger: *const core.LogContext) !void {
        try registry.registerBuiltinCommandsWithLogger(&self.legacy_registry, logger);
        
        if (self.logger) |log| {
            try log.info("Registered all legacy builtin commands with logger", .{});
        }
    }
    
    /// Load and register all CLI plugins
    pub fn loadCliPlugins(self: *Self) !void {
        // Initialize builtin CLI plugins
        try cli_plugins.initializeBuiltinCliPlugins(self.cli_plugin_registry);
        
        // Load plugins into manager
        try cli_plugins.loadCliPlugins(self.cli_plugin_registry, self.cli_plugin_manager);
        
        if (self.logger) |log| {
            try log.info("Loaded all CLI plugins", .{});
        }
    }
    
    /// Get command by name (checks both legacy and plugin commands)
    pub fn getCommand(self: *Self, name: []const u8) ?CommandLookupResult {
        // First check legacy commands
        if (self.legacy_registry.get(name)) |legacy_cmd| {
            return CommandLookupResult{ .legacy = legacy_cmd };
        }
        
        // Then check plugin commands
        if (self.cli_plugin_manager.findCommand(name)) |plugin_cmd| {
            return CommandLookupResult{ .plugin = plugin_cmd };
        }
        
        return null;
    }
    
    /// Execute command by name
    pub fn executeCommand(self: *Self, name: []const u8, args: []const []const u8) !void {
        if (self.getCommand(name)) |cmd_result| {
            switch (cmd_result) {
                .legacy => |legacy_cmd| {
                    // Convert args to RuntimeOptions for legacy commands
                    // This is a simplified conversion - in practice you'd need proper argument parsing
                    const options = types.RuntimeOptions{
                        .container_id = if (args.len > 0) args[0] else "default",
                        .debug = false,
                        .verbose = false,
                    };
                    try legacy_cmd.execute(options, self.allocator);
                },
                .plugin => |_| {
                    const result = try self.cli_plugin_manager.executeCommand(name, args, self.allocator);
                    if (result.exit_code != 0) {
                        if (result.message) |msg| {
                            std.log.err("Plugin command failed: {s}", .{msg});
                        }
                        return error.CommandFailed;
                    }
                },
            }
        } else {
            std.log.err("Command not found: {s}", .{name});
            return error.CommandNotFound;
        }
    }
    
    /// Get help for command
    pub fn getCommandHelp(self: *Self, name: []const u8) ![]const u8 {
        if (self.getCommand(name)) |cmd_result| {
            switch (cmd_result) {
                .legacy => |legacy_cmd| {
                    return legacy_cmd.help(self.allocator);
                },
                .plugin => |plugin_cmd| {
                    return plugin_cmd.generateHelp(self.allocator);
                },
            }
        } else {
            return error.CommandNotFound;
        }
    }
    
    /// List all available commands
    pub fn listAllCommands(self: *Self) ![]const []const u8 {
        var commands = std.ArrayList([]const u8).init(self.allocator);
        defer commands.deinit();
        
        // Add legacy commands
        const legacy_commands = try self.legacy_registry.list(self.allocator);
        defer self.allocator.free(legacy_commands);
        
        for (legacy_commands) |cmd| {
            try commands.append(self.allocator, try self.allocator.dupe(u8, cmd));
        }
        
        // Add plugin commands
        const plugin_commands = try self.cli_plugin_manager.getAllCommands(self.allocator);
        defer {
            for (plugin_commands) |cmd| {
                self.allocator.free(cmd);
            }
            self.allocator.free(plugin_commands);
        }
        
        for (plugin_commands) |cmd| {
            try commands.append(self.allocator, try self.allocator.dupe(u8, cmd));
        }
        
        return commands.toOwnedSlice(self.allocator);
    }
    
    /// Check if command exists
    pub fn hasCommand(self: *Self, name: []const u8) bool {
        return self.getCommand(name) != null;
    }
    
    /// Get command statistics
    pub fn getCommandStats(self: *Self) !CommandStats {
        const legacy_commands = try self.legacy_registry.list(self.allocator);
        defer self.allocator.free(legacy_commands);
        
        const plugin_commands = try self.cli_plugin_manager.getAllCommands(self.allocator);
        defer {
            for (plugin_commands) |cmd| {
                self.allocator.free(cmd);
            }
            self.allocator.free(plugin_commands);
        }
        
        const plugin_list = try self.cli_plugin_manager.listPlugins(self.allocator);
        defer {
            for (plugin_list) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(plugin_list);
        }
        
        return CommandStats{
            .total_commands = legacy_commands.len + plugin_commands.len,
            .legacy_commands = legacy_commands.len,
            .plugin_commands = plugin_commands.len,
            .loaded_plugins = plugin_list.len,
        };
    }
};

/// Command lookup result - either legacy or plugin command
pub const CommandLookupResult = union(enum) {
    legacy: *interfaces.CommandInterface,
    plugin: *const plugin.CliCommand,
};

/// Command statistics
pub const CommandStats = struct {
    total_commands: usize,
    legacy_commands: usize,
    plugin_commands: usize,
    loaded_plugins: usize,
};

/// Global enhanced registry instance
var global_enhanced_registry: ?EnhancedCommandRegistry = null;

/// Initialize the global enhanced command registry
pub fn initGlobalEnhancedRegistry(
    allocator: std.mem.Allocator,
    cli_plugin_manager: *plugin.CliPluginManager,
    cli_plugin_registry: *cli_plugins.CliPluginRegistry
) !void {
    global_enhanced_registry = EnhancedCommandRegistry.init(
        allocator,
        cli_plugin_manager,
        cli_plugin_registry
    );
}

/// Get the global enhanced command registry
pub fn getGlobalEnhancedRegistry() ?*EnhancedCommandRegistry {
    return if (global_enhanced_registry) |*reg| reg else null;
}

/// Deinitialize the global enhanced command registry
pub fn deinitGlobalEnhancedRegistry() void {
    if (global_enhanced_registry) |*reg| {
        reg.deinit();
        global_enhanced_registry = null;
    }
}

/// Test suite
const testing = std.testing;

test "enhanced registry basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_plugin_manager = plugin.CliPluginManager.init(allocator, &plugin_manager);
    defer cli_plugin_manager.deinit();
    
    // Create CLI plugin registry
    var cli_plugin_registry = cli_plugins.CliPluginRegistry.init(allocator);
    defer cli_plugin_registry.deinit();
    
    // Create enhanced registry
    var enhanced_registry = EnhancedCommandRegistry.init(
        allocator,
        &cli_plugin_manager,
        &cli_plugin_registry
    );
    defer enhanced_registry.deinit();
    
    // Test plugin loading
    try enhanced_registry.loadCliPlugins();
    
    // Test command statistics
    const stats = try enhanced_registry.getCommandStats();
    try testing.expect(stats.loaded_plugins > 0);
    try testing.expect(stats.plugin_commands > 0);
    
    // Test command lookup
    const has_stats = enhanced_registry.hasCommand("stats");
    try testing.expect(has_stats);
}

test "command lookup and execution" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create plugin manager
    var plugin_manager = plugin.PluginManager.init(allocator);
    defer plugin_manager.deinit();
    
    // Create CLI plugin manager
    var cli_plugin_manager = plugin.CliPluginManager.init(allocator, &plugin_manager);
    defer cli_plugin_manager.deinit();
    
    // Create CLI plugin registry
    var cli_plugin_registry = cli_plugins.CliPluginRegistry.init(allocator);
    defer cli_plugin_registry.deinit();
    
    // Create enhanced registry
    var enhanced_registry = EnhancedCommandRegistry.init(
        allocator,
        &cli_plugin_manager,
        &cli_plugin_registry
    );
    defer enhanced_registry.deinit();
    
    // Load plugins
    try enhanced_registry.loadCliPlugins();
    
    // Test command lookup
    const stats_cmd = enhanced_registry.getCommand("stats");
    try testing.expect(stats_cmd != null);
    try testing.expect(stats_cmd.? == .plugin);
    
    // Test non-existent command
    const missing_cmd = enhanced_registry.getCommand("nonexistent");
    try testing.expect(missing_cmd == null);
}