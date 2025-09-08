# Proxmox LXCRI Architecture

## Overview

Proxmox LXCRI (LXC Runtime Interface) is a container runtime interface that enables running OCI-compliant containers on Proxmox VE using LXC. The system is designed to work with Kubernetes through containerd and provides a complete solution for container management, storage, networking, and security.

## System Context

The system interacts with several external actors:

1. **Kubernetes**: Manages container lifecycle through CRI
2. **System Administrator**: Configures and manages the runtime
3. **Developer**: Develops and maintains the system

The system also interacts with Proxmox VE for:
- Container runtime (LXC)
- Storage management (ZFS)
- Network configuration

## Container Architecture

The system consists of several main containers:

1. **containerd**:
   - CRI Plugin: Implements Kubernetes Container Runtime Interface
   - OCI Runtime: Manages OCI-compliant containers

2. **Proxmox LXCRI**:
   - Runtime Service: Manages container lifecycle
   - Storage Service: Handles container storage
   - Network Service: Manages container networking
   - Security Service: Enforces security policies

3. **Proxmox VE**:
   - LXC Runtime: Executes containers
   - ZFS Storage: Provides storage backend
   - Network Stack: Handles networking

## Component Architecture

### Runtime Service

1. **State Manager**:
   - Container State: Tracks container lifecycle
   - State Storage: Persists container state

2. **Hook System**:
   - Hook Executor: Executes container hooks
   - Hook Context: Provides hook execution context

3. **Bundle Validator**:
   - Spec Validator: Validates OCI spec
   - Config Validator: Validates container config

### Storage Service

1. **Dataset Manager**:
   - ZFS Operations: Manages ZFS datasets
   - Dataset Config: Handles dataset configuration

2. **Layer Manager**:
   - Layer Storage: Manages container layers
   - Layer Operations: Handles layer operations

3. **Image Manager**:
   - Image Storage: Manages container images
   - Image Operations: Handles image operations

### Network Service

1. **VLAN Manager**:
   - VLAN Config: Manages VLAN configuration
   - VLAN Operations: Handles VLAN operations

2. **Bridge Manager**:
   - Bridge Config: Manages bridge configuration
   - Bridge Operations: Handles bridge operations

3. **IP Manager**:
   - IP Config: Manages IP configuration
   - IP Operations: Handles IP operations

### Security Service

1. **AppArmor/SELinux**:
   - Profile Manager: Manages security profiles
   - Policy Enforcer: Enforces security policies

2. **Seccomp**:
   - Filter Manager: Manages seccomp filters
   - Profile Loader: Loads seccomp profiles

3. **Capabilities**:
   - Cap Manager: Manages Linux capabilities
   - Cap Enforcer: Enforces capability restrictions

## Code Architecture

### Key Classes

1. **ContainerState**:
   - Tracks container lifecycle state
   - Manages container metadata
   - Handles state persistence

2. **HookExecutor**:
   - Executes container hooks
   - Manages hook timeouts
   - Handles hook errors

3. **HookContext**:
   - Provides hook execution context
   - Manages environment variables
   - Validates context data

4. **DatasetManager**:
   - Manages ZFS datasets
   - Handles dataset operations
   - Provides dataset information

5. **LayerManager**:
   - Manages container layers
   - Handles layer operations
   - Manages layer storage

6. **ImageManager**:
   - Manages container images
   - Handles image operations
   - Manages image storage

## Data Flow

1. **Container Creation**:
   - Kubernetes sends create request
   - containerd validates request
   - Proxmox LXCRI creates container
   - LXC starts container

2. **Container Lifecycle**:
   - State Manager tracks state
   - Hook System executes hooks
   - Security Service enforces policies

3. **Storage Operations**:
   - Image Manager pulls images
   - Layer Manager creates layers
   - Dataset Manager manages storage

4. **Network Operations**:
   - Network Service configures network
   - Proxmox VE sets up networking
   - Container gets network access

## Security Considerations

1. **Container Isolation**:
   - LXC provides process isolation
   - AppArmor/SELinux enforces access control
   - Seccomp filters system calls

2. **Resource Management**:
   - ZFS provides storage isolation
   - Network namespaces provide network isolation
   - Cgroups manage resource limits

3. **Access Control**:
   - Linux capabilities restrict privileges
   - Security profiles enforce policies
   - Network policies control access

## Performance Considerations

1. **Storage Performance**:
   - ZFS provides efficient storage
   - Layer management optimizes space
   - Caching improves performance

2. **Network Performance**:
   - VLANs provide network isolation
   - Bridges optimize network traffic
   - IP management ensures efficiency

3. **Runtime Performance**:
   - LXC provides lightweight containers
   - Hook system minimizes overhead
   - State management optimizes operations

## System Architecture

```
containerd -> proxmox-lxcri -> Proxmox API -> LXC/QEMU
     |                             |
     |                             v
     |                        ZFS Storage
     v
OCI Bundle
```

## Core Components

### 1. OCI Runtime Implementation
- Implements OCI Runtime Specification v1.0
- Handles container lifecycle commands
- Manages state transitions
- Implements hooks system

### 2. Storage Manager
- ZFS dataset management
- Volume snapshots and clones
- Layer management
- **ZFS Checkpoint/Restore System**
  - Lightning-fast container state snapshots
  - Automatic ZFS detection and CRIU fallback
  - Timestamp-based snapshot organization
  - Latest checkpoint auto-selection
- Image storage

### 3. Network Manager
- VLAN configuration
- Bridge management
- IP allocation
- DNS configuration

### 4. Security Module
- AppArmor/SELinux profiles
- Seccomp filters
- Resource isolation
- Capability management

