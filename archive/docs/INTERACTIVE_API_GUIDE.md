# Interactive API Guide for Proxmox LXCRI

## 🚀 Quick Start Interactive Tutorial

This guide provides hands-on examples and interactive commands to get you started with Proxmox LXCRI on Debian Linux and Proxmox VE environments.

### Prerequisites Verification

```bash
# Verify Debian/Proxmox VE environment
cat /etc/debian_version  # Should show Debian version
systemctl status pve-cluster  # Proxmox VE cluster service

# Check if Proxmox LXCRI is installed
nexcage --version

# Verify Proxmox VE connection
nexcage list

# Check configuration
nexcage spec --help
```

## 📚 Core API Categories

### 1. Container Lifecycle Management

#### Creating Containers

**Basic Container Creation:**
```bash
# Create a simple container
nexcage create my-container \
  --image ubuntu:22.04 \
  --memory 512MB \
  --cpu 1

# Verify creation
nexcage list | grep my-container
```

**Advanced Container with Security:**
```bash
# Create container with security hardening
nexcage create secure-container \
  --image alpine:latest \
  --memory 256MB \
  --cpu 0.5 \
  --read-only \
  --no-new-privileges \
  --drop-capabilities ALL \
  --add-capability NET_BIND_SERVICE \
  --user 1000:1000
```

**Container with Health Checks:**
```bash
# Create container with health monitoring
nexcage create web-app \
  --image nginx:alpine \
  --memory 1GB \
  --cpu 2 \
  --health-cmd "curl -f http://localhost/" \
  --health-interval 30s \
  --health-timeout 10s \
  --health-retries 3
```

#### Starting and Managing Containers

**Start with Lifecycle Hooks:**
```bash
# Start container with custom hooks
nexcage start my-container \
  --pre-start-hook "/usr/local/bin/setup.sh" \
  --post-start-hook "/usr/local/bin/notify.sh"
```

**Combined Run Operation:**
```bash
# Create and start in one command
nexcage run fast-start \
  --image redis:alpine \
  --memory 512MB \
  --detach \
  --port 6379:6379
```

#### Monitoring and Health Checks

**Check Container Health:**
```bash
# Get detailed health status
nexcage inspect my-container --health

# Monitor real-time metrics
nexcage stats my-container --follow

# Get readiness status
nexcage readiness my-container
```

### 2. Advanced Operations

#### Checkpoint and Restore

**Create Checkpoint:**
```bash
# Create ZFS snapshot checkpoint
nexcage checkpoint my-container \
  --checkpoint-dir /var/lib/containers/checkpoints \
  --leave-running

# List available checkpoints
nexcage checkpoint --list my-container
```

**Restore from Checkpoint:**
```bash
# Restore container state
nexcage restore my-container \
  --checkpoint-dir /var/lib/containers/checkpoints \
  --force

# Restore to different container
nexcage restore new-container \
  --from-checkpoint my-container \
  --checkpoint-dir /var/lib/containers/checkpoints
```

#### Network Management

**Configure Container Networking:**
```bash
# Create with custom network
nexcage create net-container \
  --image ubuntu:22.04 \
  --network bridge=br1 \
  --ip 192.168.1.100/24 \
  --gateway 192.168.1.1 \
  --dns 8.8.8.8

# Add additional network interface
nexcage network attach net-container \
  --network bridge=br2 \
  --ip 10.0.0.100/16
```

#### Storage Management

**Configure Storage:**
```bash
# Create with ZFS storage
nexcage create storage-container \
  --image ubuntu:22.04 \
  --storage-driver zfs \
  --storage-pool tank/containers \
  --storage-size 10GB

# Mount additional volumes
nexcage create volume-container \
  --image nginx:alpine \
  --mount type=bind,source=/host/data,target=/var/www \
  --mount type=tmpfs,target=/tmp,size=100MB
```

### 3. Security and Compliance

#### Security Scanning

**Run Security Audit:**
```bash
# Comprehensive security scan
nexcage security-audit \
  --standards cis-docker,nist-800-190 \
  --severity medium \
  --export-report /tmp/security-report.json

# Quick security check
nexcage security-check my-container \
  --check-privileged \
  --check-capabilities \
  --check-network-exposure
```

#### Compliance Reporting

**Generate Compliance Reports:**
```bash
# PCI-DSS compliance report
nexcage compliance-report \
  --standard pci-dss \
  --container my-container \
  --output /reports/pci-compliance.pdf

# HIPAA compliance check
nexcage compliance-report \
  --standard hipaa \
  --all-containers \
  --format json
```

### 4. Performance and Monitoring

#### Resource Monitoring

**Real-time Performance:**
```bash
# Monitor all containers
nexcage stats --all --interval 5s

# Detailed performance metrics
nexcage metrics my-container \
  --cpu-details \
  --memory-breakdown \
  --network-stats \
  --disk-io

# Performance benchmarking
nexcage benchmark my-container \
  --duration 60s \
  --include-network \
  --include-disk
```

#### Resource Limits

**Set and Update Limits:**
```bash
# Set runtime resource limits
nexcage update my-container \
  --memory 2GB \
  --cpu 4 \
  --disk-limit 20GB \
  --network-bandwidth 100Mbps

# CPU throttling
nexcage limit my-container \
  --cpu-quota 50000 \
  --cpu-period 100000 \
  --cpu-shares 1024
```

## 🔧 Configuration Management

### Environment-Specific Configurations

**Development Environment:**
```bash
# Development configuration
export PROXMOX_LXCRI_ENV=development
nexcage config set \
  --log-level debug \
  --enable-profiling \
  --disable-security-checks

# Load development-specific config
nexcage --config /etc/nexcage/dev.json run dev-container
```

