# Modular Architecture Guide

## Overview

Nexcage v0.4.0 introduces a modular architecture that follows SOLID principles, providing clean separation of concerns and extensibility.

## Architecture Principles

### SOLID Principles

1. **Single Responsibility Principle (SRP)**: Each module has a single, well-defined responsibility
2. **Open/Closed Principle (OCP)**: Modules are open for extension but closed for modification
3. **Liskov Substitution Principle (LSP)**: Backends and integrations are interchangeable through common interfaces
4. **Interface Segregation Principle (ISP)**: Interfaces are focused and specific
5. **Dependency Inversion Principle (DIP)**: Core depends on abstractions, not concrete implementations

## Module Structure

```
src/
├── core/           # System core (required modules)
│   ├── config.zig      # Global configuration
│   ├── errors.zig      # Error handling system
│   ├── logging.zig     # Structured logging
│   ├── interfaces.zig  # Common interfaces
│   └── types.zig       # Global types and structures
├── backends/       # Backend implementations
│   ├── lxc/            # LXC backend
│   ├── proxmox-lxc/    # Proxmox LXC backend
│   ├── proxmox-vm/     # Proxmox VM backend
│   └── crun/           # Crun OCI backend
├── integrations/   # External system integrations
│   ├── proxmox-api/    # Proxmox API client
│   ├── zfs/            # ZFS integration
│   └── bfc/            # BFC integration
├── cli/            # Command-line interface
│   ├── run.zig         # Run command
│   ├── help.zig        # Help command
│   ├── version.zig     # Version command
│   └── registry.zig    # Command registry
├── utils/          # Utility modules
│   ├── fs.zig          # File system utilities
│   └── net.zig         # Network utilities
└── main_modular.zig    # Modular entry point
```

## Core Module

The core module provides the foundation for all other modules:

### Configuration Management
```zig
const core = @import("core");

// Initialize configuration loader
var config_loader = core.ConfigLoader.init(allocator);
const config = try config_loader.loadDefault();

// Access configuration
std.debug.print("Runtime type: {}\n", .{config.runtime_type});
```

### Logging System
```zig
// Initialize logger
var logger = core.LogContext.init(allocator, std.io.getStdErr().writer(), core.LogLevel.info, "my-app");
defer logger.deinit();

// Log messages
try logger.info("Application started", .{});
try logger.@"error"("Operation failed: {}", .{error});
```

### Error Handling
```zig
// Use core error types
return core.Error.InvalidInput;
return core.Error.RuntimeError;
```

## Backend Modules

Backends implement the container runtime interfaces defined in `core/interfaces.zig`.

### LXC Backend
```zig
const backends = @import("backends");

// Initialize LXC backend
const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
defer lxc_driver.deinit();

// Create container
try lxc_driver.create(sandbox_config);

// Start container
try lxc_driver.start("container-id");

// Stop container
try lxc_driver.stop("container-id");
```

### Proxmox LXC Backend
```zig
// Initialize Proxmox LXC backend
const proxmox_config = core.types.ProxmoxLxcBackendConfig{
    .allocator = allocator,
    .host = "proxmox.example.com",
    .port = 8006,
    .username = "user@pam",
    .password = "password",
    .realm = "pam",
    .verify_ssl = false,
};

const proxmox_lxc = try backends.proxmox_lxc.ProxmoxLxcDriver.init(allocator, proxmox_config);
defer proxmox_lxc.deinit();

// Create LXC container via Proxmox API
const lxc_config = core.types.ProxmoxLxcConfig{
    .allocator = allocator,
    .vmid = 100,
    .hostname = "test-container",
    .memory = 512,
    .cores = 1,
    .rootfs = "local-lvm:8",
};

try proxmox_lxc.createContainer(lxc_config);
```

## CLI Module

The CLI module provides a registry-based command system:

### Command Registration
```zig
const cli = @import("cli");

// Initialize command registry
var registry = cli.CommandRegistry.init(allocator);
defer registry.deinit();

// Register built-in commands
try cli.registerBuiltinCommands(&registry);

// List available commands
const commands = try registry.list(allocator);
defer allocator.free(commands);
```

### Custom Commands
```zig
// Create custom command
const MyCommand = struct {
    const Self = @This();
    
    name: []const u8 = "mycommand",
    description: []const u8 = "My custom command",
    
    pub fn execute(self: *Self, options: core.types.RuntimeOptions, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = allocator;
        
        std.debug.print("Executing custom command\n", .{});
    }
};

// Register custom command
const my_cmd = try registry.allocator.alloc(MyCommand, 1);
my_cmd[0] = MyCommand{};
try registry.register(@ptrCast(&my_cmd[0]));
```

## Integration Modules

Integration modules provide external system connectivity:

### Proxmox API Integration
```zig
const integrations = @import("integrations");

// Initialize Proxmox API client
const api_config = core.types.ProxmoxApiConfig{
    .allocator = allocator,
    .host = "proxmox.example.com",
    .port = 8006,
    .token = "user@pam!tokenid=tokenvalue",
    .node = "node1",
};

const api_client = try integrations.proxmox_api.ProxmoxApiClient.init(allocator, api_config);
defer api_client.deinit();

// Make API requests
const response = try api_client.makeRequest(.GET, "/api2/json/cluster/status");
```

