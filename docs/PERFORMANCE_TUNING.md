# Performance Tuning Guide

This guide provides recommendations for optimizing NexCage performance in production environments.

## System Requirements

### Minimum Requirements
- CPU: 2 cores
- RAM: 4 GB
- Storage: 10 GB (50GB+ recommended for production)
- Network: 1 Gbps

### Recommended Production Setup
- CPU: 8+ cores (16+ for high-density deployments)
- RAM: 16 GB+ (32GB+ for high-density)
- Storage: NVMe SSD with ZFS
- Network: 10 Gbps with dedicated bridges

## ZFS Optimization

### ZFS Pool Configuration

```bash
# Create optimized ZFS pool for containers
sudo zpool create \
  -o ashift=12 \
  -O compression=lz4 \
  -O atime=off \
  -O xattr=sa \
  -O dnodesize=auto \
  tank /dev/nvme0n1

# Create dataset for containers
sudo zfs create \
  -o mountpoint=/var/lib/nexcage \
  -o recordsize=16K \
  -o primarycache=metadata \
  -o secondarycache=all \
  tank/containers
```

### ZFS Tuning Parameters

```bash
# /etc/modprobe.d/zfs.conf
options zfs zfs_arc_max=8589934592    # 8GB ARC
options zfs zfs_arc_min=2147483648     # 2GB minimum
options zfs zfs_prefetch_disable=0     # Enable prefetch
options zfs l2arc_write_max=16777216   # 16MB L2ARC write
options zfs zfs_txg_timeout=5          # 5 second transaction group timeout
```

Apply settings:

```bash
sudo update-initramfs -u
sudo reboot
```

### Per-Container ZFS Settings

```bash
# For database containers (random I/O)
zfs set recordsize=8K tank/containers/db-container
zfs set primarycache=metadata tank/containers/db-container
zfs set logbias=throughput tank/containers/db-container

# For web servers (sequential I/O)
zfs set recordsize=128K tank/containers/web-container
zfs set compression=lz4 tank/containers/web-container

# For high-performance containers
zfs set sync=disabled tank/containers/perf-container  # Use with caution!
```

## Network Performance

### Bridge Optimization

```bash
# Disable unnecessary kernel features on bridge
sudo ip link set vmbr0 txqueuelen 10000

# Enable offloading
sudo ethtool -K vmbr0 gso on
sudo ethtool -K vmbr0 tso on
sudo ethtool -K vmbr0 gro on

# Make persistent in /etc/network/interfaces
cat >> /etc/network/interfaces <<EOF
auto vmbr0
iface vmbr0 inet static
    address 10.0.0.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-maxwait 0
    post-up ethtool -K vmbr0 gso on tso on gro on
    post-up ip link set vmbr0 txqueuelen 10000
EOF
```

### VLAN Performance

```bash
# Enable VLAN offloading on physical interface
sudo ethtool -K eth0 rxvlan on txvlan on

# Optimize VLAN interfaces
for vlan in 100 101 102; do
  sudo ip link set vmbr0.$vlan txqueuelen 5000
done
```

## CPU Optimization

### CPU Pinning

For containers requiring consistent performance:

```json
{
  "linux": {
    "resources": {
      "cpu": {
        "cpus": "0-3",
        "mems": "0"
      }
    }
  }
}
```

### NUMA Awareness

```bash
# Check NUMA topology
numactl --hardware

# Pin container to specific NUMA node
# In OCI config.json:
{
  "linux": {
    "resources": {
      "cpu": {
        "cpus": "0-15",     # First NUMA node CPUs
        "mems": "0"          # First NUMA node memory
      }
    }
  }
}
```

### CPU Governor

```bash
# Set performance governor for consistent performance
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Make persistent
sudo apt-get install cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils
```

## Memory Management

### Container Memory Limits

```json
{
  "linux": {
    "resources": {
      "memory": {
        "limit": 2147483648,        # 2GB hard limit
        "reservation": 1073741824,   # 1GB soft limit
        "swap": 1073741824           # 1GB swap
      }
    }
  }
}
```

### System Memory Tuning

```bash
# /etc/sysctl.d/99-nexcage.conf
vm.swappiness = 10                    # Prefer RAM over swap
vm.vfs_cache_pressure = 50            # Balance cache vs. other memory
vm.dirty_ratio = 15                   # Start writeback at 15% RAM
vm.dirty_background_ratio = 5         # Background writeback at 5%
vm.min_free_kbytes = 262144           # 256MB minimum free memory
vm.overcommit_memory = 1              # Allow overcommit
net.core.rmem_max = 134217728         # 128MB receive buffer
net.core.wmem_max = 134217728         # 128MB send buffer
```

Apply settings:

```bash
sudo sysctl -p /etc/sysctl.d/99-nexcage.conf
```

## I/O Optimization

### I/O Scheduler

```bash
# For NVMe (none scheduler)
echo none | sudo tee /sys/block/nvme0n1/queue/scheduler

# For SSD (mq-deadline)
echo mq-deadline | sudo tee /sys/block/sda/queue/scheduler

# For HDD (bfq)
echo bfq | sudo tee /sys/block/sdb/queue/scheduler

# Make persistent via udev
cat > /etc/udev/rules.d/60-scheduler.rules <<EOF
# NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

# SSD
ACTION=="add|change", SUBSYSTEM=="block", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDD
ACTION=="add|change", SUBSYSTEM=="block", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
```

### I/O Limits per Container

