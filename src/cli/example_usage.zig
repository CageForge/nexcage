/// CLI Integration Example Usage
/// 
/// This module demonstrates how to use the enhanced CLI system that integrates
/// both legacy commands and new plugin commands.

const std = @import("std");
const core = @import("core");
const cli = @import("mod.zig");
const plugin = @import("../plugin/mod.zig");
const cli_plugins = @import("../plugins/cli/mod.zig");

/// Example of setting up the complete CLI system
pub fn setupCompleteCliSystem(allocator: std.mem.Allocator, logger: ?*core.LogContext) !*cli.EnhancedCommandRegistry {
    // 1. Create core plugin manager
    var plugin_manager = try allocator.create(plugin.PluginManager);
    plugin_manager.* = plugin.PluginManager.init(allocator);
    
    // 2. Create CLI plugin manager
    var cli_plugin_manager = try allocator.create(plugin.CliPluginManager);
    cli_plugin_manager.* = plugin.CliPluginManager.init(allocator, plugin_manager);
    
    // 3. Create CLI plugin registry
    var cli_plugin_registry = try allocator.create(cli_plugins.CliPluginRegistry);
    cli_plugin_registry.* = cli_plugins.CliPluginRegistry.init(allocator);
    
    // 4. Create enhanced command registry
    var enhanced_registry = try allocator.create(cli.EnhancedCommandRegistry);
    enhanced_registry.* = cli.EnhancedCommandRegistry.init(
        allocator,
        cli_plugin_manager,
        cli_plugin_registry
    );
    
    // 5. Set up logging if available
    if (logger) |log| {
        enhanced_registry.setLogger(log);
    }
    
    // 6. Register legacy builtin commands
    if (logger) |log| {
        try enhanced_registry.registerBuiltinLegacyCommandsWithLogger(log);
    } else {
        try enhanced_registry.registerBuiltinLegacyCommands();
    }
    
    // 7. Load CLI plugins
    try enhanced_registry.loadCliPlugins();
    
    return enhanced_registry;
}

/// Example CLI command dispatcher
pub fn dispatchCommand(
    enhanced_registry: *cli.EnhancedCommandRegistry,
    command_line: []const []const u8,
    allocator: std.mem.Allocator
) !void {
    if (command_line.len == 0) {
        std.log.err("No command provided", .{});
        return;
    }
    
    const command_name = command_line[0];
    const args = if (command_line.len > 1) command_line[1..] else &[_][]const u8{};
    
    // Handle special commands
    if (std.mem.eql(u8, command_name, "help")) {
        try showHelp(enhanced_registry, args, allocator);
        return;
    }
    
    if (std.mem.eql(u8, command_name, "list-commands")) {
        try listAllCommands(enhanced_registry, allocator);
        return;
    }
    
    if (std.mem.eql(u8, command_name, "stats-commands")) {
        try showCommandStats(enhanced_registry);
        return;
    }
    
    // Execute the command
    enhanced_registry.executeCommand(command_name, args) catch |err| {
        switch (err) {
            error.CommandNotFound => {
                std.log.err("Command '{s}' not found. Use 'help' to see available commands.", .{command_name});
                try suggestSimilarCommands(enhanced_registry, command_name, allocator);
            },
            error.CommandFailed => {
                std.log.err("Command '{s}' failed to execute", .{command_name});
            },
            else => {
                std.log.err("Error executing command '{s}': {}", .{ command_name, err });
            },
        }
    };
}

/// Show help for a specific command or general help
fn showHelp(
    enhanced_registry: *cli.EnhancedCommandRegistry,
    args: []const []const u8,
    allocator: std.mem.Allocator
) !void {
    if (args.len > 0) {
        // Show help for specific command
        const command_name = args[0];
        const help_text = enhanced_registry.getCommandHelp(command_name) catch |err| {
            switch (err) {
                error.CommandNotFound => {
                    std.log.err("Command '{s}' not found", .{command_name});
                    return;
                },
                else => return err,
            }
        };
        defer allocator.free(help_text);
        
        std.debug.print("Help for '{s}':\n{s}\n", .{ command_name, help_text });
    } else {
        // Show general help
        try showGeneralHelp(enhanced_registry, allocator);
    }
}

