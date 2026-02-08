# Containerd Integration Guide

This guide explains how to integrate NexCage with containerd as an OCI runtime.

## Overview

NexCage can be configured as a containerd runtime, allowing containerd to use NexCage for container lifecycle management. This enables:

- Kubernetes integration via CRI
- Docker compatibility (via containerd backend)
- Standard OCI runtime interface
- Proxmox VE backend for containers

## Prerequisites

- containerd 1.6.0 or later
- NexCage 0.7.0 or later
- Proxmox VE 7.0+ (for LXC backend)
- Root/sudo access

## Installation

### 1. Install containerd

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y containerd

# Verify installation
containerd --version
```

### 2. Install NexCage

```bash
# Build from source
cd /path/to/nexcage
zig build -Doptimize=ReleaseFast

# Install binary
sudo cp zig-out/bin/nexcage /usr/local/bin/
sudo chmod +x /usr/local/bin/nexcage

# Verify installation
nexcage version
```

### 3. Create NexCage Configuration

```bash
# Create config directory
sudo mkdir -p /etc/nexcage

# Create configuration
sudo cat > /etc/nexcage/config.json <<'EOF'
{
  "proxmox": {
    "host": "localhost",
    "node": "pve1"
  },
  "storage": {
    "type": "zfs",
    "pool": "rpool",
    "dataset": "containers"
  },
  "network": {
    "bridge": "vmbr0"
  },
  "logging": {
    "level": "info",
    "file": "/var/log/nexcage/nexcage.log"
  }
}
EOF
```

## Containerd Configuration

### Configure NexCage as Runtime

Edit `/etc/containerd/config.toml`:

```toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  # Enable CRI plugin
  
[plugins."io.containerd.grpc.v1.cri".containerd]
  # Default runtime
  default_runtime_name = "runc"
  
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
  
    # Standard runc runtime
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      runtime_type = "io.containerd.runc.v2"
      
    # NexCage runtime using crun backend
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage]
      runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage.options]
        BinaryName = "/usr/local/bin/nexcage"
        Root = "/var/run/nexcage"
        
    # NexCage with LXC backend
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage-lxc]
      runtime_type = "io.containerd.runc.v2"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage-lxc.options]
        BinaryName = "/usr/local/bin/nexcage"
        Root = "/var/run/nexcage"
        SystemdCgroup = true
```

### Restart containerd

```bash
sudo systemctl restart containerd
sudo systemctl status containerd
```

## Usage with containerd

### Using ctr (containerd CLI)

```bash
# Pull an image
sudo ctr image pull docker.io/library/nginx:alpine

# Create container with NexCage runtime
sudo ctr run \
  --runtime io.containerd.runc.v2 \
  --runtime-config-path /etc/nexcage/config.json \
  docker.io/library/nginx:alpine nginx-test

# List containers
sudo ctr containers list

# Delete container
sudo ctr container delete nginx-test
```

### Using crictl (CRI CLI)

```bash
# Configure crictl
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Pull image
sudo crictl pull nginx:alpine

# Create pod sandbox
cat > pod-config.json <<'EOF'
{
  "metadata": {
    "name": "nginx-sandbox",
    "namespace": "default",
    "uid": "hdishd83djaidwnduwk28bcsb"
  },
  "linux": {}
}
EOF

POD_ID=$(sudo crictl runp --runtime=nexcage pod-config.json)

# Create container
cat > container-config.json <<'EOF'
{
  "metadata": {
    "name": "nginx"
  },
  "image": {
    "image": "nginx:alpine"
  },
  "command": [
    "nginx",
    "-g",
    "daemon off;"
  ]
}
EOF

CONTAINER_ID=$(sudo crictl create $POD_ID container-config.json pod-config.json)

# Start container
sudo crictl start $CONTAINER_ID

# List containers
sudo crictl ps

# Stop and remove
sudo crictl stop $CONTAINER_ID
sudo crictl rm $CONTAINER_ID
sudo crictl stopp $POD_ID
sudo crictl rmp $POD_ID
```

## Kubernetes Integration

### Configure kubelet to use NexCage

Edit kubelet configuration (usually `/var/lib/kubelet/config.yaml`):

```yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
containerRuntime: remote
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
```

### Create RuntimeClass

```yaml
# runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nexcage
handler: nexcage
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nexcage-lxc
handler: nexcage-lxc
```

Apply:

```bash
kubectl apply -f runtime-class.yaml
```

### Deploy Pod with NexCage Runtime

```yaml
# nginx-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  runtimeClassName: nexcage
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
```

Deploy:

```bash
kubectl apply -f nginx-pod.yaml
kubectl get pods
kubectl describe pod nginx
```

## Verification

### Test Runtime Selection

```bash
# Verify NexCage is available
sudo ctr plugin ls | grep nexcage

# Test container creation
sudo ctr run --rm --runtime=nexcage docker.io/library/alpine:latest test-container sh -c "echo 'Hello from NexCage'"
```

### Check Logs

```bash
# Containerd logs
sudo journalctl -u containerd -f

# NexCage logs
sudo tail -f /var/log/nexcage/nexcage.log
```

## Troubleshooting

### Runtime Not Found

```bash
# Check containerd config
sudo containerd config dump | grep -A 10 runtimes

# Verify nexcage binary
which nexcage
nexcage version
```

### Permission Issues

```bash
# Ensure proper permissions
sudo chmod +x /usr/local/bin/nexcage
sudo mkdir -p /var/run/nexcage
sudo chmod 755 /var/run/nexcage
```

### Container Creation Fails

```bash
# Enable debug logging in containerd
sudo cat > /etc/containerd/config.toml <<EOF
[debug]
  level = "debug"
EOF

sudo systemctl restart containerd

# Check logs
sudo journalctl -u containerd -n 100 --no-pager
```

## Best Practices

### 1. Use Runtime Classes

Define different runtime classes for different workload types:

- `nexcage-lxc` - For Proxmox LXC containers
- `nexcage-crun` - For standard OCI containers with crun
- `runc` - Fallback to standard runc

### 2. Resource Limits

Always set resource limits in pod specifications:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "500m"
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

### 3. Monitoring

Monitor container runtime metrics:

```bash
# Container stats via crictl
sudo crictl stats

# NexCage specific metrics
nexcage list
```

## Performance Tuning

### Optimize containerd

```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri"]
  max_container_log_line_size = 16384
  
[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"
```

### Optimize NexCage

```json
{
  "performance": {
    "parallel_operations": true,
    "cache_enabled": true,
    "max_concurrent_containers": 100
  }
}
```

## Related Documentation

- [CLI Reference](../CLI_REFERENCE.md)
- [Kubernetes CRI Integration](KUBERNETES_CRI.md)
- [Architecture Overview](../architecture/OVERVIEW.md)
- [Troubleshooting Guide](../TROUBLESHOOTING_GUIDE.md)
