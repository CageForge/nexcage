## Vendored libcrun build

This repository builds vendored `libcrun` in CI to ensure ABI compatibility is preserved.

Workflow: `.github/workflows/build_vendored.yml`

Steps:
- Install system dependencies via apt (libseccomp-dev, libyajl-dev, libcap-dev, libsystemd-dev, etc.)
- Run `zig build prepare-crun` to generate headers and verify pkg-config deps
- Run `zig build -Duse-vendored-libcrun=true`

Local equivalent:
```bash
make deps
make build-vendored
```

# GitHub CI/CD Setup for Proxmox Testing

This document provides step-by-step instructions for setting up automated CI/CD testing on Proxmox server `mgr.cp.if.ua`.

## Overview

The CI/CD pipeline automatically:
- Runs tests on Proxmox server after each commit
- Deploys the application to Proxmox server
- Monitors server health and application status
- Generates detailed reports and artifacts
- Comments on pull requests with test results

## Prerequisites

### 1. GitHub CLI
Install GitHub CLI if not already installed:
```bash
# Ubuntu/Debian
sudo apt install gh

# macOS
brew install gh

# Windows
winget install GitHub.cli
```

### 2. SSH Access to Proxmox Server
Ensure you have SSH access to the Proxmox server:
```bash
ssh root@mgr.cp.if.ua
```

### 3. GitHub Repository
Ensure you have push access to the repository and can manage secrets.

## Quick Setup

### Automated Setup
Run the automated setup script:
```bash
chmod +x scripts/setup_github_ci.sh
./scripts/setup_github_ci.sh
```

This script will:
1. Generate SSH key pair for CI
2. Copy public key to Proxmox server
3. Add private key to GitHub secrets
4. Test the connection
5. Trigger the workflow

### Manual Setup

#### Step 1: Generate SSH Key Pair
```bash
ssh-keygen -t ed25519 -f ci_ssh_key -N "" -C "nexcage-ci@github.com"
```

#### Step 2: Copy Public Key to Proxmox Server
```bash
ssh-copy-id -i ci_ssh_key.pub root@mgr.cp.if.ua
```

#### Step 3: Test SSH Connection
```bash
ssh -i ci_ssh_key -o StrictHostKeyChecking=no root@mgr.cp.if.ua "echo 'SSH connection successful'"
```

#### Step 4: Add Private Key to GitHub Secrets
```bash
gh secret set PROXMOX_SSH_KEY --body-file ci_ssh_key
```

#### Step 5: Clean Up Local Files
```bash
rm -f ci_ssh_key ci_ssh_key.pub
```

## Workflow Configuration

### Workflow File
The workflow is defined in `.github/workflows/proxmox_ci.yml` and includes:

1. **proxmox-ci**: Runs tests on Proxmox server
2. **proxmox-deployment**: Deploys application to Proxmox server
3. **proxmox-monitoring**: Monitors server health
4. **generate-ci-summary**: Generates combined reports

### Environment Variables
- `PVE_HOST`: Proxmox server hostname (mgr.cp.if.ua)
- `PVE_USER`: Proxmox server user (root)
- `PVE_PATH`: Binary path on Proxmox server (/usr/local/bin)
- `CONFIG_PATH`: Config path on Proxmox server (/etc/nexcage)

### Secrets Required
- `PROXMOX_SSH_KEY`: Private SSH key for Proxmox server access

## Workflow Triggers

### Automatic Triggers
- **Push to main/develop**: Full CI/CD pipeline
- **Push to feature branches**: CI testing only
- **Pull requests**: CI testing with PR comments

### Manual Triggers
- **Workflow dispatch**: Manual trigger from GitHub Actions UI

## Workflow Jobs

### 1. Proxmox CI Job
**Purpose**: Run tests on Proxmox server
**Triggers**: All pushes and PRs
**Steps**:
- Checkout code
- Setup Zig environment
- Install dependencies
- Setup SSH connection
- Run Proxmox tests
- Upload test reports
- Comment on PRs

### 2. Proxmox Deployment Job
**Purpose**: Deploy application to Proxmox server
**Triggers**: Push to main branch only
**Steps**:
- Build release binary
- Setup SSH connection
- Deploy to Proxmox server
- Set permissions
- Test deployment
- Upload deployment summary

### 3. Proxmox Monitoring Job
**Purpose**: Monitor server health and application status
**Triggers**: After CI and deployment
**Steps**:
- Check server status
- Monitor binary status
- Check config status
- Generate monitoring report
- Upload monitoring report

### 4. Generate CI Summary Job
**Purpose**: Generate combined reports
**Triggers**: After all other jobs
**Steps**:
- Download all artifacts
- Generate combined summary
- Upload combined summary
- Comment on PRs

