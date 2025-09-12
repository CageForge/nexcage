# BFC (Binary File Container) Integration

This document describes the integration of BFC (Binary File Container) into the proxmox-lxcri project.

## Overview

BFC is a high-performance, single-file container format for storing files and directories with complete POSIX metadata preservation. It provides:

- **Single-file containers** - Everything in one `.bfc` file
- **POSIX metadata** - Preserves permissions, timestamps, and file types
- **Fast random access** - O(log N) file lookup with sorted index
- **Optional compression** - ZSTD compression with intelligent content analysis
- **Optional encryption** - ChaCha20-Poly1305 AEAD with Argon2id key derivation
- **Integrity validation** - CRC32C checksums with hardware acceleration
- **Cross-platform** - Works on Linux, macOS, and other Unix systems

## Integration Architecture

The BFC integration follows the plugin architecture pattern:

```
src/bfc/
├── mod.zig              # BFC Zig bindings for C library
└── ...

src/oci/backend/
├── bfc.zig              # BFC backend plugin implementation
├── plugin.zig           # Backend plugin interface
└── manager.zig          # Backend manager
```

## Components

### 1. BFC Module (`src/bfc/mod.zig`)

Provides Zig bindings for the BFC C library:

- `BFCContainer` - Main container handle for reading/writing
- `BFCBuilder` - Container builder for creating new containers
- `BFCFileInfo` - File information structure
- Error handling and logging integration

### 2. BFC Backend Plugin (`src/oci/backend/bfc.zig`)

Implements the `BackendPlugin` interface for BFC:

- Container lifecycle management (create, start, stop, delete)
- File system operations (add files, directories)
- Container state management
- Checkpoint and restore functionality

### 3. Backend Manager (`src/oci/backend/manager.zig`)

Manages all backend plugins including BFC:

- Plugin registration and discovery
- Backend selection and routing
- Unified API for container operations

## Usage

### Basic BFC Operations

```zig
// Create BFC container
var container = try bfc.BFCContainer.init(allocator, logger, "/path/to/container.bfc");
defer container.deinit();

// Create the container
try container.create();

// Add files
try container.addFile("hello.txt", "Hello, World!", 0o644);
try container.addDir("data", 0o755);

// Finish the container
try container.finish();

// Open for reading
try container.open();

// List contents
try container.list(callback, userdata);

// Extract files
try container.extractFile("hello.txt", "/tmp/hello.txt");
```

### Using BFC Backend Plugin

```zig
// Initialize backend manager
var backend_manager = try oci.backend.BackendManager.init(allocator, logger);
defer backend_manager.deinit();

// Initialize plugins
try backend_manager.initializePlugins();

// Get BFC backend
const bfc_backend = backend_manager.getBackend(.bfc);

// Create container
try bfc_backend.?.createContainer(bfc_backend.?, "container-id", "/path/to/bundle", null);

// Start container
try bfc_backend.?.startContainer(bfc_backend.?, "container-id");

// Get container state
const state = try bfc_backend.?.getContainerState(bfc_backend.?, "container-id");
```

## Configuration

BFC backend can be configured through the main configuration file:

```json
{
  "runtime": {
    "backends": {
      "bfc": {
        "enabled": true,
        "container_path": "/tmp/bfc-containers",
        "compression": "zstd",
        "compression_level": 3,
        "encryption": false
      }
    }
  }
}
```

## Dependencies

The BFC integration requires:

- **libzstd** - For compression support
- **libsodium** - For encryption support
- **BFC C library** - Statically linked from `deps/bfc/`

## Build Configuration

BFC is integrated into the build system via `build.zig`:

```zig
// BFC library
const bfc_lib = b.addStaticLibrary(.{
    .name = "bfc",
    .target = target,
    .optimize = optimize,
});

// Add BFC source files
bfc_lib.addCSourceFiles(&.{
    "deps/bfc/src/bfc.c",
    "deps/bfc/src/bfc_io.c",
    // ... other source files
}, &.{
    "-std=c17",
    "-Wall",
    "-Wextra",
    "-O3",
    "-DNDEBUG",
});

// Link system libraries
bfc_lib.linkSystemLibrary("zstd");
bfc_lib.linkSystemLibrary("sodium");
```

## Examples

See `examples/bfc_example.zig` for complete usage examples.

## Performance

BFC provides excellent performance characteristics:

- **Write**: ≥300 MB/s for 1 MiB files
- **Read**: ≥1 GB/s sequential, ≥50 MB/s random 4 KiB
- **List**: ≤1 ms for directories with ≤1024 entries
- **Index load**: ≤5 ms for 100K entries on NVMe SSD

## Security

BFC implements several security measures:

- **Path traversal prevention** with strict normalization
- **Safe extraction** using `O_NOFOLLOW` and parent directory validation
- **CRC32C validation** on all read operations
- **Bounds checking** on all buffer operations
- **No arbitrary code execution** - pure data format

## Future Enhancements

- [ ] Dynamic plugin loading
- [ ] BFC container registry integration
- [ ] Advanced compression strategies
- [ ] Encryption key management
- [ ] Container migration support
- [ ] Performance monitoring and metrics

## References

- [BFC GitHub Repository](https://github.com/zombocoder/bfc)
- [BFC Documentation](https://github.com/zombocoder/bfc/tree/main/docs)
- [BFC API Reference](https://github.com/zombocoder/bfc/tree/main/include)