## Command Flow Details

### create
```
containerd -> proxmox-lxcri create
  1. Validate bundle
     - Check config.json existence
     - Validate bundle structure
     - Parse and validate config
  
  2. Create ZFS dataset
     - Generate dataset name from container ID
     - Create dataset with appropriate properties
     - Set quota and reservation
  
  3. Setup rootfs
     - Copy bundle rootfs to ZFS dataset
     - Apply filesystem options
     - Configure mountpoints
  
  4. Configure LXC container
     - Generate LXC config from OCI spec
     - Set resource limits (CPU, memory)
     - Configure network interfaces
     - Setup storage mounts
  
  5. Execute pre-create hooks
     - Run prestart hooks
     - Handle hook timeouts
     - Process hook results
  
  6. Create container via Proxmox API
     - Call LXC create API
     - Wait for creation completion
     - Verify container status
  
  7. Save container state
     - Write state to configured root directory
     - Update status file
     - Save runtime metadata
```

### start
```
containerd -> proxmox-lxcri start
  1. Load container state
     - Read state from disk
     - Validate current status
  
  2. Execute pre-start hooks
     - Run createRuntime hooks
     - Run createContainer hooks
     - Process hook results
  
  3. Start container
     - Call Proxmox API start
     - Wait for container to start
     - Monitor startup process
  
  4. Execute post-start hooks
     - Run poststart hooks
     - Update container state
  
  5. Update state
     - Update status to running
     - Save new state to disk
```

### state
```
containerd -> proxmox-lxcri state
  1. Load container metadata
     - Read state from disk
     - Validate state file
  
  2. Query Proxmox API
     - Get current container status
     - Fetch resource usage
     - Get network status
  
  3. Generate state response
     - Format according to OCI spec
     - Include all required fields
     - Add annotations
  
  4. Return state
     - Output JSON formatted state
     - Include status, pid, bundle
```

### kill
```
containerd -> proxmox-lxcri kill
  1. Load container state
     - Validate container exists
     - Check current status
  
  2. Process signal
     - Map signal to LXC operation
     - Handle special signals
  
  3. Execute kill
     - Send signal via Proxmox API
     - Wait for completion
     - Handle timeouts
  
  4. Update state
     - Update container status
     - Save new state
```

### delete
```
containerd -> proxmox-lxcri delete
  1. Load container state
     - Check container exists
     - Verify container stopped
  
  2. Execute pre-delete hooks
     - Run poststop hooks
     - Clean up resources
  
  3. Delete container
     - Remove LXC container
     - Delete ZFS dataset
     - Clean network config
  
  4. Cleanup state
     - Remove state files
     - Clean metadata
     - Remove runtime files
```

## State Management

Container state is maintained in the configured root directory:
```
/run/proxmox-lxcri/
  ├── containers/
  │   └── <container-id>/
  │       ├── state.json    # Current state
  │       ├── config.json   # Container config
  │       └── hooks/        # Hook state
  └── runtime/
      └── events.log       # Runtime events
```

## Error Handling

Each operation implements comprehensive error handling:

1. **Validation Errors**
   - Bundle validation
   - State consistency
   - Resource availability

2. **Runtime Errors**
   - API communication
   - Resource allocation
   - Hook execution

3. **Recovery Procedures**
   - Resource cleanup
   - State restoration
   - Partial completion handling

## ZFS Checkpoint/Restore Architecture

### Overview
The ZFS Checkpoint/Restore system provides enterprise-grade container state management through a hybrid approach that prioritizes ZFS snapshots while maintaining CRIU compatibility.

### Architecture Components

```
┌─────────────────────────────────────────────────────────────┐
│                    ZFS Checkpoint/Restore                    │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  ZFS Manager  │───▶│ Snapshot Mgr │───▶│   Dataset    │  │
│  │   Detection   │    │   Creation   │    │  Management  │  │
│  └───────────────┘    └──────────────┘    └──────────────┘  │
│           │                     │                    │      │
│           ▼                     ▼                    ▼      │
│  ┌───────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │ CRIU Fallback │    │  Timestamp   │    │    Latest    │  │
│  │   Detection   │    │   Naming     │    │  Selection   │  │
│  └───────────────┘    └──────────────┘    └──────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Core Components

1. **ZFS Manager (`src/zfs/mod.zig`)**:
   - Automatic ZFS availability detection
   - Dataset existence validation
   - Snapshot creation and management
   - Error handling and logging

2. **Checkpoint Controller**:
   - Container state analysis
   - Consistency checking
   - Hybrid routing (ZFS/CRIU)
   - Performance optimization

3. **Restore Engine**:
   - Latest checkpoint detection
   - Timestamp parsing and filtering
   - ZFS rollback operations
   - State verification

### Dataset Organization

**Structure Pattern:**
```
tank/containers/<container_id>
├── @checkpoint-1691234567
├── @checkpoint-1691234890
└── @checkpoint-1691235123
```

**Performance Characteristics:**
- ZFS Creation: ~1-3 seconds
- ZFS Restore: ~2-5 seconds  
- CRIU Fallback: ~10-60 seconds
- Storage Overhead: ~0-5% (ZFS COW)

## Monitoring and Metrics

1. **Container Metrics**
   - Resource usage
   - Network statistics
   - Storage utilization

2. **Runtime Metrics**
   - Operation latency
   - Error rates
   - API response times

3. **Health Monitoring**
   - Container health checks
   - Runtime status
   - Resource availability

4. **ZFS Metrics**
   - Snapshot creation time
   - Storage usage patterns
   - Dataset health status
   - Checkpoint success rates 