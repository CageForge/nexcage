# Project Dependencies

## Core Dependencies

### Runtime Dependencies
- **Zig Compiler** (>= 0.13.0)
  - Required for building the project
  - Used for memory management and system programming

- **Proxmox VE** (>= 7.0)
  - Core virtualization platform
  - Required for LXC container management
  - Used for VM orchestration

- **ZFS Utilities**
  - Required for storage management
  - Used for snapshots and clones
  - Required for image management

- **Linux Kernel** (>= 5.0)
  - Required for container features
  - Used for cgroups and namespaces
  - Required for security features

### Development Dependencies
- **Git**
  - Required for version control
  - Used for CI/CD pipelines

- **Docker**
  - Required for build environment
  - Used for CI/CD pipelines

- **Gitleaks** (>= 8.18.1)
  - Required for security scanning
  - Used in CI/CD pipelines

## Optional Dependencies

### Security
- **AppArmor**
  - Optional for enhanced security
  - Used for container isolation

- **SELinux**
  - Optional for enhanced security
  - Used for container isolation

### Networking
- **CNI Plugins**
  - Required for container networking
  - Used for network isolation
  - Required for pod networking

### Storage
- **LXC Tools**
  - Required for container management
  - Used for container lifecycle

## Build Dependencies

### Required Tools
- **curl**
  - Required for downloading dependencies
  - Used in build scripts

- **wget**
  - Required for downloading dependencies
  - Used in build scripts

- **xz-utils**
  - Required for archive handling
  - Used in build process

### Development Tools
- **build-essential**
  - Required for compilation
  - Used in build process

## Version Management

### Fixed Versions
- Zig: 0.13.0
- Gitleaks: 8.18.1
- Proxmox VE: 7.0+

### Version Constraints
- Linux Kernel: >= 5.0
- ZFS: Latest stable version
- CNI Plugins: Latest stable version

## Installation

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    zfsutils-linux \
    lxc \
    curl \
    wget \
    xz-utils
```

### CentOS/RHEL
```bash
sudo yum install -y \
    gcc \
    git \
    zfs \
    lxc \
    curl \
    wget \
    xz
```

## Configuration

### Required Environment Variables
- `PROXMOX_LXCRI_CONFIG`: Path to configuration file
- `ZIG_PATH`: Path to Zig compiler (if not in PATH)

### Optional Environment Variables
- `PROXMOX_API_TOKEN`: Proxmox API token
- `PROXMOX_NODE`: Proxmox node name
- `ZFS_DATASET`: ZFS dataset path 