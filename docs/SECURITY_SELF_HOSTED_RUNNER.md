# Security Guide: Self-Hosted GitHub Runner for Public Repositories

**Date**: 2025-10-31  
**Status**: Best Practices Guide  
**Target**: Public GitHub repositories with self-hosted runners

## ⚠️ Security Considerations

When running self-hosted runners for public repositories, you must protect against:
- **Malicious code from forks** in pull requests
- **Secret exfiltration** attempts
- **System compromise** from untrusted code execution
- **Supply chain attacks** via dependencies

## 🛡️ Security Architecture

### 1. Runner Isolation

#### Option A: LXC Container Isolation (Recommended for Proxmox)
```bash
# Create dedicated LXC container for runner
pct create 100 local:vztmpl/debian-11-standard_11.7-1_amd64.tar.zst \
  --hostname github-runner \
  --memory 2048 \
  --cores 2 \
  --storage local-lvm \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp

# Start container
pct start 100

# Install runner inside container
pct enter 100
# ... install GitHub Actions runner ...
```

#### Option B: Systemd-nspawn Container
```bash
# Create minimal root filesystem
sudo debootstrap --arch=amd64 bullseye /var/lib/machines/github-runner http://deb.debian.org/debian

# Configure container
sudo systemd-nspawn -D /var/lib/machines/github-runner \
  --bind=/tmp:/tmp \
  --private-network \
  --capability=all
```

#### Option C: Virtual Machine (Maximum Isolation)
- Use Proxmox VM with minimal Debian/Ubuntu
- Snapshot before each run
- Revert after completion

### 2. Dedicated Runner User

```bash
# Create dedicated user for runner
sudo useradd -r -m -s /bin/bash -d /opt/github-runner github-runner
sudo usermod -aG docker github-runner  # Only if Docker needed

# Create runner directory with proper permissions
sudo mkdir -p /opt/github-runner/_work
sudo chown -R github-runner:github-runner /opt/github-runner
sudo chmod 750 /opt/github-runner/_work
```

### 3. Restricted Permissions

```bash
# Limit runner user capabilities
sudo setcap -r /opt/github-runner/run.sh  # Remove all capabilities

# Use AppArmor or SELinux profiles
sudo aa-genprof /opt/github-runner/run.sh

# Limit network access
sudo iptables -A OUTPUT -m owner --uid-owner github-runner -j REJECT
sudo iptables -A OUTPUT -m owner --uid-owner github-runner -d github.com -j ACCEPT
sudo iptables -A OUTPUT -m owner --uid-owner github-runner -d registry.npmjs.org -j ACCEPT
```

### 4. Workflow Configuration for Security

#### Pull Request Security Settings

**Critical**: Configure workflows to prevent secret access from forks:

```yaml
# .github/workflows/security.yml example
on:
  pull_request:
    branches: [ main ]

permissions:
  contents: read
  pull-requests: write
  # NO secrets access by default

jobs:
  build:
    runs-on: [self-hosted, proxmox]
    # NEVER allow pull_request_target with secrets for public repos
    if: github.event.pull_request.head.repo.full_name == github.repository
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        # Checkout PR code
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      
      - name: Build
        run: zig build
        # Secrets are NOT available in PR workflows by default
        # Only available if explicitly configured (NOT RECOMMENDED)
```

#### Blocking Fork PRs from Self-Hosted Runner

```yaml
jobs:
  build:
    runs-on: [self-hosted, proxmox]
    # Only run on PRs from same repository
    if: github.event.pull_request.head.repo.full_name == github.repository || github.event_name != 'pull_request'
    
    steps:
      - name: Verify PR source
        run: |
          if [ "${{ github.event_name }}" == "pull_request" ]; then
            if [ "${{ github.event.pull_request.head.repo.full_name }}" != "${{ github.repository }}" ]; then
              echo "❌ Blocking PR from fork for security"
              exit 1
            fi
          fi
```

### 5. Secrets Management

#### GitHub Secrets Best Practices

```yaml
# DO: Use secrets only for trusted workflows
env:
  SECRET_VAR: ${{ secrets.SECRET_NAME }}

# DON'T: Expose secrets in PR workflows from forks
# Secrets are automatically unavailable in pull_request workflows
# UNLESS using pull_request_target (NEVER USE THIS FOR PUBLIC REPOS)
```

#### Local Secret Storage (Alternative)

```bash
# Store secrets in runner environment (not in GitHub)
sudo -u github-runner bash -c 'cat > ~/.github-secrets << EOF
GITHUB_TOKEN=$(cat /etc/github-runner/token)
PROXMOX_PASSWORD=$(cat /etc/github-runner/proxmox-password)
EOF'

# Restrict access
sudo chmod 600 ~github-runner/.github-secrets
sudo chown github-runner:github-runner ~github-runner/.github-secrets
```

### 6. Network Isolation

```bash
# Firewall rules for runner
sudo ufw allow from 140.82.112.0/20 to any port 443  # GitHub Actions
sudo ufw allow from 185.199.108.0/22 to any port 443  # GitHub Actions
sudo ufw deny from github-runner user out

# Or use iptables
sudo iptables -A OUTPUT -m owner --uid-owner $(id -u github-runner) \
  -d 140.82.112.0/20 -j ACCEPT
sudo iptables -A OUTPUT -m owner --uid-owner $(id -u github-runner) \
  -d 185.199.108.0/22 -j ACCEPT
sudo iptables -A OUTPUT -m owner --uid-owner $(id -u github-runner) \
  -j DROP
```

