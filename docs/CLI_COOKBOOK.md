# CLI Cookbook

Practical recipes and workflows for common NexCage tasks.

## Quick Start Workflows

### First-Time Setup

```bash
# 1. Install dependencies
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev

# 2. Build NexCage
zig build

# 3. Create configuration
cp config.json.example config.json
# Edit config.json with your settings

# 4. Verify installation
./zig-out/bin/nexcage version
```

### Basic Container Lifecycle

```bash
# List all containers
nexcage list

# Create container from OCI bundle
nexcage create --name my-container --image /path/to/bundle

# Start the container
nexcage start --name my-container

# Check container state
nexcage state --name my-container

# Stop the container
nexcage stop --name my-container

# Delete the container
nexcage delete --name my-container
```

## Common Task Examples

### Working with Proxmox Templates

```bash
# Create container from Proxmox template storage
nexcage create \
  --name debian-web \
  --image local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst \
  --runtime lxc

# Create from local template file
nexcage create \
  --name ubuntu-db \
  --image /var/lib/vz/template/cache/ubuntu-22.04-standard.tar.zst \
  --runtime lxc
```

### Container Management

```bash
# List only LXC containers
nexcage list --runtime lxc

# Send graceful shutdown signal
nexcage kill --name my-container --signal SIGTERM

# Force kill container
nexcage kill --name my-container --signal SIGKILL

# Get OCI-compliant state JSON
nexcage state --name my-container | jq .
```

### Backend Selection

```bash
# Explicitly use LXC backend (default for Proxmox)
nexcage create --name lxc-container --image /bundle --runtime lxc

# Use crun runtime (OCI)
nexcage create --name crun-container --image /bundle --runtime crun

# Use runc runtime (OCI fallback)
nexcage create --name runc-container --image /bundle --runtime runc
```

## Troubleshooting Commands

### Debugging Container Issues

```bash
# Enable debug logging
nexcage --debug list

# Verbose output for create operation
nexcage --verbose create --name test --image /bundle

# Use custom config file
nexcage --config /path/to/config.json list
```

### Checking Container State

```bash
# Get detailed state information
nexcage state --name my-container

# Example output:
# {
#   "ociVersion": "1.0.2",
#   "id": "my-container",
#   "status": "running",
#   "pid": 12345,
#   "bundle": "/var/lib/nexcage/bundles/my-container",
#   "annotations": {}
# }
```

### Verifying Configuration

```bash
# Check if backend tools are available
which pct lxc-ls crun runc

# Verify Proxmox LXC installation
pct list

# Test OCI runtime
crun --version
runc --version
```

## Scripting and Automation

### Batch Container Creation

```bash
#!/bin/bash
# Create multiple containers from template

TEMPLATE="local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
PREFIX="web"
COUNT=5

for i in $(seq 1 $COUNT); do
  NAME="${PREFIX}-$(printf "%02d" $i)"
  echo "Creating container: $NAME"
  
  nexcage create --name "$NAME" --image "$TEMPLATE" --runtime lxc
  nexcage start --name "$NAME"
  
  echo "Container $NAME created and started"
done
```

### Health Check Script

```bash
#!/bin/bash
# Check health of all containers

nexcage list | tail -n +2 | while read line; do
  CONTAINER_NAME=$(echo $line | awk '{print $1}')
  
  echo "Checking: $CONTAINER_NAME"
  STATE=$(nexcage state --name "$CONTAINER_NAME" 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    STATUS=$(echo "$STATE" | jq -r '.status')
    echo "  Status: $STATUS"
  else
    echo "  Error: Could not get state"
  fi
done
```

### Cleanup Old Containers

```bash
#!/bin/bash
# Stop and delete all containers with specific prefix

PREFIX="test"

nexcage list | grep "^${PREFIX}-" | awk '{print $1}' | while read CONTAINER; do
  echo "Stopping $CONTAINER..."
  nexcage stop --name "$CONTAINER" 2>/dev/null || true
  
  echo "Deleting $CONTAINER..."
  nexcage delete --name "$CONTAINER"
done
```

## Best Practices for Production

### 1. Always Verify Bundle Before Creation

```bash
# Check bundle structure
ls -la /path/to/bundle/
# Should contain: config.json and rootfs/

# Validate config.json syntax
jq empty /path/to/bundle/config.json

# Then create container
nexcage create --name prod-app --image /path/to/bundle
```

