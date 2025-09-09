# Proxmox LXCRI Installation Guide

This guide covers all installation methods for Proxmox LXCRI v0.3.0 with revolutionary ZFS checkpoint/restore functionality.

## 📦 Installation Methods

### Method 1: DEB Package (Recommended for Ubuntu/Debian)

#### Prerequisites
- Ubuntu 20.04+ or Debian 11+ 
- ZFS utils for optimal performance: `sudo apt install zfsutils-linux`
- CRIU for fallback support: `sudo apt install criu`

#### Installation Steps

1. **Download DEB Package**:
   ```bash
   # For x86_64 (amd64)
   wget https://github.com/kubebsd/proxmox-lxcri/releases/latest/download/proxmox-lxcri_0.3.0-1_amd64.deb
   
   # For ARM64
   wget https://github.com/kubebsd/proxmox-lxcri/releases/latest/download/proxmox-lxcri_0.3.0-1_arm64.deb
   ```

2. **Install Package**:
   ```bash
   sudo dpkg -i proxmox-lxcri_0.3.0-1_amd64.deb
   sudo apt-get install -f  # Fix any dependency issues
   ```

3. **Configure Proxmox Credentials**:
   ```bash
   sudo nano /etc/proxmox-lxcri/proxmox-lxcri.json
   ```
   
   Update the configuration:
   ```json
   {
     "proxmox": {
       "hosts": ["your-proxmox-host.local"],
       "port": 8006,
       "token": "YOUR-API-TOKEN",
       "node": "your-node-name"
     }
   }
   ```

4. **Start Service**:
   ```bash
   sudo systemctl enable proxmox-lxcri
   sudo systemctl start proxmox-lxcri
   sudo systemctl status proxmox-lxcri
   ```

5. **Verify Installation**:
   ```bash
   proxmox-lxcri version
   proxmox-lxcri help
   ```

#### DEB Package Benefits
- ✅ **Automatic dependency management**
- ✅ **System integration** (systemd service, user accounts)
- ✅ **Easy updates** via `apt upgrade`
- ✅ **Man pages and documentation** included
- ✅ **Bash completion** enabled
- ✅ **Proper file permissions** and security

### Method 2: Binary Installation

#### Download Binary
```bash
# x86_64 Linux
wget https://github.com/kubebsd/proxmox-lxcri/releases/latest/download/proxmox-lxcri-linux-x86_64
chmod +x proxmox-lxcri-linux-x86_64
sudo mv proxmox-lxcri-linux-x86_64 /usr/local/bin/proxmox-lxcri

# ARM64 Linux  
wget https://github.com/kubebsd/proxmox-lxcri/releases/latest/download/proxmox-lxcri-linux-aarch64
chmod +x proxmox-lxcri-linux-aarch64
sudo mv proxmox-lxcri-linux-aarch64 /usr/local/bin/proxmox-lxcri
```

#### Manual Configuration
```bash
# Create directories
sudo mkdir -p /etc/proxmox-lxcri
sudo mkdir -p /var/lib/proxmox-lxcri
sudo mkdir -p /var/log/proxmox-lxcri

# Create configuration
sudo tee /etc/proxmox-lxcri/config.json << 'EOF'
{
  "proxmox": {
    "hosts": ["proxmox.example.com"],
    "port": 8006,
    "token": "YOUR-API-TOKEN",
    "node": "your-node"
  }
}
EOF
```

### Method 3: Build from Source

#### Prerequisites
```bash
# Install Zig 0.13.0
curl -L https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz | tar -xJ
sudo mv zig-linux-x86_64-0.13.0 /opt/zig
sudo ln -sf /opt/zig/zig /usr/local/bin/zig
```

#### Build Steps
```bash
git clone https://github.com/kubebsd/proxmox-lxcri.git
cd proxmox-lxcri
git checkout v0.3.0

# Build optimized release
zig build -Doptimize=ReleaseFast

# Install binary
sudo cp zig-out/bin/proxmox-lxcri /usr/local/bin/
```

## 🔧 Post-Installation Configuration

### ZFS Setup for Optimal Performance

1. **Create Container Datasets**:
   ```bash
   # Create base dataset
   sudo zfs create tank/containers
   
   # Enable compression for space efficiency
   sudo zfs set compression=lz4 tank/containers
   
   # Optional: Enable deduplication (use carefully)
   sudo zfs set dedup=on tank/containers
   ```

2. **Test ZFS Integration**:
   ```bash
   # Check ZFS availability
   proxmox-lxcri checkpoint --help | grep -i zfs
   
   # Verify ZFS detection in logs
   sudo journalctl -u proxmox-lxcri -f
   ```

### Proxmox API Token Setup

1. **Create API Token in Proxmox**:
   - Log into Proxmox web interface
   - Go to Datacenter → Permissions → API Tokens
   - Add new token with sufficient privileges

2. **Test API Connection**:
   ```bash
   # Test with debug output
   proxmox-lxcri --debug list
   ```

### Container Runtime Configuration

