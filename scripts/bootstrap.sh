#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Print status message
print_status() {
    echo -e "${GREEN}[*]${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}[!]${NC} $1"
}

# Print warning message
print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
else
    print_error "Could not detect OS"
    exit 1
fi

# Install dependencies based on OS
print_status "Installing dependencies for $OS $VER"

case $OS in
    "Ubuntu" | "Debian GNU/Linux")
        apt-get update
        apt-get install -y \
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
        ;;
    "Fedora" | "CentOS Linux" | "Red Hat Enterprise Linux")
        dnf install -y \
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
        ;;
    *)
        print_error "Unsupported OS: $OS"
        exit 1
        ;;
esac

# Install Zig
print_status "Installing Zig 0.11.0"

ZIG_VERSION="0.11.0"
ZIG_DIR="/opt/zig"
ZIG_TAR="zig-linux-x86_64-$ZIG_VERSION.tar.xz"

if [ ! -d "$ZIG_DIR" ]; then
    mkdir -p "$ZIG_DIR"
    wget "https://ziglang.org/download/$ZIG_VERSION/$ZIG_TAR"
    tar -xf "$ZIG_TAR" -C "$ZIG_DIR" --strip-components=1
    rm "$ZIG_TAR"
fi

# Add Zig to PATH
if ! grep -q "export PATH=\$PATH:$ZIG_DIR" ~/.bashrc; then
    echo "export PATH=\$PATH:$ZIG_DIR" >> ~/.bashrc
    source ~/.bashrc
fi

# Clone repository
print_status "Cloning repository"

REPO_DIR="/opt/proxmox-lxcri"
if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/your-org/proxmox-lxcri.git "$REPO_DIR"
    cd "$REPO_DIR"
else
    cd "$REPO_DIR"
    git pull
fi

# Build project
print_status "Building project"

zig build

# Create configuration directory
print_status "Creating configuration directory"

CONFIG_DIR="/etc/proxmox-lxcri"
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    cp config.example.json "$CONFIG_DIR/config.json"
fi

# Create runtime directory
print_status "Creating runtime directory"

RUNTIME_DIR="/run/proxmox-lxcri"
if [ ! -d "$RUNTIME_DIR" ]; then
    mkdir -p "$RUNTIME_DIR"
fi

# Create ZFS pool if not exists
print_status "Checking ZFS pool"

POOL_NAME="proxmox-lxcri"
if ! zpool list "$POOL_NAME" >/dev/null 2>&1; then
    print_warning "ZFS pool '$POOL_NAME' not found"
    print_warning "Please create it manually with:"
    print_warning "zpool create $POOL_NAME /dev/your-disk"
fi

# Create systemd service
print_status "Creating systemd service"

SERVICE_FILE="/etc/systemd/system/proxmox-lxcri.service"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Proxmox LXCRI Container Runtime
After=network.target

[Service]
Type=simple
ExecStart=$REPO_DIR/zig-out/bin/proxmox-lxcri --config $CONFIG_DIR/config.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

print_status "Installation complete!"
print_status "Next steps:"
print_status "1. Configure ZFS pool: zpool create $POOL_NAME /dev/your-disk"
print_status "2. Edit configuration: $CONFIG_DIR/config.json"
print_status "3. Start service: systemctl start proxmox-lxcri"
print_status "4. Enable service: systemctl enable proxmox-lxcri" 