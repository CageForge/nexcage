# OCI Bundle Generator & Create Command

## Overview

NexCage implements OCI Runtime Specification 1.0.2 for creating containers on Proxmox VE using LXC backend.

## Architecture

### Components

1. **Mapping Manager** (`src/oci/mapping.zig`)
   - Generates unique VMIDs for containers
   - Maintains persistent mapping between container-id and vmid
   - Handles collision detection

2. **State Manager** (`src/oci/state_manager.zig`)
   - Manages container state (created, running, stopped, paused)
   - Persists state.json per container
   - Implements OCI runtime spec state format

3. **Config Parser** (`src/oci/config_parser.zig`)
   - Parses OCI config.json from bundle
   - Converts OCI spec to LXC configuration
   - Handles resources, mounts, namespaces, capabilities

4. **LXC Creator** (`src/backends/lxc/creator.zig`)
   - Creates LXC containers using `pct create`
   - Configures environment variables
   - Manages mounts and resources

5. **Create Command** (`src/oci/create_command.zig`)
   - Orchestrates container creation workflow
   - Validates bundle structure
   - Integrates all components

## Usage

### Create Container

```bash
nexcage create <container-id> <bundle-path>
```

**Example:**
```bash
# Create container from OCI bundle
nexcage create nginx-prod /var/lib/containerd/bundles/nginx

# Container is created but not started (status: created)
nexcage state nginx-prod
```

### Bundle Structure

```
bundle/
├── config.json      # OCI runtime specification
└── rootfs/          # Container root filesystem
    ├── bin/
    ├── etc/
    ├── lib/
    ├── usr/
    └── ...
```

### Minimal config.json

```json
{
  "ociVersion": "1.0.2",
  "process": {
    "terminal": false,
    "user": {
      "uid": 0,
      "gid": 0
    },
    "args": ["/bin/sh"],
    "env": [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "TERM=xterm"
    ],
    "cwd": "/"
  },
  "root": {
    "path": "rootfs",
    "readonly": false
  },
  "hostname": "container",
  "linux": {
    "namespaces": [
      {"type": "pid"},
      {"type": "network"},
      {"type": "ipc"},
      {"type": "uts"},
      {"type": "mount"}
    ]
  }
}
```

## Workflow

### 1. VMID Generation

```
container-id → hash → VMID (100-999999)
```

- Uses Wyhash for deterministic generation
- Checks for collisions in mapping
- Validates against existing Proxmox containers

### 2. OCI Config Parsing

Extracts from config.json:
- `process.args` → command to execute
- `process.env` → environment variables
- `root.path` → rootfs location
- `mounts` → additional volumes
- `linux.resources` → memory, CPU limits
- `linux.namespaces` → unprivileged mode
- `hostname` → container hostname

### 3. LXC Container Creation

```bash
pct create <vmid> /dev/null \
  --rootfs local:2,mp=<rootfs-path> \
  --hostname <hostname> \
  --memory <memory-mb> \
  --cores <cpu-cores> \
  --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp
```

### 4. State Persistence

**State file:** `/var/lib/nexcage/state/<container-id>.json`

```json
{
  "ociVersion": "1.0.2",
  "id": "nginx-prod",
  "status": "created",
  "pid": 0,
  "bundle": "/var/lib/containerd/bundles/nginx",
  "vmid": 12345,
  "created_at": 1696780800
}
```

**Mapping file:** `/var/lib/nexcage/state/mapping.json`

```json
{
  "nginx-prod": {
    "vmid": 12345,
    "created_at": 1696780800,
    "bundle_path": "/var/lib/containerd/bundles/nginx"
  }
}
```

## OCI Spec Translation

### Resources

| OCI Field | LXC Option |
|-----------|------------|
| `linux.resources.memory.limit` | `--memory <MB>` |
| `linux.resources.cpu.quota/period` | `--cores <N>` |

### Namespaces

| OCI Namespace | LXC Config | Implementation |
|---------------|------------|----------------|
| `user` | `--unprivileged 1` + `--features nesting=1,keyctl=1` | Automatically applied via `pct set` after creation |
| `pid`, `network`, `ipc`, `uts`, `mount`, `cgroup` | Default in LXC | No additional configuration needed |

**Namespace Processing:**
- Namespaces are parsed from `linux.namespaces` array in config.json
- User namespace detection enables nesting and keyctl features
- Features are applied using `pct set <vmid> --features <features>` after container creation
- All standard OCI namespaces are supported and properly isolated

### Features

| OCI Namespace Type | LXC Features Applied |
|-------------------|---------------------|
| `user` namespace present | `nesting=1,keyctl=1` |
| No user namespace | `keyctl=1` (minimal) |

**Feature Application Flow:**
1. Parse namespaces from OCI bundle config.json
2. Detect user namespace (if present)
3. Create container with `pct create` (unprivileged mode)
4. Apply features via `pct set --features` based on namespace types

### Environment Variables

```
process.env → lxc.environment.KEY=VALUE
```

Configured via `pct set <vmid> --set lxc.environment.KEY=VALUE`

## Error Handling

### Common Errors

- `ContainerExists` - Container with same ID already exists
- `BundleNotFound` - Bundle directory not found
- `InvalidConfig` - config.json is invalid or missing
- `VmidGenerationFailed` - Cannot generate unique VMID
- `LxcCreateFailed` - pct create command failed

### Validation

Before creation:
1. Check bundle directory exists
2. Verify config.json is present and valid
3. Verify rootfs directory exists
4. Check container ID is not already used

## Integration with Containerd

NexCage can be used as OCI runtime with containerd:

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage.options]
    BinaryName = "/usr/local/bin/nexcage"
```

## Testing

Run tests:
```bash
zig build test
```

Specific tests:
```bash
# Mapping tests
zig test tests/oci_mapping_test.zig

# State manager tests
zig test tests/oci_state_manager_test.zig
```

## Troubleshooting

### Container creation fails

1. Check Proxmox VE is running: `systemctl status pve-cluster`
2. Verify pct is available: `which pct`
3. Check permissions: user must have access to pct commands
4. Review logs: `/var/log/nexcage/runtime.log`

### VMID collision

If VMID generation consistently fails:
- Check `/var/lib/nexcage/state/mapping.json` for corruption
- Manually clean up orphaned VMIDs: `pct destroy <vmid>`
- Clear mapping file if needed (backup first!)

### State file corruption

```bash
# Backup and reset state
sudo cp -r /var/lib/nexcage/state /var/lib/nexcage/state.backup
sudo rm -rf /var/lib/nexcage/state/*
```

## Performance

- VMID generation: O(1) average, O(n) worst case with collisions
- State persistence: ~1ms per operation
- LXC creation: 2-5 seconds depending on rootfs size

## Security Considerations

- Unprivileged containers by default
- User namespace isolation
- Capability dropping
- Seccomp profiles (future)
- AppArmor integration (future)

## Future Enhancements

- [ ] Advanced mount options (bind, tmpfs, etc.)
- [ ] Capability management
- [ ] Seccomp profile support
- [ ] Resource limits (blkio, pids, etc.)
- [ ] Hook execution (prestart, poststart, etc.)
- [ ] Checkpoint/restore integration
- [ ] Network configuration options
