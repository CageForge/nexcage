# NexCage Backend Plugins

This directory contains all backend plugins for the NexCage container runtime system.

## Available Backend Plugins

### 1. Crun Backend Plugin (`crun-plugin/`)
- **Runtime**: OCI container runtime using crun
- **Dependencies**: `crun >= 1.0.0`
- **Use Case**: High-performance OCI containers
- **Priority**: 10 (highest)

### 2. Runc Backend Plugin (`runc-plugin/`)
- **Runtime**: OCI container runtime using runc
- **Dependencies**: `runc >= 1.0.0`
- **Use Case**: Standard OCI containers
- **Priority**: 20

### 3. Proxmox LXC Backend Plugin (`proxmox-lxc-plugin/`)
- **Runtime**: LXC containers via Proxmox VE
- **Dependencies**: `pct >= 6.0.0`, Proxmox VE
- **Use Case**: Enterprise LXC containers with Proxmox management
- **Priority**: 30

### 4. Proxmox VM Backend Plugin (`proxmox-vm-plugin/`)
- **Runtime**: VM-based containers via Proxmox VE
- **Dependencies**: `qm >= 6.0.0`, Proxmox VE, KVM/QEMU
- **Use Case**: VM-isolated containers for maximum security
- **Priority**: 40

## Plugin Structure

Each plugin directory contains:
```
{backend-name}-plugin/
├── plugin.zig          # Plugin implementation
├── plugin.json         # Plugin metadata
└── README.md           # Plugin documentation
```

## Backend Selection

Backends are selected by priority (lower number = higher priority):
1. **crun-backend** (10) - Fastest OCI runtime
2. **runc-backend** (20) - Standard OCI runtime  
3. **proxmox-lxc-backend** (30) - Enterprise LXC
4. **proxmox-vm-backend** (40) - VM isolation

## Configuration

Each backend can be configured individually:

```yaml
plugins:
  crun-backend:
    enabled: true
    priority: 10
    
  proxmox-lxc-backend:
    enabled: true
    priority: 30
    config:
      proxmox_host: "pve.example.com"
      proxmox_token: "${PROXMOX_TOKEN}"
```

## Usage

```bash
# List available backends
nexcage backend list

# Get backend info
nexcage backend info crun-backend

# Enable/disable backends
nexcage backend enable proxmox-lxc-backend
nexcage backend disable runc-backend

# Check backend health
nexcage backend health --all
```

## Development

To create a new backend plugin:
1. Copy an existing plugin directory as template
2. Implement the `plugin.BackendExtension` interface
3. Update plugin.json metadata
4. Add tests and documentation
5. Register in backend registry

See the [Plugin Development Guide](../README.md) for detailed instructions.