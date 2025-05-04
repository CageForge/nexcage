# Proxmox Kubernetes Integration

This document describes the process of setting up a Proxmox server as a Kubernetes worker node and connecting it to an existing control plane.

## Prerequisites

- Proxmox server with LXC installed
- Access to an existing Kubernetes control plane
- Network access to the control plane
- SSH access to the Proxmox server

## Integration Steps

### 1. Proxmox Server Preparation

```bash
# System update
apt update && apt upgrade -y

# Install required packages
apt install -y curl gnupg apt-transport-https ca-certificates
```

### 2. Network Configuration

### 1. Kube-OVN Integration

```bash
# Install required packages for OVN
apt install -y openvswitch-switch openvswitch-common

# Configure OVS bridge
ovs-vsctl add-br br-ovn
ovs-vsctl set bridge br-ovn protocols=OpenFlow13
ovs-vsctl set bridge br-ovn other-config:datapath-id=0000000000000001

# Configure OVN integration
cat > /etc/ovn/ovn.conf << EOF
[ovn]
ovn-nb-db=tcp:${CONTROL_PLANE_IP}:6641
ovn-sb-db=tcp:${CONTROL_PLANE_IP}:6642
EOF

# Start OVN services
systemctl enable ovn-controller
systemctl start ovn-controller

# Configure OVS to connect to OVN
ovs-vsctl set Open_vSwitch . external_ids:ovn-remote=tcp:${CONTROL_PLANE_IP}:6642
ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-type=geneve
ovs-vsctl set Open_vSwitch . external_ids:ovn-encap-ip=${NODE_IP}

# Create integration bridge
ovs-vsctl add-br br-int
ovs-vsctl set bridge br-int protocols=OpenFlow13
ovs-vsctl set bridge br-int other-config:datapath-id=0000000000000002

# Connect integration bridge to OVN
ovs-vsctl add-port br-int geneve0 -- set interface geneve0 type=geneve options:remote_ip=${CONTROL_PLANE_IP}
```

### 2. Network Configuration for Kubernetes

```bash
# Configure network bridge for Kubernetes
cat > /etc/network/interfaces.d/k8s-bridge << EOF
auto vmbr1
iface vmbr1 inet static
    address 10.0.0.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF

# Connect Kubernetes bridge to OVS
ovs-vsctl add-port br-ovn vmbr1
```

### 3. Kube-OVN CNI Configuration

```bash
# Install Kube-OVN CNI
kubectl apply -f https://raw.githubusercontent.com/kubeovn/kube-ovn/master/yamls/kube-ovn.yaml

# Configure Kube-OVN
cat > /etc/kube-ovn/config.yaml << EOF
apiVersion: kubeovn.io/v1
kind: KubeovnConfig
metadata:
  name: kubeovn-config
spec:
  defaultNetwork:
    name: ovn-default
    type: overlay
    subnet: 10.16.0.0/16
    gateway: 10.16.0.1
    excludeIps:
    - 10.16.0.1
    - 10.16.0.2
    - 10.16.0.3
  ovn:
    nb-db: tcp:${CONTROL_PLANE_IP}:6641
    sb-db: tcp:${CONTROL_PLANE_IP}:6642
EOF

# Apply Kube-OVN configuration
kubectl apply -f /etc/kubeovn/config.yaml
```

### 4. Network Verification

```bash
# Check OVS bridges
ovs-vsctl show

# Check OVN connections
ovn-nbctl show

# Check Kube-OVN status
kubectl get pods -n kube-system | grep kube-ovn

# Test network connectivity
kubectl run test-pod --image=busybox -- sleep 3600
kubectl exec -it test-pod -- ping ${CONTROL_PLANE_IP}
```

### 5. Network Troubleshooting

```bash
# Check OVS logs
journalctl -u openvswitch-switch

# Check OVN logs
journalctl -u ovn-controller

# Check Kube-OVN logs
kubectl logs -n kube-system -l app=kube-ovn-controller

# Check network connectivity
ovs-ofctl dump-flows br-ovn
ovs-ofctl dump-flows br-int
```

### 3. Kubelet Installation and Configuration

```bash
# Add Kubernetes repository
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

# Install kubelet
apt update && apt install -y kubelet kubeadm kubectl

# Configure kubelet
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=10.0.0.1 \
                   --container-runtime=remote \
                   --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \
                   --cgroup-driver=systemd
EOF
```

