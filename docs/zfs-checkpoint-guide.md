# ZFS Checkpoint/Restore Guide

This guide covers the ZFS-based checkpoint and restore functionality in Proxmox LXCRI, providing lightning-fast container state management through ZFS snapshots.

## Overview

Proxmox LXCRI implements a hybrid checkpoint/restore system that prioritizes ZFS snapshots for performance while providing CRIU as a fallback mechanism. This approach delivers enterprise-grade container state management with filesystem-level consistency guarantees.

### Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Container     │───▶│  ZFS Snapshot    │───▶│   Checkpoint    │
│   Runtime       │    │  (Primary)       │    │   Created       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                        │
        │                        ▼ (if ZFS unavailable)
        │               ┌──────────────────┐
        └──────────────▶│  CRIU Fallback   │
                        │  (Secondary)     │
                        └──────────────────┘
```

## Features

### ⚡ Performance Benefits
- **Lightning Speed**: Snapshots created in seconds vs minutes with traditional methods
- **Filesystem-Level**: Consistent state capture at the storage layer
- **Minimal Overhead**: ZFS copy-on-write eliminates data duplication
- **Instant Restore**: ZFS rollback provides near-instantaneous container restoration

### 🏗️ Architecture Features
- **Hybrid Approach**: ZFS primary, CRIU fallback
- **Automatic Detection**: Smart ZFS availability detection
- **Structured Storage**: Organized dataset patterns
- **Timestamp Management**: Chronological snapshot organization

## Prerequisites

### ZFS Requirements
- ZFS filesystem installed and configured
- ZFS pool available for container storage
- Sufficient pool space for snapshots
- Administrative privileges for ZFS operations

### Recommended Setup
```bash
# Create ZFS pool (example)
sudo zpool create tank /dev/sdb

# Create container datasets
sudo zfs create tank/containers
sudo zfs create tank/containers/container1
sudo zfs create tank/containers/container2
```

### System Requirements
- Proxmox VE 7.0+ (recommended)
- ZFS 2.0+ 
- Sufficient storage space for snapshots
- Network storage (optional) for distributed setups

## Dataset Structure

### Convention
Proxmox LXCRI uses a structured dataset naming convention:

```
tank/containers/<container_id>
```

### Examples
```
tank/containers/web-server
tank/containers/database-primary  
tank/containers/cache-redis
```

### Snapshot Naming
Snapshots follow a timestamp-based pattern:

```
<dataset>@checkpoint-<unix_timestamp>
```

### Examples
```
tank/containers/web-server@checkpoint-1691234567
tank/containers/database-primary@checkpoint-1691234890
```

## Usage

### Checkpoint Operations

#### Basic Checkpoint
Create a checkpoint of a running container:

```bash
proxmox-lxcri checkpoint container-id
```

**What happens:**
1. ZFS availability detection
2. Dataset validation (`tank/containers/container-id`)
3. Timestamp generation
4. ZFS snapshot creation
5. Verification and logging

#### With Custom Dataset
Specify a custom ZFS dataset path:

```bash
proxmox-lxcri checkpoint --image-path tank/custom/path container-id
```

#### CRIU Fallback
When ZFS is unavailable, automatic fallback to CRIU:

```bash
# Automatically falls back to CRIU if ZFS unavailable
proxmox-lxcri checkpoint container-id

# Explicit CRIU usage
proxmox-lxcri checkpoint --image-path /tmp/criu-checkpoint container-id
```

### Restore Operations

#### Latest Checkpoint Restore
Restore from the most recent checkpoint:

```bash
proxmox-lxcri restore container-id
```

**What happens:**
1. ZFS dataset detection
2. Snapshot enumeration
3. Latest checkpoint identification
4. ZFS rollback execution
5. Container state restoration

#### Specific Snapshot Restore
Restore from a specific checkpoint snapshot:

```bash
proxmox-lxcri restore --snapshot checkpoint-1691234567 container-id
```

#### CRIU Restore
Restore from CRIU checkpoint:

```bash
proxmox-lxcri restore --image-path /tmp/criu-checkpoint container-id
```

### Combined Operations

#### Run Command
Create and start a container in one operation:

```bash
proxmox-lxcri run --bundle /path/to/bundle container-id
```

**Equivalent to:**
```bash
proxmox-lxcri create --bundle /path/to/bundle container-id
proxmox-lxcri start container-id
```

## Management Commands

### List Snapshots
Using ZFS tools directly:

```bash
# List all snapshots for a container
zfs list -t snapshot tank/containers/container-id

# List all checkpoint snapshots
zfs list -t snapshot | grep checkpoint-
```

### Snapshot Information
```bash
# Get snapshot details
zfs get all tank/containers/container-id@checkpoint-1691234567

# Check snapshot size
zfs get used tank/containers/container-id@checkpoint-1691234567
```

### Cleanup Operations
```bash
# Delete specific snapshot
zfs destroy tank/containers/container-id@checkpoint-1691234567

