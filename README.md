# Proxmox LXCRI

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![CNCF Sandbox](https://img.shields.io/badge/CNCF-Sandbox-blue.svg)](https://www.cncf.io/sandbox-projects/)


An OCI-compatible runtime implementation that transforms Proxmox VE into a container and VM orchestration worker. This project serves as a drop-in replacement for runc, enabling native LXC containers and VMs to run as pods through containerd or other OCI-compatible container engines.

## Key Benefits

- Run containers using Proxmox LXC/VM backend instead of standard runc
- Leverage Proxmox VE's mature virtualization capabilities
- Use existing Proxmox infrastructure for container orchestration
- Seamless integration with containerd and Kubernetes
- Support for both LXC containers and full VMs as pods
- Native ZFS storage management
- Enterprise-grade security and isolation

## Features

- Full OCI Runtime Specification v1.0 compliance
- Native Proxmox LXC/VM lifecycle management
- ZFS-based storage with snapshots and clones
- Advanced networking with VLAN and SDN support
- Comprehensive security with AppArmor/SELinux
- High-availability with multi-node support
- Resource limits and cgroups management
- Live migration capabilities
- Node caching for improved performance

### OCI Image System
- **Advanced Layer Management**: Efficient container image layer handling with dependency resolution
- **LayerFS**: High-performance filesystem abstraction for container layers
- **Metadata Caching**: LRU-based caching system for improved performance
- **Object Pooling**: Memory-efficient layer object reuse
- **Parallel Processing**: Multi-threaded layer operations
- **Image Validation**: Comprehensive OCI image manifest and configuration validation
- **Container Creation**: Integrated container creation from OCI images with LayerFS support


## Requirements

- Zig 0.13.0 or later
- Proxmox VE 7.0 or later
- ZFS utilities
- Linux kernel 5.0 or later

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/proxmox-lxcri.git
cd proxmox-lxcri
```

2. Install dependencies:
```bash
./scripts/install-deps.sh
```

3. Build the project:
```bash
./scripts/build.sh
```

4. Configure the project:
```bash
# Edit proxmox-config.json with your settings
```

## Usage

### Container Management

```bash
# Create a container
./zig-out/bin/proxmox-lxcri create \
    --name my-container \
    --image debian:bullseye \
    --memory 512 \
    --cores 1 \
    --storage zfs

# Start a container
./zig-out/bin/proxmox-lxcri start my-container

# Stop a container
./zig-out/bin/proxmox-lxcri stop my-container

# Delete a container
./zig-out/bin/proxmox-lxcri delete my-container
```

### Image Management

```bash
# Pull an image from registry
./zig-out/bin/proxmox-lxcri image pull debian:bullseye

# Create an image from local file
./zig-out/bin/proxmox-lxcri image import my-image.raw

# Delete an image
./zig-out/bin/proxmox-lxcri image delete my-image
```

### Testing

```bash
# Run all tests
./zig-linux-x86_64-0.13.0/zig build test

# Run specific test categories
./zig-linux-x86_64-0.13.0/zig build test-performance
./zig-linux-x86_64-0.13.0/zig build test-memory
./zig-linux-x86_64-0.13.0/zig build test-integration
./zig-linux-x86_64-0.13.0/zig build test-comprehensive

# Run individual test files
./zig-linux-x86_64-0.13.0/zig test tests/oci/image/layerfs_test.zig
```

### Development
# Run tests
zig build test

# Run linter
zig build lint
```

## Building

Build the project using Zig:

```bash
zig build
```

## Configuration

The configuration file can be placed in one of these locations:

1. Path specified in `PROXMOX_LXCRI_CONFIG` environment variable
2. `/etc/proxmox-lxcri/config.json`
3. `./config.json`

Example configuration:

```json
{
    "proxmox": {
        "hosts": ["host1.example.com", "host2.example.com"],
        "port": 8006,
        "token": "YOUR-API-TOKEN",
        "node": "your-node",
        "node_cache_duration": 60
    }
}
```

## Usage

### As OCI Runtime

```bash
# Create a container
proxmox-lxcri create --bundle /path/to/bundle container-id

# Start a container
proxmox-lxcri start container-id

# Get container state
proxmox-lxcri state container-id

# Stop a container
proxmox-lxcri kill container-id

# Delete a container
proxmox-lxcri delete container-id
```

Runtime options:
- `--root` - Directory for storing container state
- `--log` - Set the log file path
- `--log-format` - Set the log format (text or json)
- `--systemd-cgroup` - Use systemd cgroup manager
- `--bundle` - Path to the root of the bundle directory
- `--pid-file` - File to write the process id to
- `--console-socket` - Path to an AF_UNIX socket to send the console FD

### With containerd

1. Configure containerd to use proxmox-lxcri:

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.proxmox-lxcri]
  runtime_type = "io.containerd.proxmox-lxcri.v1"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.proxmox-lxcri.options]
    BinaryName = "/usr/local/bin/proxmox-lxcri"
```

2. Restart containerd:

```bash
sudo systemctl restart containerd
```

## Architecture

The project consists of several key components:

1. **OCI Runtime**: Implements the OCI Runtime Specification
2. **Container Manager**: Manages container lifecycle
3. **Storage Manager**: Handles ZFS-based storage
4. **Network Manager**: Manages container networking
5. **Security Module**: Handles security features
6. **Proxmox Client**: Communicates with Proxmox VE API

## Project Status

Current progress: 99.8%

Completed features:
- Basic project structure
- Proxmox API integration
- Pod management
- Image system with ZFS support
- Network subsystem with CNI
- Security features (70%)
- Architecture optimization
- C API migration

In progress:
- Testing and documentation (90%)
- Monitoring and metrics (30%)
- CI/CD improvements (40%)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the [Apache License 2.0](LICENSE).

Proxmox LXCri is a Cloud Native Computing Foundation (CNCF) Sandbox project.

## CNCF Compliance

Proxmox LXCri adheres to the principles and standards of the Cloud Native Computing Foundation (CNCF):

- Open source and open development
- Vendor neutrality
- Focus on containers and microservices
- Support for CNCF standards
- Community and collaboration

## Code of Conduct

This project follows the [CNCF Code of Conduct](CODE_OF_CONDUCT.md). Please familiarize yourself with it before participating in the community. 
