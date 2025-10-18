# Troubleshooting Guide

## Overview

This document contains detailed instructions for diagnosing and resolving common problems that occur when working with nexcage. Use debug logging for detailed problem analysis.

## Quick Diagnostics

### 1. Basic System Check
```bash
# Check version and basic functionality
./nexcage --version
./nexcage --help

# Check available commands
./nexcage list
```

### 2. Enable Debug Mode
```bash
# Full diagnostics with logging
./nexcage --debug --log-file /tmp/nexcage-debug.log <command>
```

## Common Problems and Solutions

### 1. Container Creation Issues

#### Problem: "Container not created"
```bash
# Diagnostics
./nexcage --debug --log-file /tmp/create-debug.log create --name test-container --image ubuntu:20.04

# Log analysis
grep -E "(ERROR|WARN|Failed)" /tmp/create-debug.log
```

**Possible Causes:**
- Missing OCI bundle
- Incorrect image path
- Permission problems
- Missing dependencies

**Solutions:**
```bash
# 1. Check OCI bundle
ls -la /path/to/oci-bundle/
ls -la /path/to/oci-bundle/config.json

# 2. Check permissions
sudo chown -R $USER:$USER /var/lib/lxc/
sudo chmod -R 755 /var/lib/lxc/

# 3. Install dependencies
sudo apt-get update
sudo apt-get install lxc-utils lxc-dev
```

#### Problem: "Image not found"
```bash
# Check available images
./nexcage --debug list

# Check LXC templates
pveam list
pveam available
```

**Solutions:**
```bash
# Download template
pveam download local ubuntu-20.04-standard_20.04-1_amd64.tar.zst

# Check after download
pveam list | grep ubuntu
```

### 2. Container Startup Issues

#### Problem: "Container not starting"
```bash
# Startup diagnostics
./nexcage --debug start --name test-container

# Check status
./nexcage --debug list
```

**Possible Causes:**
- Container doesn't exist
- Configuration problems
- Missing resources
- Network problems

**Solutions:**
```bash
# 1. Check container existence
pct list | grep test-container

# 2. Check configuration
pct config 100  # replace 100 with container VMID

# 3. Check container logs
pct logs 100

# 4. Restart with detailed logging
pct start 100 --debug
```

#### Problem: "Network configuration error"
```bash
# Network diagnostics
./nexcage --debug --log-file /tmp/network-debug.log create --name net-test --image ubuntu:20.04
```

**Solutions:**
```bash
# 1. Check network interfaces
ip link show
brctl show

# 2. Check Proxmox configuration
cat /etc/pve/lxc/100.conf | grep -i net

# 3. Create bridge if needed
sudo ip link add name vmbr1 type bridge
sudo ip link set vmbr1 up
```

### 3. Performance Issues

#### Problem: "Slow command execution"
```bash
# Performance measurement
./nexcage --debug --log-file /tmp/perf.log list
./nexcage --debug --log-file /tmp/perf.log create --name perf-test --image ubuntu:20.04

# Analyze execution time
grep "completed in" /tmp/perf.log
```

**Optimization:**
```bash
# 1. Check resource usage
htop
iostat -x 1

# 2. Check disk space
df -h
du -sh /var/lib/lxc/

# 3. Clear cache
sudo sync
sudo echo 3 > /proc/sys/vm/drop_caches
```

#### Problem: "Memory issues"
```bash
# Memory tracking
export NEXCAGE_MEMORY_TRACKING=1
./nexcage --debug --log-file /tmp/memory.log list
```

**Solutions:**
```bash
# 1. Check memory usage
free -h
cat /proc/meminfo

# 2. Configure swap
sudo swapon --show
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 4. Logging Issues

#### Problem: "Logs not created"
```bash
# Check permissions
ls -la /tmp/nexcage-debug.log
ls -la /var/log/nexcage/

# Create log directory
sudo mkdir -p /var/log/nexcage
sudo chown $USER:$USER /var/log/nexcage
```

#### Problem: "Permission denied"
```bash
# Check permissions
ls -la /var/lib/lxc/
sudo chown -R $USER:$USER /var/lib/lxc/
sudo chmod -R 755 /var/lib/lxc/
```

### 5. OCI Bundle Issues

#### Problem: "Invalid OCI bundle"
```bash
# Diagnose bundle structure
ls -la /path/to/bundle/
ls -la /path/to/bundle/rootfs/
cat /path/to/bundle/config.json | jq .
```

**Solutions:**
```bash
# 1. Check structure
mkdir -p /tmp/test-bundle/rootfs
echo '{"ociVersion":"1.0.0","process":{"args":["/bin/sh"]},"root":{"path":"rootfs"}}' > /tmp/test-bundle/config.json

