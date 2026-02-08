# Migration and Upgrade Guide

This guide helps you migrate to NexCage from other container runtimes and upgrade between NexCage versions.

## Version Upgrade

### Upgrading NexCage

#### From 0.7.x to 0.8.x (Future)

> **Note**: Version 0.8.x is not yet released. This section will be updated when available.

**Recommended Upgrade Path:**

1. Backup current state
2. Stop all containers
3. Upgrade binary
4. Update configuration
5. Restart containers

#### From 0.7.4 to 0.7.5

**Changes:**
- Added OCI Registry Pull support
- Enhanced network device aliases
- Improved `linux.netDevices` handling

**Upgrade Steps:**

```bash
# 1. Backup configuration
sudo cp /etc/nexcage/config.json /etc/nexcage/config.json.backup

# 2. Download new version
VERSION=0.7.5
wget https://github.com/CageForge/nexcage/releases/download/v${VERSION}/nexcage-linux-x86_64-v${VERSION}.tar.gz

# 3. Verify checksum
wget https://github.com/CageForge/nexcage/releases/download/v${VERSION}/nexcage-linux-x86_64-v${VERSION}.tar.gz.sha256
sha256sum -c nexcage-linux-x86_64-v${VERSION}.tar.gz.sha256

# 4. Extract and install
tar -xzf nexcage-linux-x86_64-v${VERSION}.tar.gz
sudo mv nexcage /usr/local/bin/
sudo chmod +x /usr/local/bin/nexcage

# 5. Verify version
nexcage version
```

**No Configuration Changes Required** - Backward compatible with 0.7.4

#### General Upgrade Best Practices

```bash
# Check current version
nexcage version

# List all containers before upgrade
nexcage list > containers-pre-upgrade.txt

# Stop all containers
for container in $(nexcage list | tail -n +2 | awk '{print $1}'); do
  echo "Stopping $container..."
  nexcage stop --name "$container"
done

# Perform upgrade (see version-specific instructions above)

# Verify upgrade
nexcage version

# Restart containers
for container in $(cat containers-pre-upgrade.txt | tail -n +2 | awk '{print $1}'); do
  echo "Starting $container..."
  nexcage start --name "$container"
done
```

## Breaking Changes by Version

### v0.7.0

