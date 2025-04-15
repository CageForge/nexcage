# Issue 10: Implement Proxmox VE API Client

## Description

Implement a robust Proxmox VE API client in Zig that can:
- Handle multiple Proxmox hosts with automatic failover
- Cache node information to reduce API calls
- Support all necessary API endpoints for LXC container management
- Handle authentication and session management
- Implement proper error handling and retries

## Tasks

- [x] Create basic Proxmox client structure
- [x] Implement authentication
- [x] Add support for multiple hosts
- [x] Implement node caching
- [x] Add error handling
- [x] Implement retry mechanism
- [x] Add logging
- [x] Write tests
- [x] Document the API

## Implementation Details

The Proxmox client should be implemented in `src/proxmox.zig` with the following structure:

```zig
const Client = struct {
    allocator: Allocator,
    hosts: []const []const u8,
    token: []const u8,
    port: u16,
    node: []const u8,
    node_cache: ?NodeInfo,
    node_cache_time: i64,
    logger: Logger,
    // ... other fields
};
```

Key features:
- Support for multiple Proxmox hosts with automatic failover
- Node information caching to reduce API calls
- Proper error handling and retries
- Comprehensive logging
- Thread-safe operations

## Testing

The client should be tested with:
- Unit tests for individual functions
- Integration tests with a real Proxmox server
- Error handling tests
- Performance tests for caching
- Load tests for multiple hosts

## Documentation

Documentation should include:
- API reference
- Usage examples
- Configuration options
- Error handling guide
- Performance considerations

## Dependencies

- Zig standard library
- HTTP client library
- JSON parser
- Logging library

## Timeline

- Week 1: Basic client structure and authentication
- Week 2: Multiple hosts support and node caching
- Week 3: Error handling and retries
- Week 4: Testing and documentation

## Acceptance Criteria

- [ ] Client can connect to multiple Proxmox hosts
- [ ] Node information is cached and updated properly
- [ ] All API endpoints are implemented
- [ ] Error handling is comprehensive
- [ ] Tests pass
- [ ] Documentation is complete 