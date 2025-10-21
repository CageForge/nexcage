# Nexcage Development Guide

## Development Environment Setup

### Prerequisites
- Zig 0.15.1 or later
- Proxmox VE 7.4 or later
- containerd 1.7 or later
- ZFS 2.1 or later
- Linux kernel 5.15 or later

### Build Environment
```bash
# Clone repository
git clone https://github.com/cageforge/nexcage.git
cd nexcage

# Install dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    zfsutils-linux \
    libzfs-dev \
    libproxmox-backup-qemu0-dev

# Build project
zig build
```

## Debugging
[docs/DEBUG_LOGGING_GUIDE.md]

### Debug Build
```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Run with debug logging
NEXCAGE_LOG_LEVEL=debug ./zig-out/bin/nexcage
```

### GDB Debugging
```bash
# Start GDB
gdb ./zig-out/bin/nexcage

# Set breakpoints
break src/oci/create.zig:100
break src/network/manager.zig:50

# Run with arguments
run --config /etc/nexcage/config.json
```

### System Tracing
```bash
# Trace system calls
strace -f -o trace.log ./zig-out/bin/nexcage

# Trace network operations
tcpdump -i any -w network.pcap
```

## Adding New Features

### 1. Project Structure (old structure, legacy)
```
src/
├── oci/           # OCI runtime implementation
├── network/       # Network management
├── storage/       # Storage management
├── security/      # Security features
└── common/        # Common utilities
```

### 2. Development Workflow

#### a. Create Feature Branch
```bash
git checkout -b feature/your-feature-name
```

#### b. Implement Feature
```zig
// Example: Adding new hook type
pub const HookType = enum {
    prestart,
    poststart,
    poststop,
    your_new_hook,  // Add new hook type
};

// Update hook executor
pub fn executeHook(self: *HookExecutor, hook: Hook, context: HookContext) !void {
    switch (hook.type) {
        .your_new_hook => try self.executeYourNewHook(hook, context),
        else => try self.executeDefaultHook(hook, context),
    }
}
```

#### c. Add Tests
```zig
test "HookExecutor - new hook type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try HookExecutor.init(allocator);
    defer executor.deinit();

    const hook = types.Hook{
        .type = .your_new_hook,
        .path = "/bin/echo",
        .args = &[_][]const u8{"Hello"},
        .env = null,
        .timeout = null,
    };

    const context = HookContext{
        .container_id = "test-container",
        .bundle = "/test/bundle",
        .state = "creating",
    };

    try executor.executeHook(hook, context);
}
```

#### d. Update Documentation
```markdown
## New Hook Type

The `your_new_hook` hook is executed during the container lifecycle...

### Configuration
```json
{
    "hooks": {
        "your_new_hook": [
            {
                "path": "/path/to/hook",
                "args": ["arg1", "arg2"],
                "env": ["KEY=value"]
            }
        ]
    }
}
```
```

### 3. Code Review Checklist

- [ ] Code follows Zig style guide
- [ ] All tests pass
- [ ] Documentation updated
- [ ] No memory leaks
- [ ] Error handling complete
- [ ] Logging appropriate
- [ ] Performance considered

### 4. Performance Considerations (deprecated)

```zig
// Use arena allocator for temporary allocations
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

// Use fixed-size arrays when possible
var buffer: [1024]u8 = undefined;

// Avoid unnecessary copies
const slice = try allocator.dupe(u8, original);
defer allocator.free(slice);
```

### 5. Error Handling (deprecated)

```zig
// Use error sets for specific errors
const StorageError = error{
    DatasetNotFound,
    PermissionDenied,
    OutOfSpace,
};

// Return error union
pub fn createDataset(path: []const u8) !void {
    if (try datasetExists(path)) {
        return StorageError.DatasetExists;
    }
    // ...
}

// Handle errors appropriately
if (createDataset(path)) |_| {
    // Success
} else |err| switch (err) {
    StorageError.DatasetExists => {
        log.warn("Dataset already exists: {s}", .{path});
    },
    else => |e| {
        log.err("Failed to create dataset: {}", .{e});
        return e;
    },
}
```

## Testing

### Unit Tests
```bash
# Run all tests
zig build test

# Run specific test
zig build test --test-filter "HookExecutor"
```

### Integration Tests
```bash
# Run integration tests
zig build test_integration

# Run specific integration test
zig build test_integration --test-filter "container_lifecycle"
```

### Performance Tests
```bash
# Run benchmarks
zig build benchmark

# Profile performance
perf record -g ./zig-out/bin/nexcage
perf report
```

## Release Process

### 1. Version Bumping
```bash
# Update version in build.zig
version = "0.7.0";
```

### 2. Changelog
```bash
# Update CHANGELOG.md
git log --pretty=format:"%h %s" v0.0.9..HEAD
```

### 3. Release Tag
```bash
git tag -a v0.7.0 -m "Release v0.7.0"
git push origin v0.7.0
```

### 4. Documentation
- Update CLI documentation
- Update user guide
- Update release notes

## Troubleshooting

### Common Issues

1. **Memory Leaks**
```bash
# Use valgrind to detect leaks
valgrind --leak-check=full ./zig-out/bin/nexcage
```

2. **Performance Issues**
```bash
# Profile CPU usage
perf top -p $(pgrep nexcage)

# Profile memory usage
pmap -x $(pgrep nexcage)
```

3. **Network Issues**
```bash
# Check network configuration
ip netns exec container-ns ip addr

# Check network connectivity
nc -zv container-ip port
```

### Debugging Tips

1. **Enable Verbose Logging**
```bash
NEXCAGE_LOG_LEVEL=debug ./zig-out/bin/nexcage
```

2. **Check System Logs**
```bash
journalctl -u nexcage -f
```

3. **Inspect Container State**
```bash
ls -l /run/nexcage/containers/
cat /run/nexcage/containers/<id>/state.json
``` 