/// Show general help with all available commands
fn showGeneralHelp(
    enhanced_registry: *cli.EnhancedCommandRegistry,
    allocator: std.mem.Allocator
) !void {
    const stats = try enhanced_registry.getCommandStats();
    
    std.debug.print("NexCage Container Runtime\n\n");
    std.debug.print("Usage: nexcage <command> [options] [arguments]\n\n");
    std.debug.print("Available Commands ({d} total):\n\n", .{stats.total_commands});
    
    const all_commands = try enhanced_registry.listAllCommands();
    defer {
        for (all_commands) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(all_commands);
    }
    
    // Group commands by type (heuristic based on name)
    var container_commands = std.ArrayList([]const u8).empty;
    var plugin_commands = std.ArrayList([]const u8).empty;
    var system_commands = std.ArrayList([]const u8).empty;
    
    defer container_commands.deinit(allocator);
    defer plugin_commands.deinit(allocator);
    defer system_commands.deinit(allocator);
    
    for (all_commands) |cmd| {
        if (std.mem.indexOf(u8, cmd, " ") != null or 
            std.mem.eql(u8, cmd, "stats") or 
            std.mem.eql(u8, cmd, "logs") or 
            std.mem.eql(u8, cmd, "network")) {
            try plugin_commands.append(allocator, cmd);
        } else if (std.mem.eql(u8, cmd, "create") or 
                   std.mem.eql(u8, cmd, "start") or 
                   std.mem.eql(u8, cmd, "stop") or 
                   std.mem.eql(u8, cmd, "delete") or 
                   std.mem.eql(u8, cmd, "list") or 
                   std.mem.eql(u8, cmd, "run")) {
            try container_commands.append(allocator, cmd);
        } else {
            try system_commands.append(allocator, cmd);
        }
    }
    
    if (container_commands.items.len > 0) {
        std.debug.print("Container Management:\n");
        for (container_commands.items) |cmd| {
            std.debug.print("  {s}\n", .{cmd});
        }
        std.debug.print("\n");
    }
    
    if (plugin_commands.items.len > 0) {
        std.debug.print("Plugin Commands:\n");
        for (plugin_commands.items) |cmd| {
            std.debug.print("  {s}\n", .{cmd});
        }
        std.debug.print("\n");
    }
    
    if (system_commands.items.len > 0) {
        std.debug.print("System Commands:\n");
        for (system_commands.items) |cmd| {
            std.debug.print("  {s}\n", .{cmd});
        }
        std.debug.print("\n");
    }
    
    std.debug.print("Statistics:\n");
    std.debug.print("  Legacy commands: {d}\n", .{stats.legacy_commands});
    std.debug.print("  Plugin commands: {d}\n", .{stats.plugin_commands});
    std.debug.print("  Loaded plugins: {d}\n", .{stats.loaded_plugins});
    std.debug.print("\nUse 'nexcage help <command>' for detailed help on a specific command.\n");
}

/// List all available commands
fn listAllCommands(
    enhanced_registry: *cli.EnhancedCommandRegistry,
    allocator: std.mem.Allocator
) !void {
    const all_commands = try enhanced_registry.listAllCommands();
    defer {
        for (all_commands) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(all_commands);
    }
    
    std.debug.print("All available commands:\n");
    for (all_commands) |cmd| {
        // Determine command type
        const cmd_type = if (enhanced_registry.getCommand(cmd)) |result| 
            switch (result) {
                .legacy => "legacy",
                .plugin => "plugin",
            }
        else 
            "unknown";
            
        std.debug.print("  {s} ({s})\n", .{ cmd, cmd_type });
    }
}

