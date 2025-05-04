# Proxmox LXCRI Onboarding Guide

## Prerequisites

Before starting, ensure you have:
- A Linux system (Ubuntu/Debian or RHEL/CentOS/Fedora)
- Root access
- At least 10GB of free disk space
- A disk or partition for ZFS pool

## Quick Start

For a quick setup, run the bootstrap script:

```bash
# Download and run bootstrap script
curl -O https://raw.githubusercontent.com/your-org/proxmox-lxcri/main/scripts/bootstrap.sh
chmod +x bootstrap.sh
sudo ./bootstrap.sh
```

## Manual Setup

### 1. System Requirements

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    zfsutils-linux \
    libzfs-dev \
    libproxmox-backup-qemu0-dev \
    gdb \
    strace \
    tcpdump \
    valgrind \
    linux-tools-common \
    linux-tools-generic
```

#### RHEL/CentOS/Fedora
```bash
sudo dnf install -y \
    gcc \
    gcc-c++ \
    make \
    git \
    curl \
    wget \
    zfs \
    libzfs \
    gdb \
    strace \
    tcpdump \
    valgrind \
    perf
```

### 2. Install Zig

```bash
# Download Zig
ZIG_VERSION="0.11.0"
ZIG_DIR="/opt/zig"
sudo mkdir -p "$ZIG_DIR"
cd "$ZIG_DIR"
sudo wget "https://ziglang.org/download/$ZIG_VERSION/zig-linux-x86_64-$ZIG_VERSION.tar.xz"
sudo tar -xf "zig-linux-x86_64-$ZIG_VERSION.tar.xz" --strip-components=1
sudo rm "zig-linux-x86_64-$ZIG_VERSION.tar.xz"

# Add to PATH
echo "export PATH=\$PATH:$ZIG_DIR" >> ~/.bashrc
source ~/.bashrc
```

### 3. Clone Repository

```bash
REPO_DIR="/opt/proxmox-lxcri"
sudo mkdir -p "$REPO_DIR"
sudo chown $USER:$USER "$REPO_DIR"
git clone https://github.com/your-org/proxmox-lxcri.git "$REPO_DIR"
cd "$REPO_DIR"
```

### 4. Build Project

```bash
zig build
```

### 5. Configure ZFS

```bash
# Create ZFS pool
sudo zpool create proxmox-lxcri /dev/your-disk

# Verify pool
sudo zpool status
```

### 6. Configure Runtime

```bash
# Create config directory
sudo mkdir -p /etc/proxmox-lxcri
sudo cp config.example.json /etc/proxmox-lxcri/config.json

# Create runtime directory
sudo mkdir -p /run/proxmox-lxcri
```

### 7. Start Service

```bash
# Create systemd service
sudo tee /etc/systemd/system/proxmox-lxcri.service << EOF
[Unit]
Description=Proxmox LXCRI Container Runtime
After=network.target

[Service]
Type=simple
ExecStart=/opt/proxmox-lxcri/zig-out/bin/proxmox-lxcri --config /etc/proxmox-lxcri/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload and start service
sudo systemctl daemon-reload
sudo systemctl start proxmox-lxcri
sudo systemctl enable proxmox-lxcri
```

## Development Environment

### 1. IDE Setup

#### VS Code
1. Install VS Code
2. Install Zig extension
3. Configure settings:
```json
{
    "zig.path": "/opt/zig/zig",
    "zig.buildRunnerPath": "/opt/zig/zig",
    "zig.formattingProvider": "zigfmt"
}
```

### 2. Debugging Setup

#### GDB Configuration
```bash
# Create .gdbinit
echo "set auto-load safe-path /" > ~/.gdbinit
```

#### Debug Build
```bash
zig build -Doptimize=Debug
```

### 3. Testing Environment

```bash
# Run tests
zig build test

# Run specific test
zig build test --test-filter "HookExecutor"

# Run integration tests
zig build test_integration
```

## Learning Resources

### Documentation
- [Architecture Overview](architecture.md)
- [Technical Stack](tech_stack.md)
- [Development Guide](dev_guide.md)

### External Resources
- [Zig Documentation](https://ziglang.org/documentation/master/)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [containerd Documentation](https://containerd.io/docs/)

## Common Issues

### 1. ZFS Pool Creation
```bash
# Check available disks
lsblk

# Create pool with specific disk
sudo zpool create proxmox-lxcri /dev/sdX
```

### 2. Build Errors
```bash
# Clean build
rm -rf zig-cache zig-out
zig build
```

### 3. Service Issues
```bash
# Check service status
sudo systemctl status proxmox-lxcri

# Check logs
sudo journalctl -u proxmox-lxcri -f
```

## Next Steps

1. Read the [Architecture Overview](architecture.md)
2. Review the [Technical Stack](tech_stack.md)
3. Follow the [Development Guide](dev_guide.md)
4. Start with a simple task from the issue tracker
5. Join the development chat/forum
6. Attend team meetings and standups 