# Proxmox Kubernetes Integration

This document describes the process of setting up a Proxmox server as a Kubernetes worker node and connecting it to an existing control plane.

## Prerequisites

- Proxmox VE 7.4+
- Zig 0.13.0+
- containerd 1.7+
- ZFS 2.1+
- Linux Kernel 5.15+
- SSH access to the Proxmox server
- Kubernetes control plane access

## 1. Proxmox Server Preparation

### 1.1 Install Required Packages
```bash
# Install required packages
apt update && apt install -y \
    containerd \
    kubelet \
    kubeadm \
    kubectl \
    kubernetes-cni
```

### 1.2 Configure Containerd
```bash
# Install containerd
apt install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable systemd cgroup
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
```

### 1.3 Configure Kubelet
```bash
# Configure kubelet
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
EOF

# Restart kubelet
systemctl restart kubelet
```

## 2. Network Configuration

### 2.1 Configure CNI
```bash
# Install CNI plugins
mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz | tar -C /opt/cni/bin -xz
```

### 2.2 Configure Network Policies
```bash
# Install required packages for OVN
apt install -y openvswitch-switch

# Configure OVS
ovs-vsctl add-br br0
```

## 3. Security Configuration

### 3.1 Configure SELinux
```bash
# Install SELinux tools
apt install -y policycoreutils selinux-utils

# Configure SELinux contexts
semanage fcontext -a -t container_file_t "/var/lib/containerd(/.*)?"
restorecon -Rv /var/lib/kubelet /var/lib/containerd
```

### 3.2 Configure AppArmor
```bash
# Install AppArmor tools
apt install -y apparmor apparmor-utils

# Configure AppArmor profiles
cat > /etc/apparmor.d/containerd << EOF
#include <tunables/global>

profile containerd flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow access to required directories
  /var/lib/containerd/** rw,
  /run/containerd/** rw,
}
EOF

# Load AppArmor profile
apparmor_parser -r /etc/apparmor.d/containerd
```

## 4. Monitoring Configuration

### 4.1 Configure Metrics Collection
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: proxmox-node
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: proxmox-node
  endpoints:
  - port: metrics
    interval: 15s
```

### 4.2 Configure Logging
```bash
# Configure journald
cat > /etc/systemd/journald.conf << EOF
[Journal]
Storage=persistent
SystemMaxUse=1G
RuntimeMaxUse=100M
EOF

# Restart journald
systemctl restart systemd-journald
```

## 5. Troubleshooting

### 5.1 Common Issues

1. **Containerd Issues**:
   - Check logs: `journalctl -u containerd`
   - Check containerd configuration
   - Check service status: `systemctl status containerd`

2. **Network Issues**:
   - Check OVS status: `ovs-vsctl show`
   - Check network policies
   - Check CNI configuration

3. **Security Issues**:
   - Check SELinux status: `sestatus`
   - Check AppArmor status: `aa-status`
   - Check audit logs: `ausearch -m AVC`

### 5.2 Log Collection

```bash
# Containerd logs
journalctl -u containerd -f

# Kubelet logs
journalctl -u kubelet -f

# System logs
journalctl -f
```

## 6. Maintenance

### 6.1 Updates
```bash
# Update packages
apt update && apt upgrade -y

# Update containerd
apt update && apt install -y containerd
systemctl restart containerd

# Update Kubernetes components
apt update && apt install -y kubelet kubeadm kubectl
systemctl restart kubelet
```

### 6.2 Backup
```bash
# Create backup directory
BACKUP_DIR="/var/backups/proxmox-k8s"
mkdir -p $BACKUP_DIR

# Backup containerd
tar -czf $BACKUP_DIR/containerd-$(date +%Y%m%d).tar.gz /var/lib/containerd

# Backup kubelet
tar -czf $BACKUP_DIR/kubelet-$(date +%Y%m%d).tar.gz /var/lib/kubelet

# Backup configuration
tar -czf $BACKUP_DIR/config-$(date +%Y%m%d).tar.gz /etc/containerd /etc/kubernetes
```

### 6.3 Cleanup
```bash
# Cleanup unused images
crictl rmi --prune

# Cleanup unused containers
crictl rm --prune

# Cleanup unused volumes
rm -rf /var/lib/containerd
``` 