**Production Environment:**
```bash
# Production configuration
export PROXMOX_LXCRI_ENV=production
nexcage config set \
  --log-level info \
  --enable-audit-logging \
  --enforce-security-policies \
  --enable-monitoring

# Production container with full security
nexcage run prod-app \
  --config /etc/nexcage/production.json \
  --security-profile strict \
  --enable-all-monitoring
```

### Configuration Hot-Reload

**Dynamic Configuration Updates:**
```bash
# Reload configuration without restart
nexcage config reload

# Update specific configuration values
nexcage config update \
  --runtime.memory_limit 8GB \
  --logging.level warn \
  --security.scan_interval 3600

# Validate configuration changes
nexcage config validate \
  --schema-version 2.0 \
  --check-compliance
```

## 📊 Advanced Troubleshooting

### Error Recovery

**Circuit Breaker Management:**
```bash
# Check circuit breaker status
nexcage debug circuit-breakers

# Reset failed circuit breaker
nexcage debug reset-circuit-breaker proxmox-api

# Enable circuit breaker protection
nexcage config set \
  --circuit-breaker.proxmox.enabled true \
  --circuit-breaker.proxmox.failure-threshold 5
```

**Error Analysis:**
```bash
# Analyze error patterns
nexcage debug error-analysis \
  --last 24h \
  --category network \
  --severity high

# Export error report
nexcage debug export-errors \
  --format json \
  --include-stack-traces \
  --output /tmp/error-report.json
```

### Performance Debugging

**Performance Profiling:**
```bash
# Profile container performance
nexcage profile my-container \
  --duration 120s \
  --profile-cpu \
  --profile-memory \
  --profile-network

# Generate performance report
nexcage profile-report \
  --container my-container \
  --format html \
  --output /reports/performance.html
```

## 🎯 Integration Examples

### CI/CD Pipeline Integration

**GitLab CI Integration:**
```yaml
# .gitlab-ci.yml
test_container:
  script:
    - nexcage run test-env --image test:latest --wait
    - nexcage exec test-env -- /run-tests.sh
    - nexcage security-audit test-env --fail-on-critical
    - nexcage cleanup test-env
```

**GitHub Actions Integration:**
```yaml
# .github/workflows/container-test.yml
- name: Test with Proxmox LXCRI
  run: |
    nexcage create test-container --image ${{ matrix.image }}
    nexcage start test-container --wait-ready
    nexcage exec test-container -- make test
    nexcage logs test-container > test-logs.txt
```

### Kubernetes Integration

**Runtime Class Configuration:**
```yaml
# runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nexcage
handler: nexcage
overhead:
  podFixed:
    memory: "64Mi"
    cpu: "100m"
```

**Pod Specification:**
```yaml
# pod-with-nexcage.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  runtimeClassName: nexcage
  containers:
  - name: app
    image: nginx:alpine
    resources:
      limits:
        memory: "512Mi"
        cpu: "500m"
```

## 🚀 Performance Optimization Tips

### Best Practices

**Memory Optimization:**
```bash
# Enable memory optimization
nexcage config set \
  --memory.use-hugepages true \
  --memory.enable-ksm true \
  --memory.compression-algorithm lz4

# Memory-efficient container
nexcage run memory-efficient \
  --image alpine:latest \
  --memory 64MB \
  --memory-swappiness 10 \
  --oom-kill-disable false
```

**Network Optimization:**
```bash
# High-performance networking
nexcage create fast-network \
  --image nginx:alpine \
  --network-driver macvlan \
  --enable-sr-iov \
  --network-optimization aggressive

# Zero-copy networking
nexcage config set \
  --network.zero-copy-enabled true \
  --network.tcp-offload-enabled true
```

**Storage Optimization:**
```bash
# ZFS optimization for containers
nexcage config set \
  --storage.zfs.compression lz4 \
  --storage.zfs.deduplication on \
  --storage.zfs.recordsize 64K

# High-IOPS storage configuration
nexcage create high-iops \
  --image database:latest \
  --storage-type nvme \
  --storage-iops 10000 \
  --storage-scheduler noop
```

## 📝 API Reference Quick Access

### Command Categories

1. **Lifecycle**: `create`, `start`, `stop`, `restart`, `delete`, `run`
2. **Management**: `list`, `inspect`, `stats`, `logs`, `exec`
3. **Storage**: `checkpoint`, `restore`, `export`, `import`
4. **Network**: `network`, `port`, `expose`
5. **Security**: `security-audit`, `compliance-report`, `scan`
6. **Config**: `config`, `spec`, `version`, `help`
7. **Debug**: `debug`, `profile`, `trace`, `analyze`

### Global Flags

```bash
--config PATH           # Custom configuration file
--log-level LEVEL       # Logging verbosity
--log-format FORMAT     # Log output format
--profile              # Enable performance profiling
--dry-run              # Show what would be executed
--json                 # JSON output format
--quiet                # Suppress non-error output
--verbose              # Detailed output
--timeout DURATION     # Operation timeout
```

### Exit Codes

- `0`: Success
- `1`: General error
- `2`: Misuse of shell command
- `125`: Container runtime error
- `126`: Container command not executable
- `127`: Container command not found
- `128+n`: Container killed by signal n

## 🔗 Additional Resources

- **API Documentation**: `/docs/api/`
- **Architecture Guide**: `/docs/ARCHITECTURE.md`
- **Troubleshooting**: `/docs/TROUBLESHOOTING.md`
- **Performance Tuning**: `/docs/PERFORMANCE_TUNING.md`
- **Security Guide**: `/docs/SECURITY.md`
- **Contributing**: `/docs/CONTRIBUTING.md`

---

**💡 Pro Tip**: Use `nexcage help COMMAND` for detailed help on any command, and `nexcage completion bash` to enable tab completion!
