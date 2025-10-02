# PCT CLI Migration Plan

## Overview
This document outlines the migration plan to use `pct` CLI exclusively for Proxmox LXC operations instead of direct API calls.

## Current State Analysis

### Current Implementation
- **HTTP API Client**: Direct Proxmox API calls via `src/proxmox/client.zig`
- **Operations**: LXC operations in `src/proxmox/lxc/` directory
- **Partial PCT Support**: Only in `src/oci/exec.zig` for command execution

### Current Proxmox Operations
1. **Container Management**:
   - `createContainer()` - Creates LXC containers via API
   - `startContainer()` - Starts containers via API
   - `stopContainer()` - Stops containers via API
   - `deleteContainer()` - Deletes containers via API
   - `getContainerStatus()` - Gets container status via API

2. **Container Listing**:
   - `listContainers()` - Lists all LXC containers via API
   - `listLXCs()` - Lists LXC containers via API

3. **Configuration**:
   - `getContainerConfig()` - Gets container configuration via API

## Migration Strategy

### Phase 1: PCT CLI Wrapper Implementation
**Goal**: Create a comprehensive PCT CLI wrapper to replace all API calls

#### 1.1 Create PCT CLI Module
- **File**: `src/proxmox/pct_cli.zig`
- **Purpose**: Centralized PCT CLI operations
- **Features**:
  - Command execution with proper error handling
  - Output parsing (JSON where applicable)
  - Timeout management
  - Logging integration

#### 1.2 PCT Operations Mapping
| Current API Operation | PCT CLI Command | New Function |
|----------------------|-----------------|--------------|
| Create Container | `pct create <vmid> <ostemplate>` | `pctCreateContainer()` |
| Start Container | `pct start <vmid>` | `pctStartContainer()` |
| Stop Container | `pct stop <vmid>` | `pctStopContainer()` |
| Delete Container | `pct destroy <vmid>` | `pctDeleteContainer()` |
| List Containers | `pct list` | `pctListContainers()` |
| Get Container Status | `pct status <vmid>` | `pctGetContainerStatus()` |
| Get Container Config | `pct config <vmid>` | `pctGetContainerConfig()` |

### Phase 2: Refactor ProxmoxClient
**Goal**: Replace API calls with PCT CLI calls

#### 2.1 Update ProxmoxClient Structure
- Remove HTTP client dependencies
- Add PCT CLI path configuration
- Update initialization to check PCT availability

#### 2.2 Replace Operation Methods
- Update all container operations to use PCT CLI
- Maintain same public interface for backward compatibility
- Add proper error handling and logging

### Phase 3: Configuration Updates
**Goal**: Update configuration to support PCT CLI requirements

#### 3.1 PCT CLI Configuration
- Add PCT CLI path configuration
- Add node specification for PCT operations
- Remove API token requirements

#### 3.2 Environment Requirements
- Document PCT CLI installation requirements
- Add PCT CLI availability checks
- Update dependency documentation

### Phase 4: Testing and Validation
**Goal**: Ensure all functionality works with PCT CLI

#### 4.1 Unit Tests
- Test all PCT CLI operations
- Test error handling scenarios
- Test configuration parsing

#### 4.2 Integration Tests
- Test complete container lifecycle
- Test with different Proxmox configurations
- Performance comparison with API approach

## Implementation Details

### PCT CLI Wrapper Structure
```zig
pub const PCTClient = struct {
    allocator: Allocator,
    pct_path: []const u8,
    node: []const u8,
    logger: *Logger,
    
    pub fn init(allocator: Allocator, pct_path: []const u8, node: []const u8, logger: *Logger) !PCTClient
    pub fn deinit(self: *PCTClient) void
    
    // Container operations
    pub fn createContainer(self: *PCTClient, vmid: u32, config: LXCConfig) !void
    pub fn startContainer(self: *PCTClient, vmid: u32) !void
    pub fn stopContainer(self: *PCTClient, vmid: u32) !void
    pub fn deleteContainer(self: *PCTClient, vmid: u32) !void
    pub fn listContainers(self: *PCTClient) ![]LXCContainer
    pub fn getContainerStatus(self: *PCTClient, vmid: u32) !ContainerStatus
    pub fn getContainerConfig(self: *PCTClient, vmid: u32) !LXCConfig
};
```

### Error Handling Strategy
- Parse PCT CLI exit codes
- Parse PCT CLI error messages
- Map to existing error types where possible
- Add new error types for PCT-specific issues

### Configuration Changes
```json
{
  "proxmox": {
    "pct_path": "/usr/bin/pct",
    "node": "proxmox-node",
    "timeout": 30
  }
}
```

## Benefits of PCT CLI Approach

### Advantages
1. **Simplified Dependencies**: No HTTP client, JSON parsing, or API authentication
2. **Better Error Messages**: PCT CLI provides more descriptive error messages
3. **Consistency**: Uses the same tool that Proxmox administrators use
4. **Reliability**: PCT CLI is the official tool, more stable than API calls
5. **Performance**: Direct CLI calls are often faster than HTTP API calls

### Considerations
1. **Node Requirements**: PCT CLI must be available on the node running the application
2. **Permission Requirements**: PCT CLI requires appropriate Proxmox permissions
3. **Output Parsing**: Need to parse text output instead of JSON
4. **Version Compatibility**: Need to handle different PCT CLI versions

## Migration Timeline

### Sprint 1 (Week 1-2)
- [ ] Create PCT CLI wrapper module
- [ ] Implement basic container operations
- [ ] Add comprehensive error handling
- [ ] Create unit tests

### Sprint 2 (Week 3-4)
- [ ] Refactor ProxmoxClient to use PCT CLI
- [ ] Update configuration system
- [ ] Update documentation
- [ ] Integration testing

### Sprint 3 (Week 5-6)
- [ ] Performance testing and optimization
- [ ] User acceptance testing
- [ ] Documentation updates
- [ ] Release preparation

## Success Criteria

1. **Functional Parity**: All existing functionality works with PCT CLI
2. **Performance**: Equal or better performance than API approach
3. **Reliability**: Fewer errors and better error messages
4. **Maintainability**: Cleaner, more maintainable code
5. **Documentation**: Complete documentation for PCT CLI approach

## Risk Mitigation

### Risks
1. **PCT CLI Availability**: May not be available in all environments
2. **Output Format Changes**: PCT CLI output format may change between versions
3. **Permission Issues**: PCT CLI may require different permissions than API

### Mitigation Strategies
1. **Fallback Mechanism**: Keep API client as fallback option
2. **Version Detection**: Detect PCT CLI version and handle accordingly
3. **Permission Checks**: Add permission validation during initialization
4. **Comprehensive Testing**: Test with different Proxmox and PCT CLI versions

## Conclusion

This migration will simplify the codebase, improve reliability, and provide better integration with Proxmox LXC management. The PCT CLI approach aligns with Proxmox best practices and provides a more maintainable solution for container management operations.