/// Show command statistics
fn showCommandStats(enhanced_registry: *cli.EnhancedCommandRegistry) !void {
    const stats = try enhanced_registry.getCommandStats();
    
    std.debug.print("Command Statistics:\n");
    std.debug.print("  Total commands: {d}\n", .{stats.total_commands});
    std.debug.print("  Legacy commands: {d}\n", .{stats.legacy_commands});
    std.debug.print("  Plugin commands: {d}\n", .{stats.plugin_commands});
    std.debug.print("  Loaded plugins: {d}\n", .{stats.loaded_plugins});
    
    // Calculate percentages
    if (stats.total_commands > 0) {
        const legacy_percent = (stats.legacy_commands * 100) / stats.total_commands;
        const plugin_percent = (stats.plugin_commands * 100) / stats.total_commands;
        std.debug.print("  Legacy commands: {d}%\n", .{legacy_percent});
        std.debug.print("  Plugin commands: {d}%\n", .{plugin_percent});
    }
}

/// Suggest similar commands when a command is not found
fn suggestSimilarCommands(
    enhanced_registry: *cli.EnhancedCommandRegistry,
    command_name: []const u8,
    allocator: std.mem.Allocator
) !void {
    const all_commands = try enhanced_registry.listAllCommands();
    defer {
        for (all_commands) |cmd| {
            allocator.free(cmd);
        }
        allocator.free(all_commands);
    }
    
    var suggestions = std.ArrayList([]const u8).empty;
    defer suggestions.deinit(allocator);
    
    // Simple similarity check - commands that start with the same letter(s)
    for (all_commands) |cmd| {
        if (cmd.len > 0 and command_name.len > 0) {
            if (cmd[0] == command_name[0]) {
                try suggestions.append(allocator, cmd);
            }
        }
    }
    
    if (suggestions.items.len > 0) {
        std.debug.print("\nDid you mean:\n");
        for (suggestions.items) |suggestion| {
            std.debug.print("  {s}\n", .{suggestion});
        }
    }
}

/// Example main function showing complete CLI setup and usage
pub fn exampleMain(allocator: std.mem.Allocator) !void {
    // Create logger (optional)
    var logger = core.LogContext.init(allocator, .info);
    defer logger.deinit();
    
    // Set up complete CLI system
    var enhanced_registry = try setupCompleteCliSystem(allocator, &logger);
    defer {
        enhanced_registry.deinit();
        allocator.destroy(enhanced_registry);
    }
    
    // Example command executions
    std.log.info("=== CLI Integration Example ===");
    
    // Show command statistics
    try showCommandStats(enhanced_registry);
    
    // List all commands
    std.log.info("\nListing all commands:");
    try listAllCommands(enhanced_registry, allocator);
    
    // Example command executions (these would fail without actual containers)
    const example_commands = [_][]const []const u8{
        &[_][]const u8{ "help" },
        &[_][]const u8{ "list-commands" },
        &[_][]const u8{ "stats-commands" },
        &[_][]const u8{ "help", "stats" },
    };
    
    for (example_commands) |cmd_line| {
        std.log.info("\nExecuting: {s}", .{std.mem.join(allocator, " ", cmd_line) catch "command"});
        try dispatchCommand(enhanced_registry, cmd_line, allocator);
    }
    
    std.log.info("\n=== CLI Integration Example Complete ===");
}

/// Test suite
const testing = std.testing;

test "CLI integration example setup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var enhanced_registry = try setupCompleteCliSystem(allocator, null);
    defer {
        enhanced_registry.deinit();
        allocator.destroy(enhanced_registry);
    }
    
    // Test that system is properly set up
    const stats = try enhanced_registry.getCommandStats();
    try testing.expect(stats.total_commands > 0);
    try testing.expect(stats.loaded_plugins > 0);
}

test "CLI command dispatch" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var enhanced_registry = try setupCompleteCliSystem(allocator, null);
    defer {
        enhanced_registry.deinit();
        allocator.destroy(enhanced_registry);
    }
    
    // Test help commands (these should work)
    try dispatchCommand(enhanced_registry, &[_][]const u8{"help"}, allocator);
    try dispatchCommand(enhanced_registry, &[_][]const u8{"list-commands"}, allocator);
    try dispatchCommand(enhanced_registry, &[_][]const u8{"stats-commands"}, allocator);
}