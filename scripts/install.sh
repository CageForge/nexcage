#!/bin/bash

set -e

# Check root privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run the script as root"
    exit 1
fi

# Install dependencies
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

# Configure CRI-O
mkdir -p /etc/crio/crio.conf.d
cp crio.conf.d/10-nexcage.conf /etc/crio/crio.conf.d/

# Configure Kubelet
mkdir -p /etc/kubernetes
cp kubelet.conf /etc/kubernetes/

# Install Proxmox LXCRI
cp zig-out/bin/nexcage /usr/local/bin/
chmod +x /usr/local/bin/nexcage

# Create system service
cp nexcage.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable nexcage
systemctl start nexcage

# Configure CNI
mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz | tar -C /opt/cni/bin -xz

# Configure Cilium
curl -L https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz | tar -xz
mv cilium /usr/local/bin/

# Create Proxmox LXCRI directories
mkdir -p /run/nexcage
mkdir -p /var/log/nexcage

# Configure logging
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

echo "Installation completed successfully!"
echo "Restart services:"
echo "systemctl restart crio kubelet nexcage" 