```json
{
  "linux": {
    "resources": {
      "blockIO": {
        "weight": 500,
        "throttleReadBpsDevice": [
          {
            "major": 259,
            "minor": 0,
            "rate": 104857600  # 100 MB/s
          }
        ],
        "throttleWriteBpsDevice": [
          {
            "major": 259,
            "minor": 0,
            "rate": 52428800   # 50 MB/s
          }
        ]
      }
    }
  }
}
```

## Container Density Optimization

### High-Density Configuration

For running many lightweight containers:

```json
{
  "proxmox": {
    "host": "pve.example.com",
    "node": "pve1"
  },
  "storage": {
    "type": "zfs",
    "pool": "tank",
    "dataset": "containers",
    "dedup": "off",
    "compression": "lz4"
  },
  "performance": {
    "max_concurrent_operations": 64,
    "enable_caching": true,
    "cache_size_mb": 512
  }
}
```

### Resource Overcommit Strategy

```bash
# Allow memory overcommit
echo 1 > /proc/sys/vm/overcommit_memory

# Set overcommit ratio (150%)
echo 150 > /proc/sys/vm/overcommit_ratio

# Kernel same page merging (for duplicate containers)
echo 1 > /sys/kernel/mm/ksm/run
echo 100 > /sys/kernel/mm/ksm/pages_to_scan
echo 20 > /sys/kernel/mm/ksm/sleep_millisecs
```

## Benchmarking

### Container Creation Benchmark

```bash
#!/bin/bash
# benchmark-create.sh

COUNT=10
BUNDLE="/path/to/test-bundle"

echo "=== Container Creation Benchmark ==="
echo "Creating $COUNT containers..."

START=$(date +%s%N)

for i in $(seq 1 $COUNT); do
  nexcage create --name "bench-$i" --image "$BUNDLE" --runtime crun
done

END=$(date +%s%N)
DURATION=$(( (END - START) / 1000000 ))  # Convert to ms

echo "Total time: ${DURATION}ms"
echo "Average: $(( DURATION / COUNT ))ms per container"

# Cleanup
for i in $(seq 1 $COUNT); do
  nexcage delete --name "bench-$i" 2>/dev/null || true
done
```

### I/O Performance Test

```bash
# Sequential write
dd if=/dev/zero of=/var/lib/nexcage/test bs=1M count=1024 oflag=direct

# Sequential read
dd if=/var/lib/nexcage/test of=/dev/null bs=1M iflag=direct

# Random I/O with fio
fio --name=randread --ioengine=libaio --iodepth=64 --rw=randread --bs=4k --direct=1 --size=1G --numjobs=4 --runtime=60 --group_reporting --directory=/var/lib/nexcage
```

## Monitoring Performance

### Key Performance Indicators

```bash
#!/bin/bash
# Monitor container performance

while true; do
  echo "=== $(date) ==="
  
  # Container count
  TOTAL=$(nexcage list 2>/dev/null | tail -n +2 | wc -l)
  echo "Total containers: $TOTAL"
  
  # System load
  LOAD=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs)
  echo "Load average: $LOAD"
  
  # Memory usage
  MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
  MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
  MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))
  echo "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB ($MEM_PCT%)"
  
  # ZFS ARC
  ARC_SIZE=$(cat /proc/spl/kstat/zfs/arcstats | awk '/^size/{print $3/1024/1024}')
  echo "ZFS ARC: ${ARC_SIZE}MB"
  
  echo ""
  sleep 5
done
```

## Troubleshooting Performance Issues

### High CPU Usage

```bash
# Find CPU-intensive containers
for vmid in $(pct list | tail -n +2 | awk '{print $1}'); do
  echo -n "VMID $vmid: "
  pct exec $vmid -- ps aux --sort=-%cpu | head -2 | tail -1
done

# Limit CPU for specific container
pct set <vmid> -cores 2 -cpulimit 0.5
```

### High Memory Usage

```bash
# Check container memory usage
pct list | tail -n +2 | while read line; do
  VMID=$(echo $line | awk '{print $1}')
  MEM=$(pct config $VMID | grep 'memory:' | awk '{print $2}')
  echo "VMID $VMID: ${MEM}MB configured"
done

# Reduce memory for container
pct set <vmid> -memory 1024
```

### Slow I/O

```bash
# Check I/O wait
iostat -x 1 5

# Find I/O-intensive processes
iotop -o

# Check ZFS I/O stats
zpool iostat -v tank 1
```

## Production Recommendations

### Configuration Template

```json
{
  "proxmox": {
    "host": "pve.example.com",
    "node": "pve1",
    "port": 8006,
    "api_timeout": 30
  },
  "storage": {
    "type": "zfs",
    "pool": "tank",
    "dataset": "containers",
    "compression": "lz4",
    "dedup": "off"
  },
  "network": {
    "bridge": "vmbr0",
    "mtu": 9000,
    "offload": true
  },
  "performance": {
    "max_concurrent_containers": 200,
    "cache_enabled": true,
    "parallel_operations": true
  },
  "logging": {
    "level": "info",
    "file": "/var/log/nexcage/nexcage.log",
    "max_size_mb": 100,
    "rotate_count": 10
  }
}
```

### Best Practices

1. **Use ZFS with appropriate settings** for your workload
2. **Pin critical containers** to specific CPUs/NUMA nodes
3. **Set resource limits** for all containers
4. **Monitor performance metrics** continuously
5. **Test under load** before production deployment
6. **Use NVMe storage** for best performance
7. **Separate network traffic** with VLANs
8. **Enable kernel optimizations** via sysctl
9. **Regular benchmarking** to detect degradation
10. **Scale horizontally** rather than vertically when possible

## Related Documentation

- [Architecture Overview](architecture/OVERVIEW.md)
- [User Guide](user_guide.md)
- [Monitoring Integration](integration/MONITORING.md)
- [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md)