### 4. Containerd Configuration

```bash
# Install containerd
apt install -y containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Modify configuration for LXC support
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

### 5. Control Plane Connection

```bash
# Get join command from control plane
# (This command should be obtained from the control plane administrator)
kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>
```

### 6. Connection Verification

```bash
# Check node status
kubectl get nodes

# Check pod status
kubectl get pods -A
```

## LXC Configuration for Kubernetes

### 1. LXC Template Creation

```bash
# Create base container
pct create 100 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.gz \
    --ostype ubuntu \
    --hostname k8s-worker \
    --memory 2048 \
    --cores 2 \
    --net0 name=eth0,bridge=vmbr1,ip=10.0.0.2/24,gw=10.0.0.1

# Start container
pct start 100
```

### 2. Container Configuration

```bash
# Enter container
pct enter 100

# Install required packages
apt update && apt install -y curl gnupg apt-transport-https ca-certificates

# Install kubelet
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt update && apt install -y kubelet kubeadm kubectl
```

## Verification

1. Create a test pod:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
```

2. Verify pod is running on the new node:
```bash
kubectl get pods -o wide
```

## Troubleshooting

### Common Issues

1. **Network Issues**:
   - Check bridge configuration
   - Check routing
   - Check firewall

2. **Kubelet Issues**:
   - Check logs: `journalctl -u kubelet`
   - Check kubelet configuration
   - Check service status: `systemctl status kubelet`

3. **Containerd Issues**:
   - Check logs: `journalctl -u containerd`
   - Check containerd configuration
   - Check service status: `systemctl status containerd`

### Logging

```bash
# Kubelet logs
journalctl -u kubelet -f

# Containerd logs
journalctl -u containerd -f

# Container logs
pct logs 100
```

## Security

1. **AppArmor Configuration**:
```bash
# Create Kubernetes profile
cat > /etc/apparmor.d/k8s-worker << EOF
#include <tunables/global>

profile k8s-worker flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  
  # Allow access to required directories
  /var/lib/kubelet/** rw,
  /var/lib/containerd/** rw,
  /run/containerd/** rw,
  
  # Allow network access
  network inet stream,
  network inet dgram,
}
EOF

# Apply profile
apparmor_parser -r /etc/apparmor.d/k8s-worker
```

2. **SELinux Configuration**:
```bash
# Create context for Kubernetes
semanage fcontext -a -t container_file_t "/var/lib/kubelet(/.*)?"
semanage fcontext -a -t container_file_t "/var/lib/containerd(/.*)?"
restorecon -Rv /var/lib/kubelet /var/lib/containerd
```

## Monitoring

1. **Prometheus Configuration**:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: k8s-worker
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: kubelet
  endpoints:
  - port: metrics
    interval: 15s
```

2. **Grafana Configuration**:
- Import Kubernetes nodes dashboard
- Configure alerts for critical metrics

## Updates

1. **Kubelet Update**:
```bash
apt update && apt install -y kubelet kubeadm kubectl
systemctl restart kubelet
```

2. **Containerd Update**:
```bash
apt update && apt install -y containerd
systemctl restart containerd
```

## Backup

1. **Backup Configuration**:
```bash
# Create backup script
cat > /usr/local/bin/backup-k8s-worker.sh << EOF
#!/bin/bash
BACKUP_DIR="/backup/k8s-worker"
mkdir -p \$BACKUP_DIR
tar -czf \$BACKUP_DIR/kubelet-\$(date +%Y%m%d).tar.gz /var/lib/kubelet
tar -czf \$BACKUP_DIR/containerd-\$(date +%Y%m%d).tar.gz /var/lib/containerd
EOF

# Add to crontab
echo "0 2 * * * /usr/local/bin/backup-k8s-worker.sh" | crontab -
```

## Removal

1. **Node Removal from Cluster**:
```bash
kubectl drain <node-name> --ignore-daemonsets
kubectl delete node <node-name>
```

2. **System Cleanup**:
```bash
kubeadm reset
apt purge kubelet kubeadm kubectl
rm -rf /etc/kubernetes
rm -rf /var/lib/kubelet
rm -rf /var/lib/containerd
``` 