## Test Reports

### Report Types
1. **Test Reports**: Detailed test results with timing and memory usage
2. **Deployment Reports**: Deployment status and verification
3. **Monitoring Reports**: Server health and application status
4. **Combined Reports**: All reports combined into single summary

### Report Locations
- **GitHub Actions**: Available as workflow artifacts
- **Proxmox Server**: Stored in `/var/log/nexcage/`
- **Local Development**: Stored in `test-reports/`

### Report Retention
- **GitHub Artifacts**: 30 days
- **Proxmox Server**: 7 days
- **Local Development**: Until manually cleaned

## Monitoring and Alerts

### GitHub Actions
- **Status Badges**: Display build status in README
- **Email Notifications**: Configure in repository settings
- **Slack Integration**: Configure webhooks for notifications

### Proxmox Server
- **Log Monitoring**: Check `/var/log/nexcage/`
- **System Monitoring**: Use Proxmox built-in monitoring
- **Application Monitoring**: Check binary status and performance

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed
```bash
# Check SSH key
ssh -i ci_ssh_key -o StrictHostKeyChecking=no root@mgr.cp.if.ua

# Check GitHub secrets
gh secret list

# Regenerate SSH key
ssh-keygen -t ed25519 -f ci_ssh_key -N "" -C "nexcage-ci@github.com"
```

#### 2. Workflow Not Triggering
```bash
# Check workflow file
cat .github/workflows/proxmox_ci.yml

# Check GitHub Actions
gh run list --workflow="Proxmox CI/CD"

# Trigger manually
gh workflow run "Proxmox CI/CD" --ref main
```

#### 3. Tests Failing
```bash
# Check test logs
gh run view --log

# Check Proxmox server
ssh root@mgr.cp.if.ua "systemctl status nexcage"

# Check binary
ssh root@mgr.cp.if.ua "/usr/local/bin/nexcage --help"
```

#### 4. Deployment Failed
```bash
# Check deployment logs
gh run view --log

# Check Proxmox server
ssh root@mgr.cp.if.ua "ls -la /usr/local/bin/nexcage"

# Check permissions
ssh root@mgr.cp.if.ua "chmod +x /usr/local/bin/nexcage"
```

### Debug Mode
Enable debug mode for detailed logging:
```bash
# Set debug environment variable
export DEBUG=true

# Run tests with debug output
make test-proxmox
```

## Security Considerations

### SSH Key Management
- **Key Rotation**: Rotate SSH keys regularly
- **Key Storage**: Store private keys securely in GitHub secrets
- **Access Control**: Limit SSH access to necessary users only

### Proxmox Server Security
- **User Permissions**: Use appropriate user permissions
- **Firewall Rules**: Configure firewall to allow only necessary traffic
- **Log Monitoring**: Monitor logs for suspicious activity

### GitHub Security
- **Repository Settings**: Configure appropriate repository settings
- **Secret Management**: Use GitHub secrets for sensitive data
- **Access Control**: Limit repository access to authorized users

## Performance Optimization

### Workflow Optimization
- **Parallel Jobs**: Run jobs in parallel where possible
- **Caching**: Cache dependencies and build artifacts
- **Resource Limits**: Set appropriate resource limits

### Proxmox Server Optimization
- **Resource Allocation**: Allocate appropriate resources
- **Storage Optimization**: Use appropriate storage types
- **Network Optimization**: Optimize network configurations

## Maintenance

### Regular Tasks
1. **Monitor Workflow Status**: Check GitHub Actions regularly
2. **Review Test Reports**: Analyze test results and trends
3. **Update Dependencies**: Keep dependencies up to date
4. **Rotate SSH Keys**: Rotate SSH keys regularly
5. **Clean Up Artifacts**: Clean up old artifacts and logs

### Monthly Tasks
1. **Review Security**: Review security settings and access
2. **Performance Analysis**: Analyze performance metrics
3. **Documentation Updates**: Update documentation as needed
4. **Backup Configuration**: Backup configuration files

## Support

### Getting Help
1. **Check Logs**: Review workflow and application logs
2. **GitHub Issues**: Create issues for bugs and feature requests
3. **Documentation**: Refer to this documentation and other guides
4. **Community**: Ask questions in project discussions

### Reporting Issues
When reporting issues, include:
- **Workflow Run ID**: From GitHub Actions
- **Error Messages**: Complete error messages
- **Logs**: Relevant log files
- **Environment**: Proxmox server details
- **Steps to Reproduce**: Clear steps to reproduce the issue

---

**Last Updated**: 2025-10-04  
**Version**: 0.5.0  
**Maintainer**: Nexcage Runtime Interface Team