# 2. Test with valid bundle
./nexcage --debug create --name test --image /tmp/test-bundle
```

#### Problem: "Rootfs not found"
```bash
# Check rootfs
ls -la /path/to/bundle/rootfs/
file /path/to/bundle/rootfs/
```

**Solutions:**
```bash
# Create rootfs
mkdir -p /path/to/bundle/rootfs
# Copy files or extract archive
```

## Specific Scenarios

### 1. Proxmox Problem Diagnostics

#### Check Proxmox Connection
```bash
# Connection test
curl -k https://localhost:8006/api2/json/version

# Check tokens
cat ~/.proxmox-credentials
```

#### VMID Problems
```bash
# Find available VMIDs
pct list | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n

# Check conflicts
pct list | grep "test-container"
```

### 2. Network Problem Diagnostics

#### Check Network Configuration
```bash
# List network interfaces
ip link show
brctl show

# Check routes
ip route show
```

#### DNS Problems
```bash
# DNS test
nslookup google.com
dig google.com

# Check /etc/resolv.conf
cat /etc/resolv.conf
```

### 3. Resource Problem Diagnostics

#### Check CPU
```bash
# CPU load
top -n 1
htop

# CPU information
lscpu
cat /proc/cpuinfo
```

#### Check Disk Space
```bash
# Disk usage
df -h
du -sh /var/lib/lxc/*

# Check inodes
df -i
```

## Diagnostic Automation

### 1. Diagnostic Script
```bash
#!/bin/bash
# nexcage-diagnostics.sh

echo "=== nexcage Diagnostics ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo ""

echo "=== System Information ==="
uname -a
lsb_release -a
echo ""

echo "=== Memory Usage ==="
free -h
echo ""

echo "=== Disk Usage ==="
df -h
echo ""

echo "=== LXC Status ==="
pct list
echo ""

echo "=== Network Interfaces ==="
ip link show
echo ""

echo "=== nexcage Version ==="
./nexcage --version
echo ""

echo "=== Test Command ==="
./nexcage --debug --log-file /tmp/diagnostics.log list
echo "Log written to /tmp/diagnostics.log"
```

### 2. Log Monitoring
```bash
#!/bin/bash
# monitor-nexcage.sh

LOG_FILE="/var/log/nexcage/production.log"
ALERT_EMAIL="admin@example.com"

# Monitor errors
tail -f "$LOG_FILE" | grep --line-buffered "ERROR" | while read line; do
    echo "ERROR detected: $line" | mail -s "nexcage Error Alert" "$ALERT_EMAIL"
done
```

### 3. Automatic Log Cleanup
```bash
#!/bin/bash
# cleanup-logs.sh

LOG_DIR="/var/log/nexcage"
MAX_SIZE="100M"
MAX_AGE="7"

# Cleanup by size
find "$LOG_DIR" -name "*.log" -size +$MAX_SIZE -delete

# Cleanup by age
find "$LOG_DIR" -name "*.log" -mtime +$MAX_AGE -delete

# Log rotation
for log in "$LOG_DIR"/*.log; do
    if [ -f "$log" ]; then
        mv "$log" "$log.$(date +%Y%m%d)"
        gzip "$log.$(date +%Y%m%d)"
    fi
done
```

## Monitoring System Integration

### 1. Prometheus Metrics
```bash
# Export metrics from logs
grep "completed in" /var/log/nexcage/production.log | \
  awk '{print "nexcage_command_duration_seconds{command=\""$4"\"} " $6/1000}' > /var/lib/prometheus/nexcage.prom
```

### 2. Grafana Dashboard
```json
{
  "dashboard": {
    "title": "nexcage Performance",
    "panels": [
      {
        "title": "Command Duration",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(nexcage_command_duration_seconds[5m])",
            "legendFormat": "{{command}}"
          }
        ]
      }
    ]
  }
}
```

### 3. ELK Stack
```yaml
# filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nexcage/*.log
  fields:
    service: nexcage
    environment: production
  multiline.pattern: '^\['
  multiline.negate: true
  multiline.match: after
```

## Security Recommendations

### 1. Log Protection
```bash
# Set proper permissions
chmod 640 /var/log/nexcage/*.log
chown root:nexcage /var/log/nexcage/*.log

# Encrypt sensitive logs
gpg --symmetric --cipher-algo AES256 /var/log/nexcage/sensitive.log
```

### 2. Sensitive Data Filtering
```bash
# Remove passwords from logs
sed -i 's/password=[^[:space:]]*/password=***/g' /var/log/nexcage/*.log

# Remove tokens
sed -i 's/token=[^[:space:]]*/token=***/g' /var/log/nexcage/*.log
```

## Summary

This guide provides a comprehensive approach to diagnosing and resolving nexcage problems. Use debug logging as the primary tool for problem analysis and always preserve logs for further analysis.

### Key Principles:
1. Always use debug mode for diagnostics
2. Preserve logs for analysis
3. Monitor system performance
4. Regularly clean old logs
5. Protect sensitive data in logs
