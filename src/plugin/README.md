# NexCage Plugin Development Guide

This guide provides comprehensive documentation for developing plugins for the NexCage container runtime system.

## Table of Contents

- [Overview](#overview)
- [Plugin Architecture](#plugin-architecture)
- [Getting Started](#getting-started)
- [Plugin Types](#plugin-types)
- [Core Components](#core-components)
- [Security and Capabilities](#security-and-capabilities)
- [Development Workflow](#development-workflow)
- [Examples](#examples)
- [Best Practices](#best-practices)
- [Testing](#testing)
- [Deployment](#deployment)

## Overview

NexCage uses a plugin-based architecture that allows developers to extend the container runtime with custom functionality. Plugins are secure, isolated, and capability-based components that can provide:

- **Backend implementations** (Docker, Podman, custom runtimes)
- **CLI commands** (custom subcommands and workflows)
- **Integrations** (monitoring, logging, external services)
- **Security extensions** (authentication, authorization, auditing)
- **Monitoring extensions** (metrics collection, alerting)

## Plugin Architecture

### Key Concepts

- **Plugin Metadata**: Describes plugin capabilities, dependencies, and resource requirements
- **Capabilities**: Permission-based access control for system resources
- **Security Sandbox**: Isolated execution environment for plugins
- **Hook System**: Event-driven plugin coordination
- **Plugin Context**: Runtime environment and communication interface

### Plugin Lifecycle

1. **Discovery**: Plugin manager scans for `.nexcage-plugin` files
2. **Validation**: Metadata and signatures are verified
3. **Loading**: Plugin is loaded into memory and dependencies resolved
4. **Initialization**: Plugin init hook is called with context
5. **Runtime**: Plugin responds to events and provides services
6. **Shutdown**: Plugin cleanup hooks are called before unloading

## Getting Started

### Prerequisites

- Zig 0.15.1 or later
- NexCage development environment
- Basic understanding of container runtimes

### Creating Your First Plugin

1. **Create plugin directory structure**:

```
my-plugin/
├── src/
│   ├── main.zig
│   └── plugin.zig
├── plugin.json
└── build.zig
```

2. **Define plugin metadata** (`plugin.json`):

```json
{
  "name": "my-example-plugin",
  "version": "1.0.0",
  "description": "Example plugin for NexCage",
  "author": "Your Name",
  "api_version": 1,
  "nexcage_version": "0.7.0",
  "capabilities": ["logging", "container_list"],
  "resource_requirements": {
    "max_memory_mb": 64,
    "max_cpu_percent": 5,
    "max_file_descriptors": 100
  }
}
```

3. **Implement plugin interface** (`src/plugin.zig`):

```zig
const std = @import("std");
const nexcage = @import("nexcage");
const plugin = nexcage.plugin;

// Plugin metadata
export const metadata = plugin.PluginMetadata{
    .name = "my-example-plugin",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Example plugin for NexCage",
    .api_version = 1,
    .nexcage_version = plugin.SemanticVersion{ .major = 0, .minor = 7, .patch = 0 },
    .capabilities = &[_]plugin.Capability{ .logging, .container_list },
    .resource_requirements = plugin.ResourceRequirements{
        .max_memory_mb = 64,
        .max_cpu_percent = 5,
    },
};

// Plugin hooks
export const hooks = plugin.PluginHooks{
    .init = pluginInit,
    .deinit = pluginDeinit,
    .health_check = pluginHealthCheck,
};

// Plugin extensions
export const extensions = plugin.PluginExtensions{
    .cli_commands = &[_]plugin.CLICommandExtension{
        .{
            .name = "hello",
            .description = "Say hello from plugin",
            .usage = "nexcage hello [name]",
            .execute = executeHello,
        },
    },
};

fn pluginInit(context: *plugin.PluginContext) !void {
    std.log.info("Plugin '{}' initialized", .{context.getPluginName()});
}

fn pluginDeinit(context: *plugin.PluginContext) void {
    std.log.info("Plugin '{}' shutting down", .{context.getPluginName()});
}

fn pluginHealthCheck(context: *plugin.PluginContext) !plugin.HealthStatus {
    _ = context;
    return .healthy;
}

fn executeHello(context: *plugin.PluginContext, args: []const []const u8, allocator: std.mem.Allocator) !void {
    _ = context;
    _ = allocator;

    const name = if (args.len > 1) args[1] else "World";
    std.log.info("Hello, {}!", .{name});
}
```

## Plugin Types

### Backend Extensions

Backend plugins implement container runtime functionality:

```zig
const backend_extension = plugin.BackendExtension{
    .name = "docker-backend",
    .description = "Docker container backend",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .create = dockerCreate,
    .start = dockerStart,
    .stop = dockerStop,
    .delete = dockerDelete,
    .list = dockerList,
    .info = dockerInfo,
    .exec = dockerExec,
};

fn dockerCreate(context: *plugin.PluginContext, container_id: []const u8) !void {
    // Implementation for creating containers
}

fn dockerStart(context: *plugin.PluginContext, container_id: []const u8) !void {
    // Implementation for starting containers
}
```

### CLI Command Extensions

Add custom CLI commands:

```zig
const cli_extension = plugin.CLICommandExtension{
    .name = "deploy",
    .description = "Deploy application containers",
    .usage = "nexcage deploy <app-config>",
    .examples = &[_][]const u8{
        "nexcage deploy app.yaml",
        "nexcage deploy --env production app.yaml",
    },
    .execute = executeDeploy,
    .help = showDeployHelp,
    .validate = validateDeployArgs,
};
```

### Integration Extensions

Connect with external services:

```zig
const integration_extension = plugin.IntegrationExtension{
    .name = "prometheus-metrics",
    .description = "Prometheus metrics integration",
    .version = plugin.SemanticVersion{ .major = 1, .minor = 0, .patch = 0 },
    .connect = prometheusConnect,
    .disconnect = prometheusDisconnect,
    .health_check = prometheusHealthCheck,
    .send_request = prometheusSendMetrics,
};
```

## Core Components

### Plugin Context

The plugin context provides access to the NexCage runtime:

```zig
fn useContext(context: *plugin.PluginContext) !void {
    const plugin_name = context.getPluginName();

    if (context.isValid()) {
        std.log.info("Plugin {} is running", .{plugin_name});
    }
}
```

### Hook System

Plugins can register for system events:

```zig
// Register for container lifecycle events
try hook_system.registerHook(
    "my-plugin",
    hooks.ContainerHooks.CONTAINER_CREATED,
    onContainerCreated,
    .normal,
    1000
);

fn onContainerCreated(context: *hooks.HookContext) !void {
    const container_id = context.getMetadata("container_id") orelse return;
    std.log.info("Container created: {}", .{container_id});
}
```

### Validation

Input validation is provided through the validation module:

```zig
const validation = @import("validation.zig");

fn validateInput(container_id: []const u8, command: []const []const u8) !void {
    try validation.validateContainerId(container_id);
    try validation.validateCommandArgs(command);
}
```

## Security and Capabilities

### Capability System

Plugins must declare required capabilities:

```zig
const capabilities = [_]plugin.Capability{
    .container_create,    // Can create containers
    .container_start,     // Can start containers
    .filesystem_read,     // Can read files
    .network_client,      // Can make network connections
    .logging,            // Can write logs
};
```

Available capabilities:

- **Filesystem**: `filesystem_read`, `filesystem_write`, `filesystem_execute`
- **Network**: `network_client`, `network_server`, `network_raw`
- **Process**: `process_spawn`, `process_signal`, `process_ptrace`
- **Container**: `container_create`, `container_start`, `container_stop`, `container_delete`, `container_exec`, `container_list`, `container_info`
- **Host**: `host_command`, `host_mount`, `host_device`
- **System**: `system_info`, `system_metrics`, `config_read`, `config_write`
- **Monitoring**: `logging`, `metrics`, `tracing`, `api_server`, `api_client`

### Resource Limits

Define resource requirements and limits:

```zig
const resource_requirements = plugin.ResourceRequirements{
    .max_memory_mb = 128,           // Maximum memory usage
    .max_cpu_percent = 10,          // Maximum CPU usage
    .max_file_descriptors = 200,    // Maximum open files
    .max_threads = 5,               // Maximum threads
    .timeout_seconds = 30,          // Operation timeout
    .max_network_connections = 10,   // Maximum network connections
    .max_disk_usage_mb = 50,        // Maximum disk usage
};
```

### Sandbox Configuration

Plugins run in secure sandboxes:

```zig
const sandbox_config = SandboxConfig{
    .enable_namespace_isolation = true,
    .enable_seccomp = true,
    .enable_cgroups = true,
    .network_isolation = .restricted,
    .filesystem_access = .read_only,
    .temp_dir = "/tmp/nexcage-plugins",
};
```

## Development Workflow

### 1. Development Setup

```bash
# Clone NexCage repository
git clone https://github.com/cageforge/nexcage.git
cd nexcage

# Create plugin workspace
mkdir plugins/my-plugin
cd plugins/my-plugin
```

### 2. Build Configuration

Create `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "my-plugin",
        .root_source_file = .{ .path = "src/plugin.zig" },
        .target = target,
        .optimize = optimize,
    });

    const nexcage_dep = b.dependency("nexcage", .{
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("nexcage", nexcage_dep.module("nexcage"));
    b.installArtifact(lib);
}
```

### 3. Testing

```bash
# Build plugin
zig build

# Test plugin
zig test src/plugin.zig

# Integration test with NexCage
./zig/zig test src/plugin/mod.zig
```

### 4. Packaging

Create plugin package:

```bash
# Create plugin bundle
tar -czf my-plugin-1.0.0.nexcage-plugin \
    lib/libmy-plugin.so \
    plugin.json \
    README.md
```

## Examples

### Simple Logging Plugin

```zig
const std = @import("std");
const plugin = @import("nexcage").plugin;

export const metadata = plugin.PluginMetadata{
    .name = "custom-logger",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Custom logging plugin",
    .capabilities = &[_]plugin.Capability{ .logging, .filesystem_write },
    .resource_requirements = .{ .max_memory_mb = 32 },
};

export const hooks = plugin.PluginHooks{
    .init = init,
    .deinit = deinit,
};

var log_file: ?std.fs.File = null;

fn init(context: *plugin.PluginContext) !void {
    log_file = try std.fs.cwd().createFile("plugin.log", .{});
    try log_file.?.writeAll("Logger plugin started\n");
}

fn deinit(context: *plugin.PluginContext) void {
    if (log_file) |file| {
        file.writeAll("Logger plugin stopped\n") catch {};
        file.close();
    }
}
```

### Container Backend Plugin

```zig
const std = @import("std");
const plugin = @import("nexcage").plugin;

export const metadata = plugin.PluginMetadata{
    .name = "custom-backend",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .description = "Custom container backend",
    .capabilities = &[_]plugin.Capability{
        .container_create, .container_start, .container_stop,
        .container_delete, .container_list, .host_command,
    },
    .resource_requirements = .{ .max_memory_mb = 256 },
};

export const extensions = plugin.PluginExtensions{
    .backend = &backend_extension,
};

const backend_extension = plugin.BackendExtension{
    .name = "custom",
    .description = "Custom container runtime",
    .version = .{ .major = 1, .minor = 0, .patch = 0 },
    .create = createContainer,
    .start = startContainer,
    .stop = stopContainer,
    .delete = deleteContainer,
    .list = listContainers,
    .info = getContainerInfo,
    .exec = execInContainer,
};

fn createContainer(context: *plugin.PluginContext, container_id: []const u8) !void {
    std.log.info("Creating container: {s}", .{container_id});
    // Implementation here
}

fn startContainer(context: *plugin.PluginContext, container_id: []const u8) !void {
    std.log.info("Starting container: {s}", .{container_id});
    // Implementation here
}

// ... other backend functions
```

## Best Practices

### Error Handling

- Always use Zig's error handling mechanisms
- Return appropriate error types for different failure modes
- Log errors with sufficient context for debugging

```zig
fn validateAndExecute(container_id: []const u8) !void {
    try validation.validateContainerId(container_id);

    executeOperation(container_id) catch |err| switch (err) {
        error.ContainerNotFound => {
            std.log.err("Container not found: {s}", .{container_id});
            return err;
        },
        error.PermissionDenied => {
            std.log.err("Permission denied for container: {s}", .{container_id});
            return err;
        },
        else => return err,
    };
}
```

### Memory Management

- Use proper allocator patterns
- Clean up resources in deinit hooks
- Avoid memory leaks in long-running plugins

```zig
fn allocateAndCleanup(allocator: std.mem.Allocator) !void {
    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    // Use data...
}
```

### Configuration

- Validate all configuration parameters
- Provide sensible defaults
- Document configuration options

```zig
const Config = struct {
    host: []const u8 = "localhost",
    port: u16 = 8080,
    timeout_ms: u32 = 5000,

    fn validate(self: Config) !void {
        if (self.port == 0) return error.InvalidPort;
        if (self.timeout_ms == 0) return error.InvalidTimeout;
    }
};
```

### Security

- Request only necessary capabilities
- Validate all external inputs
- Use secure communication protocols
- Follow principle of least privilege

```zig
// Good: Request only needed capabilities
const capabilities = [_]plugin.Capability{ .logging, .container_list };

// Bad: Request excessive capabilities
const capabilities = [_]plugin.Capability{
    .filesystem_write, .network_server, .host_command, .process_spawn
};
```

## Testing

### Unit Tests

```zig
const testing = std.testing;

test "plugin initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = try plugin.PluginContext.init(allocator, "test-plugin");
    defer context.deinit();

    try testing.expect(context.isValid());
}

test "capability checking" {
    const test_capabilities = [_]plugin.Capability{ .logging, .container_list };

    // Test capability validation
    try testing.expect(hasCapability(&test_capabilities, .logging));
    try testing.expect(!hasCapability(&test_capabilities, .filesystem_write));
}
```

### Integration Tests

```zig
test "plugin manager integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = plugin.PluginManagerConfig{
        .auto_load_plugins = false,
        .sandbox_enabled = false,
    };

    const manager = try plugin.PluginManager.init(allocator, config);
    defer manager.deinit();

    // Test plugin loading and execution
}
```

## Deployment

### Plugin Installation

1. **Copy plugin file to plugin directory**:

```bash
cp my-plugin.nexcage-plugin /etc/nexcage/plugins/
```

2. **Restart NexCage or reload plugins**:

```bash
nexcage plugin reload
```

3. **Verify plugin is loaded**:

```bash
nexcage plugin list
```

### Plugin Management Commands

```bash
# List all plugins
nexcage plugin list

# Show plugin information
nexcage plugin info my-plugin

# Enable/disable plugin
nexcage plugin enable my-plugin
nexcage plugin disable my-plugin

# Reload plugin
nexcage plugin reload my-plugin

# Plugin health check
nexcage plugin health my-plugin
```

### Configuration

Add plugin-specific configuration to `/etc/nexcage/config.yaml`:

```yaml
plugins:
  my-plugin:
    enabled: true
    config:
      host: "api.example.com"
      port: 8080
      api_key: "${MY_PLUGIN_API_KEY}"
```

### Monitoring

Monitor plugin health and performance:

```bash
# View plugin logs
nexcage logs --plugin my-plugin

# Monitor resource usage
nexcage plugin stats my-plugin

# Check security violations
nexcage plugin violations
```

## Troubleshooting

### Common Issues

1. **Plugin fails to load**:

   - Check metadata format and required fields
   - Verify capability declarations
   - Check dependency requirements

2. **Permission denied errors**:

   - Review capability requirements
   - Check sandbox configuration
   - Verify resource limits

3. **Memory leaks**:

   - Ensure proper cleanup in deinit hooks
   - Use defer statements for resource cleanup
   - Test with memory leak detection enabled

4. **Performance issues**:
   - Review resource requirements and limits
   - Profile plugin execution
   - Consider asynchronous operations

### Debug Mode

Enable debug logging for plugins:

```bash
NEXCAGE_LOG_LEVEL=debug nexcage --plugin-debug my-plugin
```

### Validation Tools

Use NexCage validation tools:

```bash
# Validate plugin metadata
nexcage plugin validate my-plugin.nexcage-plugin

# Test plugin in isolation
nexcage plugin test my-plugin

# Security audit
nexcage plugin audit my-plugin
```

## API Reference

For complete API documentation, see:

- [Plugin Core API](plugin.zig)
- [Plugin Manager API](manager.zig)
- [Hook System API](hooks.zig)
- [Security Sandbox API](sandbox.zig)
- [Validation API](validation.zig)

## Contributing

To contribute to the NexCage plugin system:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request
