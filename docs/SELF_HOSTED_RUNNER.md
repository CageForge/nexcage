# GitHub Actions Self-Hosted Runner Setup

This document provides comprehensive instructions for setting up Proxmox server `mgr.cp.if.ua` as a GitHub Actions self-hosted runner.

## Overview

A self-hosted runner provides:
- **Direct Access**: Run tests directly on Proxmox server
- **Better Performance**: No network latency for Proxmox operations
- **Full Control**: Complete control over the runner environment
- **Cost Efficiency**: No GitHub Actions minutes consumption
- **Custom Dependencies**: Install specific tools and libraries

## Prerequisites

### 1. Proxmox Server Access
- SSH access to `root@mgr.cp.if.ua`
- Root privileges for service management
- Internet connectivity for GitHub communication

### 2. GitHub Repository Access
- Push access to the repository
- Ability to manage repository secrets and settings
- GitHub CLI installed locally

### 3. System Requirements
- **OS**: Ubuntu/Debian (recommended)
- **RAM**: Minimum 2GB, recommended 4GB+
- **Disk**: Minimum 10GB free space
- **CPU**: 2+ cores recommended

## Quick Setup

### Automated Setup
Run the automated setup script:
```bash
chmod +x scripts/setup_github_runner.sh
./scripts/setup_github_runner.sh
```

This script will:
1. Generate registration token
2. Download and install GitHub Actions runner
3. Install dependencies (Zig, build tools)
4. Configure and register runner
5. Create systemd service
6. Start the runner service

### Manual Setup

#### Step 1: Prepare Proxmox Server
```bash
# Connect to Proxmox server
ssh root@mgr.cp.if.ua

# Create runner directory
mkdir -p /opt/github-runner
cd /opt/github-runner

# Install dependencies
apt-get update
apt-get install -y libcap-dev libseccomp-dev libyajl-dev build-essential

# Install Zig
cd /opt
wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz
tar -xf zig-linux-x86_64-0.15.1.tar.xz
ln -sf /opt/zig-linux-x86_64-0.15.1/zig /usr/local/bin/zig
```

#### Step 2: Download and Install Runner
```bash
# Download GitHub Actions runner
cd /opt/github-runner
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract runner
tar xzf actions-runner-linux-x64-2.311.0.tar.gz
```

#### Step 3: Register Runner
```bash
# Generate registration token
gh api repos/moriarti/proxmox-lxcri/actions/runners/registration-token --jq '.token'

# Configure runner
./config.sh --url https://github.com/moriarti/proxmox-lxcri --token <REGISTRATION_TOKEN> --name proxmox-runner --labels proxmox,self-hosted,ubuntu --work _work --replace
```

#### Step 4: Create Systemd Service
```bash
# Create service file
cat > /etc/systemd/system/github-runner.service << 'EOF'
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/github-runner
ExecStart=/opt/github-runner/run.sh
Restart=always
RestartSec=5
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
systemctl daemon-reload
systemctl enable github-runner
systemctl start github-runner
```

## Runner Management

### Using Management Script
```bash
# Check runner status
./scripts/manage_github_runner.sh status

# Start runner
./scripts/manage_github_runner.sh start

# Stop runner
./scripts/manage_github_runner.sh stop

# Restart runner
./scripts/manage_github_runner.sh restart

# View logs
./scripts/manage_github_runner.sh logs

# Update runner
./scripts/manage_github_runner.sh update

# Remove runner
./scripts/manage_github_runner.sh remove
```

### Manual Management
```bash
# Check service status
ssh root@mgr.cp.if.ua "systemctl status github-runner"

# View logs
ssh root@mgr.cp.if.ua "journalctl -u github-runner -f"

# Restart service
ssh root@mgr.cp.if.ua "systemctl restart github-runner"

# Stop service
ssh root@mgr.cp.if.ua "systemctl stop github-runner"
```

## Workflow Configuration

### Self-Hosted Workflow
The workflow is defined in `.github/workflows/proxmox_self_hosted.yml`:

```yaml
name: Proxmox Self-Hosted CI/CD

on:
  push:
    branches: [ main, develop, feature/**, feat/** ]
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:

jobs:
  proxmox-ci:
    runs-on: [self-hosted, proxmox]
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Run Proxmox tests
        run: |
          chmod +x scripts/proxmox_only_test.sh
          ./scripts/proxmox_only_test.sh
        env:
          PVE_HOST: root@localhost
```

### Runner Labels
- **`self-hosted`**: Required for self-hosted runners
- **`proxmox`**: Custom label for Proxmox-specific jobs
- **`ubuntu`**: OS identification

## Advantages of Self-Hosted Runner

### Performance Benefits
- **No Network Latency**: Direct access to Proxmox server
- **Faster Builds**: Local compilation and testing
- **Resource Control**: Full control over CPU, memory, and disk
- **Custom Environment**: Pre-installed tools and dependencies

### Cost Benefits
- **No GitHub Actions Minutes**: Free execution
- **Unlimited Usage**: No monthly limits
- **Custom Hardware**: Use existing infrastructure

### Security Benefits
- **Private Environment**: Complete control over security
- **No Data Transfer**: Sensitive data stays on-premises
- **Custom Policies**: Implement your own security policies

## Monitoring and Maintenance

