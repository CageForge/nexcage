# Installing Proxmox LXCRI

## Requirements

- Proxmox VE 7.0 or newer
- Zig 0.11.0 or newer
- ZFS utilities
- Linux kernel 5.0 or newer
- CRI-O
- Kubelet
- CNI plugins

## Automatic Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/proxmox-lxcri.git
cd proxmox-lxcri
```

2. Build the project:
```bash
zig build -Doptimize=ReleaseFast
```

3. Run the installation script:
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
cp crio.conf.d/10-proxmox-lxcri.conf /etc/crio/crio.conf.d/
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
cp zig-out/bin/proxmox-lxcri /usr/local/bin/
chmod +x /usr/local/bin/proxmox-lxcri
```

2. Install system service:
```bash
cp proxmox-lxcri.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable proxmox-lxcri
systemctl start proxmox-lxcri
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
mkdir -p /run/proxmox-lxcri
mkdir -p /var/log/proxmox-lxcri
```

2. Configure log rotation:
```bash
cat > /etc/logrotate.d/proxmox-lxcri << EOF
/var/log/proxmox-lxcri/*.log {
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
systemctl restart crio kubelet proxmox-lxcri
```

## Verify Installation

1. Check service status:
```bash
systemctl status proxmox-lxcri
systemctl status crio
systemctl status kubelet
```

2. Check version:
```bash
proxmox-lxcri --version
```

3. Check Proxmox connection:
```bash
proxmox-lxcri info
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
journalctl -u proxmox-lxcri -f
```

## Additional Information

- [Architecture](architecture.md)
- [Configuration](configuration.md)
- [Security](security.md)
- [Monitoring](monitoring.md) 