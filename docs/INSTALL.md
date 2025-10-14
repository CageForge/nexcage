# Installing Proxmox LXCRI

## Requirements

- Proxmox VE 7.0 or newer
- Zig 0.15.1 or newer
- ZFS utilities
- Linux kernel 5.0 or newer
- CRI-O
- Kubelet
- CNI plugins

## Automatic Installation

### Option 1: Download Pre-built Binary

1. Download latest release:
```bash
# Get latest version
VERSION=$(curl -s https://api.github.com/repos/CageForge/nexcage/releases/latest | grep tag_name | cut -d'"' -f4 | sed 's/v//')

# Download binary and checksum
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-linux-x86_64-v$VERSION.tar.gz
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-linux-x86_64-v$VERSION.tar.gz.sha256

# Verify checksum
sha256sum -c nexcage-linux-x86_64-v$VERSION.tar.gz.sha256

# Extract and install
tar -xzf nexcage-linux-x86_64-v$VERSION.tar.gz
sudo mv nexcage /usr/local/bin/
```

2. Verify installation:
```bash
nexcage --help
nexcage version
```

### Option 2: Build from Source

1. Clone the repository:
```bash
git clone https://github.com/CageForge/nexcage.git
cd nexcage
```

2. Install dependencies:
```bash
sudo apt-get update
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

3. Install Zig 0.15.1:
```bash
# See https://ziglang.org/download/ for binary tarball
zig version  # should print 0.15.1
```

4. Build the project:
```bash
zig build -Doptimize=ReleaseFast
```

5. Run the installation script:
```bash
sudo ./scripts/install.sh
```

## Manual Installation

### 1. Install Dependencies

```bash
# Install system packages
apt-get update
apt-get install -y \
    containerd \
    cri-o \
    kubelet \
    kubeadm \
    kubectl \
    kubernetes-cni \
    zfsutils-linux \
    fuse-overlayfs
```

### 2. Configure CRI-O

1. Create configuration directory:
```bash
mkdir -p /etc/crio/crio.conf.d
```

2. Copy configuration:
```bash
cp crio.conf.d/10-nexcage.conf /etc/crio/crio.conf.d/
```

### 3. Configure Kubelet

1. Create configuration directory:
```bash
mkdir -p /etc/kubernetes
```

2. Copy configuration:
```bash
cp kubelet.conf /etc/kubernetes/
```

### 4. Install Proxmox LXCRI

1. Copy binary:
```bash
cp zig-out/bin/nexcage /usr/local/bin/
chmod +x /usr/local/bin/nexcage
```

2. Install system service:
```bash
cp nexcage.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable nexcage
systemctl start nexcage
```

### 5. Configure CNI

1. Install CNI plugins:
```bash
mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz | tar -C /opt/cni/bin -xz
```

2. Install Cilium:
```bash
curl -L https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz | tar -xz
mv cilium /usr/local/bin/
```

### 6. Configure Logging

1. Create directories:
```bash
mkdir -p /run/nexcage
mkdir -p /var/log/nexcage
```

2. Configure log rotation:
```bash
cat > /etc/logrotate.d/nexcage << EOF
/var/log/nexcage/*.log {
    daily
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF
```

### 7. Restart Services

```bash
systemctl restart crio kubelet nexcage
```

## Verify Installation

1. Check service status:
```bash
systemctl status nexcage
systemctl status crio
systemctl status kubelet
```

2. Check version:
```bash
nexcage --version
```

3. Check Proxmox connection:
```bash
nexcage info
```

## Troubleshooting

### 1. CRI-O Issues

Check logs:
```bash
journalctl -u crio -f
```

### 2. Kubelet Issues

Check logs:
```bash
journalctl -u kubelet -f
```

### 3. Proxmox LXCRI Issues

Check logs:
```bash
journalctl -u nexcage -f
```

## Additional Information

- [Architecture](architecture.md)
- [Configuration](configuration.md)
- [Security](security.md)
- [Monitoring](monitoring.md) 