### Health Checks
```bash
# Check runner status
./scripts/manage_github_runner.sh status

# Check GitHub registration
gh api repos/moriarti/proxmox-lxcri/actions/runners --jq '.runners[] | select(.name=="proxmox-runner")'

# Check service logs
ssh root@mgr.cp.if.ua "journalctl -u github-runner --no-pager -n 20"
```

### Regular Maintenance
1. **Update Runner**: Keep runner version up to date
2. **Monitor Logs**: Check for errors and warnings
3. **Resource Usage**: Monitor CPU, memory, and disk usage
4. **Security Updates**: Keep system packages updated
5. **Backup Configuration**: Backup runner configuration

### Troubleshooting

#### Common Issues

##### 1. Runner Not Starting
```bash
# Check service status
systemctl status github-runner

# Check logs
journalctl -u github-runner -f

# Restart service
systemctl restart github-runner
```

##### 2. Runner Not Registered
```bash
# Check registration token
gh api repos/moriarti/proxmox-lxcri/actions/runners/registration-token

# Re-register runner
cd /opt/github-runner
./config.sh --url https://github.com/moriarti/proxmox-lxcri --token <NEW_TOKEN> --name proxmox-runner --labels proxmox,self-hosted,ubuntu --work _work --replace
```

##### 3. Build Failures
```bash
# Check dependencies
zig version
apt list --installed | grep -E "(libcap|libseccomp|libyajl)"

# Check permissions
ls -la /opt/github-runner
ls -la /usr/local/bin/zig
```

##### 4. Network Issues
```bash
# Test GitHub connectivity
curl -I https://github.com
curl -I https://api.github.com

# Check DNS resolution
nslookup github.com
nslookup api.github.com
```

## Security Considerations

### Runner Security
- **User Permissions**: Run with appropriate user permissions
- **Network Security**: Configure firewall rules
- **Access Control**: Limit SSH access to authorized users
- **Log Monitoring**: Monitor logs for suspicious activity

### GitHub Security
- **Repository Settings**: Configure appropriate repository settings
- **Runner Labels**: Use specific labels for job targeting
- **Secrets Management**: Use GitHub secrets for sensitive data
- **Access Control**: Limit repository access to authorized users

### Proxmox Security
- **VM Isolation**: Run runner in isolated VM if possible
- **Resource Limits**: Set appropriate resource limits
- **Backup Strategy**: Implement backup and recovery procedures
- **Monitoring**: Monitor runner performance and security

## Performance Optimization

### Resource Allocation
```bash
# Check current resource usage
htop
df -h
free -h

# Monitor runner performance
systemctl status github-runner
journalctl -u github-runner --no-pager -n 50
```

### Build Optimization
- **Parallel Builds**: Use multiple CPU cores
- **Caching**: Cache dependencies and build artifacts
- **Incremental Builds**: Use incremental build strategies
- **Resource Limits**: Set appropriate resource limits

### Network Optimization
- **Local Dependencies**: Install dependencies locally
- **CDN Usage**: Use CDN for downloads
- **Connection Pooling**: Optimize network connections
- **Bandwidth Management**: Manage bandwidth usage

## Backup and Recovery

### Configuration Backup
```bash
# Backup runner configuration
tar -czf github-runner-backup-$(date +%Y%m%d).tar.gz /opt/github-runner /etc/systemd/system/github-runner.service

# Backup system configuration
cp /etc/systemd/system/github-runner.service /backup/
```

### Recovery Procedures
1. **Restore Configuration**: Restore runner configuration
2. **Reinstall Dependencies**: Reinstall required packages
3. **Re-register Runner**: Register runner with GitHub
4. **Start Service**: Start the runner service
5. **Verify Functionality**: Test runner functionality

## Scaling and Load Balancing

### Multiple Runners
- **Load Distribution**: Distribute jobs across multiple runners
- **Fault Tolerance**: Ensure high availability
- **Resource Optimization**: Optimize resource usage
- **Monitoring**: Monitor all runners

### Runner Groups
- **Label-based Routing**: Route jobs based on labels
- **Environment Isolation**: Isolate different environments
- **Resource Management**: Manage resources per group
- **Security Policies**: Apply different security policies

## Integration with CI/CD

### Workflow Integration
- **Job Targeting**: Target specific runners with labels
- **Environment Variables**: Set environment-specific variables
- **Secrets Management**: Manage secrets per environment
- **Artifact Management**: Handle artifacts and reports

### Monitoring Integration
- **Metrics Collection**: Collect performance metrics
- **Alerting**: Set up alerts for failures
- **Reporting**: Generate comprehensive reports
- **Dashboard**: Create monitoring dashboards

## Support and Troubleshooting

### Getting Help
1. **Check Logs**: Review runner and system logs
2. **GitHub Issues**: Create issues for bugs and feature requests
3. **Documentation**: Refer to this documentation and GitHub docs
4. **Community**: Ask questions in project discussions

### Reporting Issues
When reporting issues, include:
- **Runner Version**: Current runner version
- **System Information**: OS, architecture, resources
- **Error Messages**: Complete error messages
- **Logs**: Relevant log files
- **Steps to Reproduce**: Clear steps to reproduce the issue

---

**Last Updated**: 2025-10-04  
**Version**: 0.5.0  
**Maintainer**: Proxmox LXC Runtime Interface Team
