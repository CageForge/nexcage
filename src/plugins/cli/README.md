# NexCage CLI Plugins

This directory contains CLI plugins that extend NexCage's command-line interface with additional functionality.

## Overview

The CLI plugin system allows extending NexCage with new commands and subcommands without modifying the core CLI code. Plugins provide a clean, modular way to add specialized functionality like advanced monitoring, debugging, and management tools.

## Available CLI Plugins

### 1. Stats Plugin (`stats-plugin/`)
**Commands**: `nexcage stats`
**Description**: Container statistics and monitoring commands
**Capabilities**: 
- `stats show` - Display container resource usage statistics
- `stats top` - Show running processes in container  
- `stats events` - Display container events

**Examples**:
```bash
# Show container stats
nexcage stats show --format=json --follow test-container

# List container processes
nexcage stats top --sort=cpu test-container

# Follow container events
nexcage stats events --follow --since=1h test-container
```

### 2. Logs Plugin (`logs-plugin/`)
**Commands**: `nexcage logs`
**Description**: Advanced logging and debugging commands
**Capabilities**:
- `logs show` - Show container logs with advanced filtering
- `logs debug` - Display debug information for troubleshooting
- `logs trace` - Trace container system calls

**Examples**:
```bash
# Show logs with filtering
nexcage logs show --follow --tail=100 --level=error test-container

# Debug container issues
nexcage logs debug --component=network --verbose test-container

# Trace system calls
nexcage logs trace --syscalls --duration=30 test-container
```

### 3. Network Plugin (`network-plugin/`)
**Commands**: `nexcage network`
**Description**: Network management and troubleshooting commands
**Capabilities**:
- `network inspect` - Inspect container network configuration
- `network connect` - Connect container to network
- `network disconnect` - Disconnect container from network
- `network troubleshoot` - Troubleshoot network issues

**Examples**:
```bash
# Inspect network configuration
nexcage network inspect --format=yaml test-container

# Connect to network
nexcage network connect --ip=192.168.1.100 test-container my-network

# Troubleshoot connectivity
nexcage network troubleshoot --target=google.com --dns test-container
```

## Plugin Architecture

### CLI Extension Interface

Each CLI plugin implements the `CliExtension` interface:

```zig
pub const CliExtension = struct {
    register_commands_fn: *const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) anyerror![]CliCommand,
    cleanup_fn: ?*const fn(allocator: std.mem.Allocator, commands: []CliCommand) void = null,
    get_metadata_fn: *const fn() plugin.PluginMetadata,
    init_fn: ?*const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) anyerror!void = null,
    deinit_fn: ?*const fn(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) void = null,
};
```

### Command Structure

Commands are defined using the `CliCommand` structure:

```zig
pub const CliCommand = struct {
    name: []const u8,
    description: []const u8,
    usage: []const u8,
    arguments: []const CliArgument = &[_]CliArgument{},
    options: []const CliOption = &[_]CliOption{},
    subcommands: []const CliCommand = &[_]CliCommand{},
    execute_fn: ?*const fn(*CliContext) anyerror!CliResult = null,
};
```

### Plugin Context

Each CLI plugin receives a `CliContext` with parsed arguments and options:

```zig
pub const CliContext = struct {
    allocator: std.mem.Allocator,
    logger: ?*core.LogContext = null,
    arguments: std.StringHashMap([]const u8),
    options: std.StringHashMap([]const u8),
    plugin_context: *plugin.PluginContext,
};
```

## Development Guide

### Creating a New CLI Plugin

1. **Create plugin directory**:
   ```bash
   mkdir src/plugins/cli/my-plugin
   ```

2. **Implement plugin.zig**:
   ```zig
   const std = @import("std");
   const plugin = @import("../../../plugin/mod.zig");
   const cli_extension = @import("../../../plugin/cli_extension.zig");
   
   // Implement command functions
   fn myCommand(context: *cli_extension.CliContext) !cli_extension.CliResult {
       // Command implementation
       return cli_extension.CliResult.success();
   }
   
   // Register commands
   fn registerCommands(allocator: std.mem.Allocator, plugin_context: *plugin.PluginContext) ![]cli_extension.CliCommand {
       // Return array of commands
   }
   
   // Export extension
   pub const extension = cli_extension.CliExtension{
       .register_commands_fn = registerCommands,
       .get_metadata_fn = getMetadata,
   };
   ```

3. **Register in mod.zig**:
   ```zig
   pub const my_plugin = @import("my-plugin/plugin.zig");
   
   pub fn initializeBuiltinCliPlugins(registry: *CliPluginRegistry) !void {
       // Add your plugin registration
       try registry.registerPlugin(
           "my-plugin",
           "Description of my plugin",
           &my_plugin.extension
       );
   }
   ```

