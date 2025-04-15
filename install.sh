#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Install dependencies
if [ -f /etc/debian_version ]; then
    apt-get update
    apt-get install -y protobuf-compiler libgrpc-dev libgrpc++-dev libgrpc++1 libgrpc-dev libprotobuf-dev libprotobuf-lite23 libprotobuf23 libprotoc23
elif [ -f /etc/redhat-release ]; then
    dnf install -y protobuf-compiler grpc-devel grpc-cpp-devel
fi

# Install development dependencies
if [ -f /etc/debian_version ]; then
    apt-get install -y git make curl docker.io
elif [ -f /etc/redhat-release ]; then
    dnf install -y git make curl docker
fi

# Install GitHub CLI
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update
    apt-get install -y gh
fi

# Install act
if ! command -v act &> /dev/null; then
    curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
fi

# Create directories
mkdir -p /etc/proxmox-lxcri
mkdir -p /var/log/proxmox-lxcri
mkdir -p /usr/local/bin

# Build the project
zig build -Doptimize=ReleaseSafe

# Install binary
cp zig-out/bin/proxmox-lxcri /usr/local/bin/
chmod +x /usr/local/bin/proxmox-lxcri

# Install configuration
if [ ! -f /etc/proxmox-lxcri/config.json ]; then
    cp config.json /etc/proxmox-lxcri/
fi

# Install systemd service
cp proxmox-lxcri.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable proxmox-lxcri.service

# Set permissions
chown root:root /usr/local/bin/proxmox-lxcri
chmod 755 /usr/local/bin/proxmox-lxcri
chown -R root:root /etc/proxmox-lxcri
chmod 644 /etc/proxmox-lxcri/config.json
chown root:root /etc/systemd/system/proxmox-lxcri.service
chmod 644 /etc/systemd/system/proxmox-lxcri.service

echo "Installation complete!"
echo "Please edit /etc/proxmox-lxcri/config.json to set your Proxmox API token"
echo "Then start the service with: systemctl start proxmox-lxcri" 