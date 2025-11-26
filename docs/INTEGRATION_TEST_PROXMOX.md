# Integration Testing on Proxmox VE Server

**Server:** mgr.cp.if.ua  
**Date:** 2025-11-02  
**Feature:** OCI Bundle Resources and Namespaces

## Prerequisites

1. Access to Proxmox VE server: `mgr.cp.if.ua`
2. `nexcage` binary installed and in PATH
3. Test bundle available: `/tmp/test-oci-bundle/resources-namespaces/`
4. Proper permissions to create LXC containers

## Quick Test

Run the automated test script:

```bash
cd /home/moriarti/repo/proxmox-lxcri
./scripts/test_resources_namespaces_proxmox.sh
```

Or with custom parameters:

```bash
PROXMOX_HOST=mgr.cp.if.ua \
BUNDLE_PATH=/tmp/test-oci-bundle/resources-namespaces \
CONTAINER_ID=my-test-container \
./scripts/test_resources_namespaces_proxmox.sh
```

## Manual Testing Steps

### 1. Create Container

```bash
nexcage create test-resources-ns /tmp/test-oci-bundle/resources-namespaces
```

**Expected:**
- Container created with VMID
- Memory limit: 256 MB (from bundle config)
- CPU: ~0.5 cores (512 shares / 1024)
- Features: nesting=1,keyctl=1 (from user namespace)

### 2. Find VMID

```bash
# From state file
cat /var/lib/nexcage/state/test-resources-ns.json | jq .vmid

# Or from pct list
pct list | grep test-resources-ns
```

### 3. Verify Resources

```bash
VMID=<vmid>
pct config $VMID | grep -E "memory|cores"
```

**Expected output:**
```
memory: 256
cores: 1
```

### 4. Verify Features (Namespaces)

```bash
pct config $VMID | grep features
```

**Expected output:**
```
features: nesting=1,keyctl=1
```

### 5. Verify Namespace Isolation

```bash
# Check if container is unprivileged (user namespace)
pct config $VMID | grep unprivileged

# Should show: unprivileged: 1
```

### 6. Full Configuration View

```bash
pct config $VMID
```

## Verification Checklist

- [ ] Container created successfully
- [ ] VMID assigned and in state file
- [ ] Memory limit matches bundle (256 MB)
- [ ] CPU cores set (1 core from 512 shares)
- [ ] Features applied (nesting=1,keyctl=1)
- [ ] Unprivileged mode enabled (user namespace)
- [ ] Container can be started: `nexcage start <container-id>`

## Cleanup

```bash
# Stop container
nexcage stop test-resources-ns

# Delete container
nexcage delete test-resources-ns

# Or directly via pct
pct destroy $VMID
```

## Troubleshooting

### Container creation fails

1. Check Proxmox VE status:
   ```bash
   systemctl status pve-cluster
   ```

2. Verify permissions:
   ```bash
   id
   groups | grep -E "root|proxmox"
   ```

3. Check logs:
   ```bash
   journalctl -u pve-cluster -n 50
   ```

### Resources not applied

1. Check bundle config parsing:
   ```bash
   cat /tmp/test-oci-bundle/resources-namespaces/config.json | jq .linux.resources
   ```

2. Verify nexcage parsed bundle:
   ```bash
   # Check logs or debug output
   nexcage create --debug test-resources-ns /tmp/test-oci-bundle/resources-namespaces
   ```

### Features not applied

1. Check namespace parsing:
   ```bash
   cat /tmp/test-oci-bundle/resources-namespaces/config.json | jq .linux.namespaces
   ```

2. Verify features were set:
   ```bash
   pct config $VMID | grep features
   ```

3. Check if pct set command was executed (review logs)

## Test Results

After running tests, document results:

- **Server:** mgr.cp.if.ua
- **Container ID:** 
- **VMID:** 
- **Memory Limit:** 
- **CPU Cores:** 
- **Features:** 
- **Status:** ✅ Pass / ❌ Fail

## Notes

- Test bundle location: `/tmp/test-oci-bundle/resources-namespaces/`
- State files: `/var/lib/nexcage/state/`
- LXC configs: `/etc/pve/lxc/<vmid>.conf`