### Command Implementation Best Practices

1. **Argument Validation**:
   ```zig
   fn myCommand(context: *cli_extension.CliContext) !cli_extension.CliResult {
       const container_name = context.getArgument("container") orelse {
           return cli_extension.CliResult.failure(1, "Container name required");
       };
       
       // Continue with implementation
   }
   ```

2. **Logging**:
   ```zig
   try context.logInfo("Processing container: {s}", .{container_name});
   try context.logWarn("High memory usage detected");
   try context.logError("Operation failed: {s}", .{error_message});
   ```

3. **Option Handling**:
   ```zig
   const format = context.getOption("format") orelse "table";
   const verbose = context.hasFlag("verbose");
   const timeout = if (context.getOption("timeout")) |t| 
       std.fmt.parseInt(u32, t, 10) catch 30 
   else 30;
   ```

4. **Error Handling**:
   ```zig
   return switch (result) {
       .success => cli_extension.CliResult.success(),
       .error => |err| cli_extension.CliResult.failure(1, try std.fmt.allocPrint(
           context.allocator, "Operation failed: {}", .{err}
       )),
   };
   ```

## Security and Capabilities

CLI plugins operate within the same security model as other plugins:

- **Capability-based Access Control**: Only declared capabilities are allowed
- **Resource Limits**: Memory, CPU, and execution time limits
- **Input Validation**: All command arguments and options are validated
- **Sandbox Isolation**: Plugins run in isolated contexts

### Required Capabilities

Common capabilities for CLI plugins:

- `logging` - Required for all plugins
- `container_info` - Access container information
- `container_list` - List containers
- `system_info` - Access system information
- `network_client` - Network connectivity for troubleshooting
- `host_command` - Execute host commands (with restrictions)

## Integration with Main CLI

The CLI plugin system integrates seamlessly with NexCage's main CLI:

1. **Plugin Discovery**: Automatically discovers and loads enabled CLI plugins
2. **Command Registration**: Registers plugin commands with the main CLI router
3. **Help Integration**: Plugin commands appear in help output
4. **Argument Parsing**: Unified argument parsing for all commands
5. **Error Handling**: Consistent error handling and reporting

## Configuration

CLI plugins can be enabled/disabled through configuration:

```yaml
plugins:
  cli:
    stats:
      enabled: true
    logs:
      enabled: true
    network:
      enabled: false
```

## Performance Considerations

- **Lazy Loading**: CLI plugins are only loaded when their commands are used
- **Resource Limits**: Each plugin has memory and CPU limits
- **Caching**: Command metadata is cached for performance
- **Parallel Loading**: Multiple plugins can be loaded concurrently

## Testing

Each CLI plugin includes comprehensive tests:

- **Unit Tests**: Test individual command functions
- **Integration Tests**: Test plugin registration and loading
- **Argument Parsing Tests**: Verify command line parsing
- **Help Generation Tests**: Ensure help text is generated correctly

Run tests for individual plugins:

```bash
# Test individual plugin (when import paths are resolved)
zig test src/plugins/cli/stats-plugin/plugin.zig
zig test src/plugins/cli/logs-plugin/plugin.zig
zig test src/plugins/cli/network-plugin/plugin.zig
```

## Future Enhancements

### Planned CLI Plugins

1. **Image Plugin**: Container image management commands
2. **Volume Plugin**: Volume and storage management
3. **Config Plugin**: Configuration management tools
4. **Security Plugin**: Security scanning and compliance
5. **Deploy Plugin**: Deployment and orchestration helpers

### Plugin Features

- **Auto-completion**: Shell completion for plugin commands
- **Command Aliases**: Short aliases for frequently used commands
- **Interactive Mode**: Interactive command execution
- **Plugin Updates**: Dynamic plugin installation and updates
- **Plugin Marketplace**: Central repository for community plugins

## Contributing

To contribute a new CLI plugin:

1. Follow the development guide above
2. Include comprehensive tests
3. Add documentation and examples
4. Ensure security best practices
5. Submit a pull request with your plugin

## Troubleshooting

### Common Issues

1. **Command Not Found**: Ensure plugin is enabled and loaded
2. **Permission Denied**: Check plugin capabilities
3. **Import Errors**: Verify import paths in plugin code
4. **Memory Limits**: Check plugin resource requirements

### Debug Mode

Enable debug logging for CLI plugins:

```bash
NEXCAGE_DEBUG=cli nexcage stats show test-container
```

This will show detailed information about plugin loading, command parsing, and execution.