### 2. Use Explicit Runtime Selection

```bash
# For production workloads on Proxmox
nexcage create --name prod-db --image /bundle --runtime lxc

# For OCI-compliant portable workloads
nexcage create --name portable-app --image /bundle --runtime crun
```

### 3. Graceful Shutdown Workflow

```bash
# Try graceful shutdown first
nexcage kill --name my-app --signal SIGTERM

# Wait a bit
sleep 10

# Check if still running
STATE=$(nexcage state --name my-app 2>/dev/null | jq -r '.status')

# Force kill if needed
if [ "$STATE" = "running" ]; then
  echo "Forcing shutdown..."
  nexcage kill --name my-app --signal SIGKILL
fi

# Delete after stopped
nexcage delete --name my-app
```

### 4. Centralized Configuration

```bash
# Use environment variable for config
export NEXCAGE_CONFIG="/etc/nexcage/production.json"

# All commands will use this config
nexcage list
nexcage create --name app --image /bundle
```

### 5. Logging for Audit Trail

```bash
# Enable verbose logging for audit
nexcage --verbose --debug create --name audit-app --image /bundle \
  2>&1 | tee -a /var/log/nexcage/operations.log
```

## Configuration Examples

### Minimal config.json

```json
{
  "proxmox": {
    "host": "pve.example.com",
    "node": "pve1"
  },
  "storage": {
    "type": "zfs",
    "pool": "rpool"
  }
}
```

### Production config.json

```json
{
  "proxmox": {
    "host": "pve-cluster.example.com",
    "port": 8006,
    "node": "pve1",
    "api_timeout": 30
  },
  "storage": {
    "type": "zfs",
    "pool": "tank",
    "dataset": "containers"
  },
  "network": {
    "bridge": "vmbr0",
    "vlan": 100
  },
  "logging": {
    "level": "info",
    "file": "/var/log/nexcage/nexcage.log"
  }
}
```

## Environment Variables

```bash
# Configuration file location
export NEXCAGE_CONFIG="/etc/nexcage/config.json"

# Logging level (debug, info, warn, error)
export NEXCAGE_LOG_LEVEL="info"

# Storage path for bundles and state
export NEXCAGE_STORAGE_PATH="/var/lib/nexcage"

# Use in commands
nexcage list
```

## Exit Codes

- `0` - Success
- `1` - General error (config, runtime error, etc.)
- `2` - Invalid arguments or usage
- `3` - Container not found
- `4` - Backend/runtime error
- `5` - Permission denied

### Checking Exit Codes

```bash
#!/bin/bash
nexcage create --name test --image /bundle

case $? in
  0)
    echo "Container created successfully"
    ;;
  1)
    echo "General error occurred"
    ;;
  2)
    echo "Invalid arguments"
    ;;
  3)
    echo "Container not found"
    ;;
  4)
    echo "Backend error"
    ;;
  5)
    echo "Permission denied"
    ;;
  *)
    echo "Unknown error"
    ;;
esac
```

## Integration with Monitoring

### Prometheus Metrics Export

```bash
# Example script to export container metrics
#!/bin/bash

METRIC_FILE="/var/lib/prometheus/nexcage_metrics.prom"

# Count containers by status
RUNNING=$(nexcage list | grep -c "running" || echo 0)
STOPPED=$(nexcage list | grep -c "stopped" || echo 0)

# Write metrics
cat > "$METRIC_FILE" <<EOF
# HELP nexcage_containers_running Number of running containers
# TYPE nexcage_containers_running gauge
nexcage_containers_running $RUNNING

# HELP nexcage_containers_stopped Number of stopped containers
# TYPE nexcage_containers_stopped gauge
nexcage_containers_stopped $STOPPED
EOF
```

## Shell Completion

### Bash Completion (Future Feature)

```bash
# Will be available in future versions
# source <(nexcage completion bash)
```

## Related Documentation

- [CLI Reference](CLI_REFERENCE.md) - Complete command reference
- [User Guide](user_guide.md) - Detailed user guide
- [Troubleshooting](TROUBLESHOOTING_GUIDE.md) - Troubleshooting guide
- [Architecture](architecture/OVERVIEW.md) - Architecture overview
