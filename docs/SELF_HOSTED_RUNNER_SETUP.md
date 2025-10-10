# Self-Hosted Runner Setup Guide

This guide provides instructions for configuring the GitHub Actions self-hosted runner on a Proxmox server.

## Prerequisites

- Proxmox VE server (tested on PVE 8.x and 9.x)
- GitHub Actions self-hosted runner installed and configured
- Runner user: `github-runner`

## Required System Permissions

The `github-runner` user needs elevated privileges to execute Proxmox commands and install system packages.

### 1. Configure Sudoers

Create a sudoers configuration file for the runner:

```bash
sudo visudo -f /etc/sudoers.d/github-runner
```

Add the following content:

```sudoers
# GitHub Actions runner permissions
# Allow package management (apt-get)
github-runner ALL=(root) NOPASSWD: /usr/bin/apt-get update
github-runner ALL=(root) NOPASSWD: /usr/bin/apt-get install *
github-runner ALL=(root) NOPASSWD: /usr/bin/apt-get upgrade *
github-runner ALL=(root) NOPASSWD: /usr/bin/dpkg *

# Allow Proxmox container management (pct)
github-runner ALL=(root) NOPASSWD: /usr/sbin/pct

# Allow Proxmox API access (pvesh)
github-runner ALL=(root) NOPASSWD: /usr/bin/pvesh

# Allow Proxmox storage management (pvesm)
github-runner ALL=(root) NOPASSWD: /usr/sbin/pvesm

# Allow systemd service management
github-runner ALL=(root) NOPASSWD: /usr/bin/systemctl enable *
github-runner ALL=(root) NOPASSWD: /usr/bin/systemctl start *
github-runner ALL=(root) NOPASSWD: /usr/bin/systemctl stop *
github-runner ALL=(root) NOPASSWD: /usr/bin/systemctl restart *
github-runner ALL=(root) NOPASSWD: /usr/bin/systemctl status *

# Allow file operations for releases
github-runner ALL=(root) NOPASSWD: /usr/bin/mv * /usr/local/bin/*

# Preserve environment variables for LXC operations
Defaults:github-runner env_keep += "LXC_MEMFD_REXEC"
Defaults:github-runner env_keep += "PATH"

# Disable requiretty for non-interactive sudo
Defaults:github-runner !requiretty
```

### 2. Set File Permissions

Ensure the sudoers file has correct permissions:

```bash
sudo chmod 0440 /etc/sudoers.d/github-runner
```

### 3. Verify Configuration

Test the configuration:

```bash
# Test as github-runner user
sudo -u github-runner sudo -n pct version
sudo -u github-runner sudo -n pvesh get /cluster/nextid
sudo -u github-runner sudo -n pvesm status
sudo -u github-runner sudo -n apt-get update
```

All commands should execute without prompting for a password.

## Required System Dependencies

The runner needs the following development libraries pre-installed:

```bash
sudo apt-get update
sudo apt-get install -y \
  libcap-dev \
  libseccomp-dev \
  libyajl-dev \
  build-essential \
  git \
  curl \
  wget
```

## Proxmox Configuration

### LXC Templates

Ensure at least one LXC template is available:

```bash
# List available templates
pvesm list local --content vztmpl

# Download Alpine template if needed
pveam update
pveam download local alpine-3.22-default_20250617_amd64.tar.xz
```

### Network Bridge

Verify the network bridge exists:

```bash
# Check for vmbr50 (or your configured bridge)
ip -br link show vmbr50
```

If the bridge doesn't exist, create it in `/etc/network/interfaces`:

```
auto vmbr50
iface vmbr50 inet static
    address 10.50.0.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s 10.50.0.0/24 -o vmbr0 -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s 10.50.0.0/24 -o vmbr0 -j MASQUERADE
```

Apply the configuration:

```bash
sudo ifreload -a
```

### Storage

Ensure storage is configured for containers:

```bash
pvesm status
```

The runner expects either `local` or `local-lvm` storage to be available.

## GitHub Actions Workflows

All workflows in `.github/workflows/` are configured to use:

```yaml
runs-on: [self-hosted, proxmox]
```

This ensures they execute on the Proxmox runner with the required privileges.

## Security Considerations

1. **Least Privilege**: The sudoers configuration grants only necessary permissions
2. **NOPASSWD**: Required for non-interactive CI/CD execution
3. **Audit Logging**: All sudo commands are logged in `/var/log/auth.log`
4. **Container Isolation**: E2E tests use unprivileged containers when possible
5. **Cleanup**: Workflows include cleanup steps to remove test containers

## Troubleshooting

### Permission Denied Errors

