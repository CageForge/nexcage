# Proxmox LXCRI Architecture

## Overview

Proxmox LXCRI is an OCI-compatible runtime that enables running containers and VMs as pods using Proxmox VE infrastructure. This document describes the architecture and command flow of the runtime implementation.

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

## Security Considerations

1. **Isolation**
   - Process namespace isolation
   - Network namespace separation
   - Resource constraints

2. **Access Control**
   - Capability management
   - SELinux/AppArmor profiles
   - Seccomp filters

3. **Network Security**
   - VLAN isolation
   - Network policy enforcement
   - Port security

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