- Changed CLI flag `--id` to `--name` for consistency
- Removed deprecated `--backend` flag (use `--runtime` instead)
- Configuration file schema updated (see [Config Migration](#configuration-migration))

**Migration:**

```bash
# Old command (v0.6.x)
nexcage create --id my-container --backend lxc --image /bundle

# New command (v0.7.x)
nexcage create --name my-container --runtime lxc --image /bundle
```

### v0.6.0

- Introduced OCI 1.3.0 support
- Added NUMA memory policy support
- Changed state file location from `/run/lxcri` to `/run/nexcage`

**Migration:**

```bash
# Migrate state files
sudo mkdir -p /run/nexcage/containers
sudo cp -r /run/lxcri/containers/* /run/nexcage/containers/ 2>/dev/null || true
```

## Configuration Migration

### Migrating from Old Config Format

**Old format (pre-0.7.0):**

```json
{
  "backend": "lxc",
  "proxmox_host": "pve.example.com",
  "storage_pool": "rpool",
  "log_level": "info"
}
```

**New format (0.7.0+):**

```json
{
  "proxmox": {
    "host": "pve.example.com",
    "node": "pve1",
    "port": 8006
  },
  "storage": {
    "type": "zfs",
    "pool": "rpool",
    "dataset": "containers"
  },
  "logging": {
    "level": "info",
    "file": "/var/log/nexcage/nexcage.log"
  }
}
```

**Automated Migration Script:**

```bash
#!/bin/bash
# migrate-config.sh

OLD_CONFIG="/etc/nexcage/config.json.old"
NEW_CONFIG="/etc/nexcage/config.json"

if [ ! -f "$OLD_CONFIG" ]; then
  echo "Old config not found at $OLD_CONFIG"
  exit 1
fi

# Extract old values
BACKEND=$(jq -r '.backend // "lxc"' "$OLD_CONFIG")
HOST=$(jq -r '.proxmox_host // "localhost"' "$OLD_CONFIG")
POOL=$(jq -r '.storage_pool // "rpool"' "$OLD_CONFIG")
LOG_LEVEL=$(jq -r '.log_level // "info"' "$OLD_CONFIG")

# Create new config
cat > "$NEW_CONFIG" <<EOF
{
  "proxmox": {
    "host": "$HOST",
    "node": "pve1",
    "port": 8006
  },
  "storage": {
    "type": "zfs",
    "pool": "$POOL",
    "dataset": "containers"
  },
  "network": {
    "bridge": "vmbr0"
  },
  "logging": {
    "level": "$LOG_LEVEL",
    "file": "/var/log/nexcage/nexcage.log"
  }
}
EOF

echo "Migration complete. New config at $NEW_CONFIG"
echo "Please review and adjust as needed."
```

## Migrating from Other Runtimes

### From Docker

**Overview:**

Docker containers cannot be directly migrated to NexCage, but you can recreate them using OCI bundles or Proxmox templates.

**Migration Strategy:**

```bash
# 1. Export Docker container as OCI bundle
docker export my-container | tar -xC /tmp/my-container-rootfs
docker inspect my-container > /tmp/container-config.json

# 2. Create OCI config.json
# (Manual step - convert Docker config to OCI format)
# See: https://github.com/opencontainers/runtime-spec

# 3. Create with NexCage
nexcage create --name my-container --image /tmp/my-container-bundle --runtime crun
nexcage start --name my-container
```

### From LXC/LXD

**Overview:**

Existing LXC containers on Proxmox can be managed by NexCage without migration.

**Integration:**

```bash
# List existing LXC containers
pct list

# NexCage can manage them
nexcage list --runtime lxc

# No migration needed - NexCage uses pct CLI
```

**For non-Proxmox LXC:**

```bash
# 1. Export LXC container
sudo lxc-freeze my-container
sudo tar -czf my-container.tar.gz -C /var/lib/lxc/my-container .
sudo lxc-unfreeze my-container

# 2. Convert to Proxmox template format
# (Manual process - create .tar.zst from rootfs)

# 3. Import to Proxmox
sudo pct create 100 local:vztmpl/my-container.tar.zst

# 4. Manage with NexCage
nexcage list
nexcage start --name 100
```

### From runc/crun

**Overview:**

Containers running with standalone runc/crun can be recreated with NexCage.

**Migration:**

```bash
# 1. Get container bundle path
runc list

# 2. Stop container
runc kill my-container SIGTERM
runc delete my-container

# 3. Create with NexCage
nexcage create --name my-container --image /path/to/bundle --runtime crun
nexcage start --name my-container
```

### From containerd

**Overview:**

NexCage can be configured as a containerd runtime (see [Containerd Integration](integration/CONTAINERD_INTEGRATION.md)).

**No Migration Needed:**

- Configure NexCage as containerd runtime
- New containers use NexCage automatically
- Existing containers continue on runc
- Gradual migration by recreation

## State Migration

### Migrating Container State

```bash
#!/bin/bash
# migrate-state.sh

OLD_STATE_DIR="/run/lxcri/containers"
NEW_STATE_DIR="/run/nexcage/containers"

if [ -d "$OLD_STATE_DIR" ]; then
  echo "Migrating state files..."
  sudo mkdir -p "$NEW_STATE_DIR"
  
  for container_dir in "$OLD_STATE_DIR"/*; do
    if [ -d "$container_dir" ]; then
      container_id=$(basename "$container_dir")
      echo "Migrating $container_id..."
      sudo cp -r "$container_dir" "$NEW_STATE_DIR/"
    fi
  done
  
  echo "State migration complete"
else
  echo "No old state directory found"
fi
```

## Rollback Procedures

### Rolling Back to Previous Version

```bash
# 1. Stop all containers
nexcage list | tail -n +2 | awk '{print $1}' | while read container; do
  nexcage stop --name "$container"
done

# 2. Install previous version
sudo cp /usr/local/bin/nexcage.backup /usr/local/bin/nexcage

# 3. Restore configuration if needed
sudo cp /etc/nexcage/config.json.backup /etc/nexcage/config.json

# 4. Verify version
nexcage version

# 5. Restart containers
cat containers-pre-upgrade.txt | tail -n +2 | awk '{print $1}' | while read container; do
  nexcage start --name "$container"
done
```

### Emergency Rollback

```bash
# If NexCage is broken, use backend directly

# For LXC containers
pct list
pct start <vmid>

# For crun containers
crun list
crun start <container-id>

# For runc containers
runc list
runc start <container-id>
```

## Post-Migration Verification

### Verification Checklist

```bash
# 1. Verify version
nexcage version

# 2. Check configuration
cat /etc/nexcage/config.json | jq .

# 3. List all containers
nexcage list

# 4. Check container states
nexcage list | tail -n +2 | while read line; do
  name=$(echo $line | awk '{print $1}')
  echo "Checking $name..."
  nexcage state --name "$name" | jq .status
done

# 5. Test container operations
nexcage create --name test-migration --image /test/bundle --runtime crun
nexcage start --name test-migration
nexcage state --name test-migration
nexcage stop --name test-migration
nexcage delete --name test-migration

echo "Migration verification complete"
```

## Common Issues

### Issue: Containers not visible after upgrade

**Solution:**

```bash
# Check state directory
ls -la /run/nexcage/containers/

# Recreate containers if state lost
pct list  # For LXC containers
# Manually recreate using nexcage create
```

### Issue: Configuration not recognized

**Solution:**

```bash
# Validate JSON syntax
jq empty /etc/nexcage/config.json

# Check for required fields
jq '.proxmox.host' /etc/nexcage/config.json
jq '.storage.pool' /etc/nexcage/config.json
```

### Issue: Runtime errors after upgrade

**Solution:**

```bash
# Check logs
sudo journalctl -u nexcage -n 100

# Verify backend runtimes
which pct crun runc

# Test backend directly
pct list
crun --version
```

## Support and Resources

- [GitHub Issues](https://github.com/CageForge/nexcage/issues)
- [Documentation](https://cageforge.github.io/nexcage/)
- [Release Notes](../releases/)
- [Troubleshooting Guide](../TROUBLESHOOTING_GUIDE.md)

## Related Documentation

- [Installation Guide](../INSTALL.md)
- [User Guide](../user_guide.md)
- [CLI Reference](../CLI_REFERENCE.md)
- [Architecture Overview](../architecture/OVERVIEW.md)