### 7. Resource Limits

```bash
# Systemd service with limits
cat > /etc/systemd/system/github-runner.service << EOF
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=github-runner
Group=github-runner
WorkingDirectory=/opt/github-runner
ExecStart=/opt/github-runner/run.sh

# Resource limits
MemoryLimit=4G
CPUQuota=200%
TasksMax=100
LimitNOFILE=4096

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/github-runner/_work

# Network
PrivateNetwork=false
RestrictAddressFamilies=AF_INET AF_INET6

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### 8. Monitoring and Logging

```bash
# Enable audit logging
sudo auditctl -w /opt/github-runner/_work -p rwxa -k github-runner

# Log all runner activity
sudo journalctl -u github-runner -f

# Monitor suspicious activity
sudo fail2ban-client set github-runner addignoreip 140.82.112.0/20
```

### 9. Workflow Permissions Configuration

Update workflow files to use minimal permissions:

```yaml
# .github/workflows/ci.yml
permissions:
  contents: read      # Read repository contents
  pull-requests: write # Comment on PRs
  checks: write        # Update check status
  # NO contents: write for PRs from forks
  # NO secrets access
```

### 10. Pull Request Approval Workflow

For maximum security, require manual approval before running workflows on self-hosted runner:

```yaml
jobs:
  build:
    runs-on: [self-hosted, proxmox]
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    
    steps:
      - name: Require approval for fork PRs
        if: github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository
        run: |
          echo "::error::PRs from forks cannot run on self-hosted runner for security"
          exit 1
```

## 🔒 Recommended Security Checklist

### Initial Setup
- [ ] Runner runs in isolated environment (LXC/VM/nspawn)
- [ ] Dedicated user with minimal permissions
- [ ] Network firewall rules configured
- [ ] Resource limits set (memory, CPU, disk)
- [ ] Audit logging enabled

### Workflow Configuration
- [ ] PRs from forks are blocked or run on GitHub-hosted runners only
- [ ] Secrets are NOT accessible in PR workflows
- [ ] Minimal permissions in workflow files
- [ ] Code signing verification enabled (optional)

### Ongoing Maintenance
- [ ] Runner updated regularly
- [ ] Logs reviewed periodically
- [ ] Access audited
- [ ] Secrets rotated regularly
- [ ] Runner health monitored

## 📋 Implementation Example

### Secure Runner Setup Script

```bash
#!/bin/bash
# scripts/setup_secure_runner.sh

set -euo pipefail

RUNNER_USER="github-runner"
RUNNER_DIR="/opt/github-runner"
REPO_URL="$1"  # Pass repository URL

# 1. Create dedicated user
sudo useradd -r -m -s /bin/bash -d "$RUNNER_DIR" "$RUNNER_USER"

# 2. Create runner directory
sudo mkdir -p "$RUNNER_DIR"/_work
sudo chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# 3. Download and install runner
cd "$RUNNER_DIR"
sudo -u "$RUNNER_USER" bash << EOF
curl -o actions-runner-linux-x64-2.311.0.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz
tar xzf actions-runner-linux-x64-2.311.0.tar.gz
./config.sh --url "$REPO_URL" --token "$2" --name proxmox-runner --work _work
EOF

# 4. Configure systemd service with security limits
sudo tee /etc/systemd/system/github-runner.service > /dev/null << SERVICE_EOF
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=$RUNNER_USER
Group=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$RUNNER_DIR/_work

# Resource limits
MemoryLimit=4G
CPUQuota=200%
TasksMax=100

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 5. Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable github-runner
sudo systemctl start github-runner

echo "✅ Secure runner configured"
```

## 🚨 Security Incident Response

If you suspect a security breach:

1. **Immediately stop the runner**:
   ```bash
   sudo systemctl stop github-runner
   ```

2. **Check logs for suspicious activity**:
   ```bash
   sudo journalctl -u github-runner --since "1 hour ago"
   sudo auditctl -w /opt/github-runner/_work -p rwxa
   ```

3. **Review workflow runs**:
   - Check GitHub Actions runs for unexpected behavior
   - Review artifacts uploaded
   - Check for secret access attempts

4. **Rotate secrets**:
   - Rotate all GitHub secrets
   - Rotate runner registration token
   - Regenerate SSH keys if used

5. **Rebuild runner environment**:
   - Snapshot and rebuild container/VM
   - Reinstall from clean state

## 📚 Additional Resources

- [GitHub Actions Security Best Practices](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Self-Hosted Runner Security](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners#self-hosted-runner-security)
- [Securing Workflows](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-secrets)

## ⚠️ Important Notes

1. **Never use `pull_request_target`** with self-hosted runners for public repos
2. **Never expose secrets** in PR workflows from forks
3. **Always verify PR source** before allowing execution
4. **Consider using GitHub-hosted runners** for fork PRs
5. **Use ephemeral runners** when possible (destroy after each run)

## 🎯 Summary

For public repositories:
- ✅ Use isolated environments (LXC/VM)
- ✅ Block or carefully review fork PRs
- ✅ Minimize permissions
- ✅ Monitor and audit
- ✅ Use dedicated runner user
- ✅ Set resource limits
- ✅ Network isolation
- ❌ Never expose secrets to PRs
- ❌ Never use pull_request_target carelessly
- ❌ Never run untrusted code without isolation

