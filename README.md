# NexCage

NexCage is a lightweight container runtime for Proxmox VE, implementing OCI-compatible orchestration for LXC and Proxmox VMs.

## Key Features
- **OCI Compliance**: Parses OCI Runtime v1.3.0 specs (NUMA, Intel RDT, netDevices).
- **Proxmox Integration**: Direct mapping of OCI bundles to Proxmox LXC (`pct`) configurations.
- **ZFS Optimized**: Automatic ZFS dataset creation and management for container rootfs.
- **Modular Architecture**: Specialized managers for ZFS, PVE API, and OCI processing.

## Quick Start

### 1. Requirements
- **OS**: Proxmox VE 8.x/9.x host (amd64).
- **Dependencies**:
  ```bash
  sudo apt-get update && sudo apt-get install -y \
    build-essential autoconf automake libtool pkg-config \
    libyajl-dev libcap-dev libseccomp-dev libsystemd-dev
  ```

### 2. Build
Requires Zig 0.15.1.
```bash
zig build
```

### 3. Usage
```bash
# General help
./zig-out/bin/nexcage --help

# Create a container from an OCI bundle
./zig-out/bin/nexcage create --bundle /path/to/bundle <container-id>

# List containers
./zig-out/bin/nexcage list
```

## Development
To add features or fix bugs:
1. Ensure Zig 0.15.1 is in your PATH.
2. The core logic resides in `src/backends/proxmox-lxc/`.
3. Build and test using standard Zig commands: `zig build` and `zig build test`.

## Components
- **ZfsManager**: Handles ZFS datasets and properties.
- **PveClient**: Orchestrates `pct` and `pvesh` commands.
- **OciProcessor**: Translates OCI configs to LXC.

## License
MIT License. See [LICENSE](LICENSE).