If you see "sudo: a password is required":
- Verify sudoers configuration: `sudo visudo -c -f /etc/sudoers.d/github-runner`
- Check file permissions: `ls -l /etc/sudoers.d/github-runner` (should be 0440)
- Test as runner user: `sudo -u github-runner sudo -n pct version`

### LXC memfd Errors

If you see "Failed to rexec as memfd":
- Ensure `LXC_MEMFD_REXEC` is in `env_keep`
- Use privileged containers for testing
- Check AppArmor/SELinux policies

### Container Cleanup Issues

If containers persist after tests:
- Check workflow cleanup steps
- Manually clean: `pct list | grep gh-e2e | awk '{print $1}' | xargs -I{} pct destroy {} --purge 1`

## Maintenance

### Update Dependencies

Periodically update system packages:

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

### Monitor Disk Usage

E2E tests create containers that consume disk space:

```bash
# Check storage usage
pvesm status

# Clean old containers
pct list | grep gh-e2e
```

### Review Logs

Check runner and workflow logs:

```bash
# Runner logs
journalctl -u actions.runner.* -f

# Sudo logs
sudo tail -f /var/log/auth.log | grep github-runner
```

## Multi-Runner Setup

The project uses two self-hosted runners with different purposes:

### Runner Labels

1. **Proxmox Runner**: `[self-hosted, proxmox]`
   - Location: Proxmox VE server
   - Purpose: E2E tests requiring Proxmox (LXC containers, crun)
   - Workflows: `proxmox_e2e.yml`, `crun_e2e.yml`
   - Service name: `actions.runner.<org>-<repo>.github-runner`

2. **Build/Test Runner**: `[self-hosted, runner0]`
   - Location: Separate server (github-runner0.cp.if.ua)
   - Purpose: Build, unit tests, security scans, documentation
   - Workflows: `ci_cncf.yml`, `security.yml`, `simple_ci.yml`, `basic_test.yml`, etc.
   - Service name: `actions.runner.<org>-<repo>.github-runner0`
   - **Note**: This runner does NOT have Proxmox installed

### Installing Runner0 (Build/Test Server)

On the build/test server (github-runner0.cp.if.ua):

1. **Download and configure the runner**:

```bash
# Create directory for runner
mkdir -p ~/actions-runner
cd ~/actions-runner

# Download runner (use latest version)
curl -o actions-runner-linux-x64-2.328.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.328.0/actions-runner-linux-x64-2.328.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.328.0.tar.gz

# Configure with runner0 label
./config.sh --url https://github.com/cageforge/nexcage \
  --token <YOUR_TOKEN> \
  --name github-runner0 \
  --labels self-hosted,runner0
```

2. **Install as service**:

```bash
sudo ./svc.sh install github-runner
sudo ./svc.sh start
```

3. **Install required dependencies**:

```bash
# Install Zig
curl -L https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz | tar -xJ
sudo mv zig-linux-x86_64-0.15.1 /usr/local/zig
echo 'export PATH=/usr/local/zig:$PATH' >> ~/.bashrc

# Install build dependencies
sudo apt-get update
sudo apt-get install -y \
  libcap-dev \
  libseccomp-dev \
  libyajl-dev \
  build-essential \
  git \
  curl \
  wget
```

**Note**: Runner0 does NOT need Proxmox, `pct`, `pvesh`, or `pvesm` installed.

### Verify Both Runners

```bash
# Check runner services
systemctl status actions.runner.*

# Both should show as active
sudo systemctl list-units 'actions.runner.*'
```

### Workflow Distribution

Workflows are distributed by purpose:

**Proxmox Runner** (`[self-hosted, proxmox]`):
- `proxmox_e2e.yml` - LXC container lifecycle tests
- `crun_e2e.yml` - OCI container lifecycle tests
- Any workflow requiring Proxmox VE access

**Runner0** (`[self-hosted, runner0]`):
- `ci_cncf.yml` - Build and test matrix (runs on both runners)
- `security.yml` - Security scans (CodeQL, Semgrep, Trivy, Gitleaks)
- `simple_ci.yml`, `basic_test.yml` - Unit tests and builds
- `oci_smoke.yml` - OCI smoke tests
- `docs.yml` - Documentation checks
- `dependencies.yml` - Dependency updates
- `permissions.yml` - Permission checks

**Load Balancing**:
- `ci_cncf.yml` uses matrix strategy to run jobs on both runners in parallel
- GitHub automatically assigns jobs to available runners with matching labels
- If one runner is offline, jobs queue for the available runner

### Benefits

- **Specialized runners**: Proxmox tests isolated from build/test workloads
- **Parallel execution**: Build matrix runs simultaneously on both runners
- **Resource efficiency**: Build-heavy jobs don't impact Proxmox server
- **High availability**: Critical builds continue if Proxmox runner is down

## References

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [LXC Container Management](https://pve.proxmox.com/wiki/Linux_Container)