# Delete all snapshots for a container
zfs destroy -r tank/containers/container-id
```

## Configuration

### Dataset Auto-Creation
Enable automatic dataset creation for new containers:

```json
{
  "zfs": {
    "auto_create_datasets": true,
    "base_dataset": "tank/containers",
    "compression": "lz4",
    "quota": "10G"
  }
}
```

### Snapshot Retention
Configure automatic snapshot cleanup:

```json
{
  "checkpoint": {
    "max_snapshots": 10,
    "retention_days": 30,
    "auto_cleanup": true
  }
}
```

## Performance Tuning

### ZFS Optimization
```bash
# Enable compression
zfs set compression=lz4 tank/containers

# Set deduplication (use carefully)
zfs set dedup=on tank/containers

# Optimize for containers
zfs set recordsize=8K tank/containers
zfs set primarycache=metadata tank/containers
```

### Memory Tuning
```bash
# Increase ARC size for better caching
echo 4294967296 > /sys/module/zfs/parameters/zfs_arc_max
```

## Monitoring

### Snapshot Space Usage
```bash
# Monitor snapshot space consumption
zfs list -o space -r tank/containers

# Check pool health
zpool status tank
```

### Performance Metrics
```bash
# ZFS I/O statistics
zpool iostat tank 1

# Snapshot creation performance
time proxmox-lxcri checkpoint test-container
```

## Troubleshooting

### Common Issues

#### ZFS Not Available
```
ERROR: ZFS not available, falling back to CRIU-only checkpoint
```

**Solutions:**
1. Install ZFS: `apt install zfsutils-linux`
2. Load ZFS module: `modprobe zfs`
3. Check ZFS service: `systemctl status zfs-import-cache`

#### Dataset Not Found
```
ERROR: Dataset does not exist: tank/containers/container-id
```

**Solutions:**
1. Create dataset: `zfs create tank/containers/container-id`
2. Check dataset path: `zfs list | grep container-id`
3. Verify permissions: `ls -la /tank/containers/`

#### Insufficient Space
```
ERROR: cannot create snapshot: out of space
```

**Solutions:**
1. Check pool space: `zpool list`
2. Clean old snapshots: `zfs destroy tank/containers/container-id@old-snapshot`
3. Add storage: `zpool add tank /dev/sdc`

### Debug Mode
Enable detailed logging:

```bash
proxmox-lxcri --debug checkpoint container-id
```

### ZFS Health Check
```bash
# Comprehensive ZFS health check
zpool status -v tank
zfs get health tank/containers
```

## Best Practices

### 1. Dataset Organization
- Use consistent naming: `tank/containers/<container-id>`
- Group related containers: `tank/containers/app-tier/web-server`
- Separate data: `tank/data/<container-id>`

### 2. Snapshot Management
- Regular cleanup of old snapshots
- Monitor snapshot space consumption
- Use descriptive snapshot names for manual snapshots

### 3. Performance
- Enable compression for better space efficiency
- Use dedicated storage for high-performance requirements
- Monitor I/O patterns and adjust recordsize accordingly

### 4. Backup Strategy
- Replicate important datasets: `zfs send/receive`
- Export pool configuration: `zpool export tank`
- Regular scrubs: `zpool scrub tank`

## Integration

### Proxmox Integration
```bash
# Create container with ZFS storage
pvesh create /nodes/node1/lxc \
  --vmid 100 \
  --hostname container1 \
  --storage tank \
  --template ubuntu-20.04
```

### Kubernetes Integration
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    io.kubernetes.cri.runtime: proxmox-lxcri
    io.kubernetes.cri.checkpoint.dataset: tank/containers/k8s-pod
spec:
  # Pod specification
```

## Examples

### Complete Workflow
```bash
# 1. Create container
proxmox-lxcri create --bundle /bundles/nginx nginx-server

# 2. Start container
proxmox-lxcri start nginx-server

# 3. Create checkpoint
proxmox-lxcri checkpoint nginx-server

# 4. Stop container
proxmox-lxcri kill nginx-server

# 5. Restore from checkpoint
proxmox-lxcri restore nginx-server

# 6. Verify restoration
proxmox-lxcri state nginx-server
```

### Batch Operations
```bash
#!/bin/bash
# Checkpoint multiple containers
containers=("web-1" "web-2" "database" "cache")

for container in "${containers[@]}"; do
  echo "Creating checkpoint for $container..."
  proxmox-lxcri checkpoint "$container"
done
```

## Security Considerations

### Access Control
- Restrict ZFS dataset permissions
- Use dedicated service accounts
- Implement audit logging

### Data Protection
- Enable ZFS encryption for sensitive data
- Regular backup of critical snapshots
- Secure snapshot replication

## Conclusion

The ZFS checkpoint/restore system in Proxmox LXCRI provides enterprise-grade container state management with unmatched performance and reliability. By leveraging ZFS's advanced features while maintaining CRIU compatibility, it offers the best of both worlds for production container environments.

For additional support and advanced configurations, refer to the [Proxmox LXCRI documentation](../README.md) and [ZFS administration guide](https://openzfs.github.io/openzfs-docs/).