### ZFS Integration
```zig
// Initialize ZFS client
const zfs_client = try integrations.zfs.ZfsClient.init(allocator);
defer zfs_client.deinit();

// Create ZFS dataset
try zfs_client.createDataset("tank/containers", .{});

// Create snapshot
try zfs_client.createSnapshot("tank/containers@backup");
```

## Usage Examples

### Basic Container Management
```zig
const std = @import("std");
const core = @import("core");
const backends = @import("backends");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    var logger = core.LogContext.init(allocator, std.io.getStdErr().writer(), core.LogLevel.info, "container-manager");
    defer logger.deinit();

    // Initialize LXC backend
    const sandbox_config = core.types.SandboxConfig{
        .allocator = allocator,
        .name = try allocator.dupe(u8, "my-container"),
        .runtime_type = .lxc,
    };

    const lxc_driver = try backends.lxc.LxcDriver.init(allocator, sandbox_config);
    defer lxc_driver.deinit();

    // Set logger
    lxc_driver.setLogger(&logger);

    // Create container
    try lxc_driver.create(sandbox_config);
    try logger.info("Container created successfully", .{});

    // Start container
    try lxc_driver.start("my-container");
    try logger.info("Container started successfully", .{});

    // Get container info
    const info = try lxc_driver.info("my-container", allocator);
    try logger.info("Container state: {}", .{info.state});

    // Stop container
    try lxc_driver.stop("my-container");
    try logger.info("Container stopped successfully", .{});
}
```

### Proxmox Integration
```zig
const std = @import("std");
const core = @import("core");
const backends = @import("backends");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Proxmox LXC backend
    const proxmox_config = core.types.ProxmoxLxcBackendConfig{
        .allocator = allocator,
        .host = try allocator.dupe(u8, "proxmox.example.com"),
        .port = 8006,
        .username = try allocator.dupe(u8, "user@pam"),
        .password = try allocator.dupe(u8, "password"),
        .realm = try allocator.dupe(u8, "pam"),
        .verify_ssl = false,
    };

    const proxmox_lxc = try backends.proxmox_lxc.ProxmoxLxcDriver.init(allocator, proxmox_config);
    defer proxmox_lxc.deinit();

    // Create LXC container
    const lxc_config = core.types.ProxmoxLxcConfig{
        .allocator = allocator,
        .vmid = 100,
        .hostname = try allocator.dupe(u8, "proxmox-container"),
        .memory = 1024,
        .cores = 2,
        .rootfs = try allocator.dupe(u8, "local-lvm:10"),
        .net0 = try allocator.dupe(u8, "bridge=vmbr0"),
        .ostemplate = try allocator.dupe(u8, "local:vztmpl/ubuntu-20.04-standard_20.04-1_amd64.tar.zst"),
    };

    try proxmox_lxc.createContainer(lxc_config);
    std.debug.print("Proxmox LXC container created successfully\n", .{});

    // Start container
    try proxmox_lxc.startContainer(100);
    std.debug.print("Container started successfully\n", .{});

    // Get container info
    const info = try proxmox_lxc.getContainerInfo(100);
    if (info) |container_info| {
        std.debug.print("Container info: VMID={d}, Status={s}\n", .{ container_info.vmid, container_info.status });
    }
}
```

## Best Practices

### Memory Management
- Always use the provided allocator
- Free allocated memory properly
- Use defer statements for cleanup

### Error Handling
- Use core error types consistently
- Provide meaningful error messages
- Handle errors gracefully

### Logging
- Use structured logging with appropriate levels
- Include context in log messages
- Avoid logging sensitive information

### Module Design
- Keep modules focused and cohesive
- Minimize dependencies between modules
- Use interfaces for loose coupling

## Migration from Legacy

The modular architecture is designed to be backward compatible. To migrate from the legacy version:

1. Update imports to use modular paths
2. Use the new configuration system
3. Leverage the new logging system
4. Take advantage of the registry-based CLI

## Performance Considerations

- Modules are loaded on-demand
- Memory usage is optimized through proper allocation patterns
- Command execution is streamlined through the registry system
- Backend selection is efficient and cached

## Troubleshooting

### Common Issues

1. **Allocator Errors**: Ensure proper allocator usage and memory cleanup
2. **Module Import Errors**: Check module paths and dependencies
3. **Command Not Found**: Verify command registration in the registry
4. **Backend Initialization Failed**: Check configuration parameters

### Debug Tips

- Enable debug logging for detailed information
- Use the built-in error handling system
- Check module dependencies and imports
- Validate configuration parameters

## Future Extensions

The modular architecture makes it easy to add:

- New backend implementations
- Additional integration modules
- Custom CLI commands
- Performance monitoring modules
- Security enhancement modules

## Conclusion

The modular architecture provides a solid foundation for Nexcage, enabling clean code organization, easy extensibility, and maintainability. By following SOLID principles, the system remains flexible and robust while providing powerful container and VM management capabilities.