#### For Containerd Integration
```bash
# Add to /etc/containerd/config.toml
sudo tee -a /etc/containerd/config.toml << 'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.proxmox-lxcri]
  runtime_type = "io.containerd.proxmox-lxcri.v1"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.proxmox-lxcri.options]
    BinaryName = "/usr/bin/proxmox-lxcri"
EOF

sudo systemctl restart containerd
```

#### For Kubernetes Integration
```yaml
# runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: proxmox-lxcri
handler: proxmox-lxcri
```

## ✅ Verification and Testing

### Basic Functionality Test
```bash
# Check version
proxmox-lxcri version

# Test help system
proxmox-lxcri help
proxmox-lxcri help checkpoint
proxmox-lxcri help restore

# List containers (requires Proxmox connection)
proxmox-lxcri list
```

### ZFS Checkpoint/Restore Test
```bash
# Create test container (example)
proxmox-lxcri create --bundle /path/to/test-bundle test-container
proxmox-lxcri start test-container

# Test checkpoint
proxmox-lxcri checkpoint test-container

# Test restore
proxmox-lxcri restore test-container

# Check ZFS snapshots
sudo zfs list -t snapshot | grep test-container
```

### Service Health Check
```bash
# Check service status
sudo systemctl status proxmox-lxcri

# View logs
sudo journalctl -u proxmox-lxcri -f

# Check resource usage
sudo systemctl show proxmox-lxcri --property=MemoryCurrent
```

## 📋 Configuration Reference

### Main Configuration File
Location: `/etc/proxmox-lxcri/proxmox-lxcri.json`

```json
{
  "proxmox": {
    "hosts": ["proxmox1.local", "proxmox2.local"],
    "port": 8006,
    "token": "YOUR-API-TOKEN",
    "node": "your-node-name",
    "node_cache_duration": 60,
    "verify_ssl": false
  },
  "runtime": {
    "root": "/run/proxmox-lxcri",
    "log_level": "info",
    "log_format": "text",
    "systemd_cgroup": true
  },
  "zfs": {
    "enabled": true,
    "auto_detect": true,
    "base_dataset": "tank/containers",
    "compression": "lz4",
    "snapshot_retention": {
      "max_snapshots": 10,
      "retention_days": 30,
      "auto_cleanup": true
    }
  },
  "checkpoint": {
    "default_mode": "zfs",
    "fallback_to_criu": true,
    "criu_path": "/usr/sbin/criu",
    "image_path": "/var/lib/proxmox-lxcri/checkpoints"
  }
}
```

### Environment Variables
```bash
# Override config file location
export PROXMOX_LXCRI_CONFIG=/path/to/config.json

# Set runtime root directory
export PROXMOX_LXCRI_ROOT=/custom/runtime/path

# Enable debug logging
export PROXMOX_LXCRI_DEBUG=true
```

## 🔄 Updates and Maintenance

### Updating DEB Package
```bash
# Check for updates
apt list --upgradable | grep proxmox-lxcri

# Update package
sudo apt update
sudo apt upgrade proxmox-lxcri

# Restart service after update
sudo systemctl restart proxmox-lxcri
```

### Updating Binary Installation
```bash
# Download new version
wget https://github.com/kubebsd/proxmox-lxcri/releases/latest/download/proxmox-lxcri-linux-x86_64

# Replace binary
sudo systemctl stop proxmox-lxcri
sudo cp proxmox-lxcri-linux-x86_64 /usr/local/bin/proxmox-lxcri
sudo systemctl start proxmox-lxcri
```

### Log Rotation (DEB Package)
```bash
# Log rotation is automatically configured
cat /etc/logrotate.d/proxmox-lxcri

# Manual log rotation
sudo logrotate -f /etc/logrotate.d/proxmox-lxcri
```

## 🚨 Troubleshooting

### Common Issues

#### ZFS Not Available
```bash
# Install ZFS utils
sudo apt install zfsutils-linux

# Check ZFS status
sudo zfs version
sudo zpool status
```

#### Service Won't Start
```bash
# Check service logs
sudo journalctl -u proxmox-lxcri -n 50

# Check configuration
proxmox-lxcri --debug help

# Test configuration
sudo -u proxmox-lxcri proxmox-lxcri version
```

#### Proxmox Connection Issues
```bash
# Test API connectivity
curl -k -H "Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET" \
  https://proxmox-host:8006/api2/json/version

# Check firewall settings
sudo ufw status
sudo iptables -L
```

### Getting Help

- **Documentation**: `/usr/share/doc/proxmox-lxcri/` (DEB package)
- **GitHub Issues**: https://github.com/kubebsd/proxmox-lxcri/issues
- **ZFS Guide**: `/usr/share/doc/proxmox-lxcri/zfs-checkpoint-guide.md`

## 📚 Next Steps

1. **Configure ZFS datasets** for optimal checkpoint/restore performance
2. **Set up monitoring** with Prometheus metrics (coming in v0.4.0)
3. **Integrate with Kubernetes** using RuntimeClass
4. **Explore advanced features** in the ZFS checkpoint guide
5. **Join the community** for support and contributions

---

**🎉 Welcome to Proxmox LXCRI v0.3.0!**

Experience revolutionary ZFS checkpoint/restore functionality with enterprise-grade container runtime performance.
