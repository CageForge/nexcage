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
   wget https://github.com/cageforge/nexcage/releases/latest/download/nexcage_0.3.0-1_amd64.deb
   
   # For ARM64
   wget https://github.com/cageforge/nexcage/releases/latest/download/nexcage_0.3.0-1_arm64.deb
   ```

2. **Install Package**:
   ```bash
   sudo dpkg -i nexcage_0.3.0-1_amd64.deb
   sudo apt-get install -f  # Fix any dependency issues
   ```

3. **Configure Proxmox Credentials**:
   ```bash
   sudo nano /etc/nexcage/nexcage.json
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
   sudo systemctl enable nexcage
   sudo systemctl start nexcage
   sudo systemctl status nexcage
   ```

5. **Verify Installation**:
   ```bash
   nexcage version
   nexcage help
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
wget https://github.com/cageforge/nexcage/releases/latest/download/nexcage-linux-x86_64
chmod +x nexcage-linux-x86_64
sudo mv nexcage-linux-x86_64 /usr/local/bin/nexcage

# ARM64 Linux  
wget https://github.com/cageforge/nexcage/releases/latest/download/nexcage-linux-aarch64
chmod +x nexcage-linux-aarch64
sudo mv nexcage-linux-aarch64 /usr/local/bin/nexcage
```

#### Manual Configuration
```bash
# Create directories
sudo mkdir -p /etc/nexcage
sudo mkdir -p /var/lib/nexcage
sudo mkdir -p /var/log/nexcage

# Create configuration
sudo tee /etc/nexcage/config.json << 'EOF'
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
# Install Zig 0.15.1
curl -L https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz | tar -xJ
sudo mv zig-linux-x86_64-0.15.1 /opt/zig
sudo ln -sf /opt/zig/zig /usr/local/bin/zig
```

#### Build Steps
```bash
git clone https://github.com/cageforge/nexcage.git
cd nexcage
git checkout v0.3.0

# Build optimized release
zig build -Doptimize=ReleaseFast

# Install binary
sudo cp zig-out/bin/nexcage /usr/local/bin/
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
   nexcage checkpoint --help | grep -i zfs
   
   # Verify ZFS detection in logs
   sudo journalctl -u nexcage -f
   ```

### Proxmox API Token Setup

1. **Create API Token in Proxmox**:
   - Log into Proxmox web interface
   - Go to Datacenter → Permissions → API Tokens
   - Add new token with sufficient privileges

2. **Test API Connection**:
   ```bash
   # Test with debug output
   nexcage --debug list
   ```

### Container Runtime Configuration

#### For Containerd Integration
```bash
# Add to /etc/containerd/config.toml
sudo tee -a /etc/containerd/config.toml << 'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage]
  runtime_type = "io.containerd.nexcage.v1"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nexcage.options]
    BinaryName = "/usr/bin/nexcage"
EOF

sudo systemctl restart containerd
```

#### For Kubernetes Integration
```yaml
# runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nexcage
handler: nexcage
```

## ✅ Verification and Testing

### Basic Functionality Test
```bash
# Check version
nexcage version

# Test help system
nexcage help
nexcage help checkpoint
nexcage help restore

# List containers (requires Proxmox connection)
nexcage list
```

### ZFS Checkpoint/Restore Test
```bash
# Create test container (example)
nexcage create --bundle /path/to/test-bundle test-container
nexcage start test-container

# Test checkpoint
nexcage checkpoint test-container

# Test restore
nexcage restore test-container

# Check ZFS snapshots
sudo zfs list -t snapshot | grep test-container
```

### Service Health Check
```bash
# Check service status
sudo systemctl status nexcage

# View logs
sudo journalctl -u nexcage -f

# Check resource usage
sudo systemctl show nexcage --property=MemoryCurrent
```

## 📋 Configuration Reference

### Main Configuration File
Location: `/etc/nexcage/nexcage.json`

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
    "root": "/run/nexcage",
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
    "image_path": "/var/lib/nexcage/checkpoints"
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
apt list --upgradable | grep nexcage

# Update package
sudo apt update
sudo apt upgrade nexcage

# Restart service after update
sudo systemctl restart nexcage
```

### Updating Binary Installation
```bash
# Download new version
wget https://github.com/cageforge/nexcage/releases/latest/download/nexcage-linux-x86_64

# Replace binary
sudo systemctl stop nexcage
sudo cp nexcage-linux-x86_64 /usr/local/bin/nexcage
sudo systemctl start nexcage
```

### Log Rotation (DEB Package)
```bash
# Log rotation is automatically configured
cat /etc/logrotate.d/nexcage

# Manual log rotation
sudo logrotate -f /etc/logrotate.d/nexcage
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
sudo journalctl -u nexcage -n 50

# Check configuration
nexcage --debug help

# Test configuration
sudo -u nexcage nexcage version
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

- **Documentation**: `/usr/share/doc/nexcage/` (DEB package)
- **GitHub Issues**: https://github.com/cageforge/nexcage/issues
- **ZFS Guide**: `/usr/share/doc/nexcage/zfs-checkpoint-guide.md`

## 📚 Next Steps

1. **Configure ZFS datasets** for optimal checkpoint/restore performance
2. **Set up monitoring** with Prometheus metrics (coming in v0.4.0)
3. **Integrate with Kubernetes** using RuntimeClass
4. **Explore advanced features** in the ZFS checkpoint guide
5. **Join the community** for support and contributions

---

**🎉 Welcome to Proxmox LXCRI v0.3.0!**

Experience revolutionary ZFS checkpoint/restore functionality with enterprise-grade container runtime performance.
