/// Stats CLI Plugin
/// 
/// This plugin provides container statistics and monitoring commands.

const std = @import("std");
const plugin = @import("../../../plugin/mod.zig");
const cli_extension = @import("../../../plugin/cli_extension.zig");

/// Stats command implementation
fn statsCommand(context: *cli_extension.CliContext) !cli_extension.CliResult {
    const container_name = context.getArgument("container");
    const format = context.getOption("format") orelse "table";
    const follow = context.hasFlag("follow");
    
    try context.logInfo("Getting stats for container: {s}", .{container_name.?});
    try context.logInfo("Output format: {s}", .{format});
    try context.logInfo("Follow mode: {}", .{follow});
    
    // Mock stats output
    const stats_output = 
        \\Container: test-container
        \\CPU Usage: 25.3%
        \\Memory Usage: 512MB / 2GB (25.0%)
        \\Network I/O: 1.2MB in / 800KB out
        \\Disk I/O: 50MB read / 25MB write
        \\Processes: 15
        \\Uptime: 2h 30m
    ;
    
    std.debug.print("{s}\n", .{stats_output});
    
    return cli_extension.CliResult.success();
}

/// Top command implementation (container process listing)
fn topCommand(context: *cli_extension.CliContext) !cli_extension.CliResult {
    const container_name = context.getArgument("container");
    const sort_by = context.getOption("sort") orelse "cpu";
    
    try context.logInfo("Listing processes for container: {s}", .{container_name.?});
    try context.logInfo("Sorted by: {s}", .{sort_by});
    
    // Mock process listing
    const top_output = 
        \\PID    PPID   CPU%   MEM%   COMMAND
        \\1      0      5.2    2.1    /bin/sh
        \\25     1      15.3   8.4    nginx: master process
        \\26     25     3.1    1.2    nginx: worker process
        \\27     25     2.8    1.1    nginx: worker process
        \\45     1      1.5    0.8    /usr/bin/cron
    ;
    
    std.debug.print("{s}\n", .{top_output});
    
    return cli_extension.CliResult.success();
}

/// Events command implementation
fn eventsCommand(context: *cli_extension.CliContext) !cli_extension.CliResult {
    const container_name = context.getArgument("container");
    const follow = context.hasFlag("follow");
    const since = context.getOption("since");
    
    try context.logInfo("Getting events for container: {s}", .{container_name.?});
    try context.logInfo("Follow mode: {}", .{follow});
    if (since) |s| {
        try context.logInfo("Since: {s}", .{s});
    }
    
    // Mock events output
    const events_output = 
        \\2024-01-15T10:30:00Z container create test-container
        \\2024-01-15T10:30:01Z container start test-container
        \\2024-01-15T10:35:12Z container exec test-container
        \\2024-01-15T10:40:25Z container network attach test-container
    ;
    
    std.debug.print("{s}\n", .{events_output});
    
    return cli_extension.CliResult.success();
}

/// Register commands provided by this plugin
fn registerCommands(
    allocator: std.mem.Allocator,
    plugin_context: *plugin.PluginContext
) ![]cli_extension.CliCommand {
    _ = plugin_context;
    
    const commands = try allocator.alloc(cli_extension.CliCommand, 1);
    
    // Main stats command with subcommands
    commands[0] = cli_extension.CliCommand{
        .name = "stats",
        .description = "Container statistics and monitoring",
        .usage = "nexcage stats [subcommand] [options] <container>",
        .subcommands = &[_]cli_extension.CliCommand{
            cli_extension.CliCommand{
                .name = "show",
                .description = "Show container resource usage statistics",
                .usage = "nexcage stats show [options] <container>",
                .arguments = &[_]cli_extension.CliArgument{
                    cli_extension.CliArgument{
                        .name = "container",
                        .description = "Container name or ID",
                        .required = true,
                    },
                },
                .options = &[_]cli_extension.CliOption{
                    cli_extension.CliOption{
                        .name = "format",
                        .short = 'f',
                        .description = "Output format (table, json, yaml)",
                        .option_type = .string,
                    },
                    cli_extension.CliOption{
                        .name = "follow",
                        .description = "Follow stats output continuously",
                        .option_type = .flag,
                        .has_value = false,
                    },
                },
                .execute_fn = statsCommand,
            },
            cli_extension.CliCommand{
                .name = "top",
                .description = "Display running processes in container",
                .usage = "nexcage stats top [options] <container>",
                .arguments = &[_]cli_extension.CliArgument{
                    cli_extension.CliArgument{
                        .name = "container",
                        .description = "Container name or ID",
                        .required = true,
                    },
                },
                .options = &[_]cli_extension.CliOption{
                    cli_extension.CliOption{
                        .name = "sort",
                        .short = 's',
                        .description = "Sort by field (cpu, memory, pid)",
                        .option_type = .string,
                    },
                },
                .execute_fn = topCommand,
            },
            cli_extension.CliCommand{
                .name = "events",
                .description = "Show container events",
                .usage = "nexcage stats events [options] <container>",
                .arguments = &[_]cli_extension.CliArgument{
                    cli_extension.CliArgument{
                        .name = "container",
                        .description = "Container name or ID",
                        .required = true,
                    },
                },
                .options = &[_]cli_extension.CliOption{
                    cli_extension.CliOption{
                        .name = "follow",
                        .short = 'f',
                        .description = "Follow events continuously",
                        .option_type = .flag,
                        .has_value = false,
                    },
                    cli_extension.CliOption{
                        .name = "since",
                        .description = "Show events since timestamp",
                        .option_type = .string,
                    },
                },
                .execute_fn = eventsCommand,
            },
        },
    };
    
    return commands;
}

/// Cleanup resources
fn cleanup(allocator: std.mem.Allocator, commands: []cli_extension.CliCommand) void {
    allocator.free(commands);
}

/// Get plugin metadata
fn getMetadata() plugin.PluginMetadata {
    return plugin.PluginMetadata{
        .name = "stats-cli-plugin",
        .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
        .description = "Container statistics and monitoring CLI commands",
        .api_version = 1,
        .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
        .dependencies = &[_][]const u8{},
        .capabilities = &[_]plugin.Capability{
            .container_list, .container_info, .system_info, 
            .system_metrics, .logging,
        },
        .resource_requirements = plugin.ResourceRequirements{
            .max_memory_mb = 64,
            .max_cpu_percent = 5,
        },
        .provides_cli_commands = true,
        .provides_backend = false,
        .provides_integrations = false,
        .provides_monitoring = true,
    };
}

/// Initialize plugin
fn initPlugin(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) !void {
    _ = allocator;
    _ = plugin_context;
    // Initialization logic if needed
}

/// Deinitialize plugin
fn deinitPlugin(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) void {
    _ = allocator;
    _ = plugin_context;
    // Cleanup logic if needed
}

/// Export the CLI extension interface
pub const extension = cli_extension.CliExtension{
    .register_commands_fn = registerCommands,
    .cleanup_fn = cleanup,
    .get_metadata_fn = getMetadata,
    .init_fn = initPlugin,
    .deinit_fn = deinitPlugin,
};

/// Export plugin metadata for registration
pub const metadata = getMetadata();