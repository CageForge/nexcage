# Runner0 Setup Instructions

## Overview

Runner0 is a dedicated build/test server at `github-runner0.cp.if.ua` that handles non-Proxmox workflows.

## Current Status

- ✅ Runner installed on server
- ⚠️ Needs label configuration update
- ⚠️ Needs dependency installation

## Required Configuration

### 1. Update Runner Label

The runner needs to be configured with the `runner0` label (not `proxmox-runner0`).

**On github-runner0.cp.if.ua:**

```bash
# Stop the runner service
sudo systemctl stop actions.runner.*

# Navigate to runner directory
cd ~/actions-runner

# Remove current configuration
./config.sh remove --token <REMOVAL_TOKEN>

# Reconfigure with correct label
./config.sh --url https://github.com/cageforge/nexcage \
  --token <NEW_TOKEN> \
  --name github-runner0 \
  --labels self-hosted,runner0

# Restart service
sudo systemctl start actions.runner.*
sudo systemctl status actions.runner.*
```

### 2. Install Required Dependencies

```bash
# Update system
sudo apt-get update

# Install build dependencies
sudo apt-get install -y \
  libcap-dev \
  libseccomp-dev \
  libyajl-dev \
  build-essential \
  git \
  curl \
  wget

# Install Zig 0.15.1
cd /tmp
curl -L https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz -o zig.tar.xz
tar -xf zig.tar.xz
sudo mv zig-linux-x86_64-0.15.1 /usr/local/zig-0.15.1
sudo ln -sf /usr/local/zig-0.15.1/zig /usr/local/bin/zig

# Verify installation
zig version  # Should show 0.15.1
```

### 3. Verify Setup

```bash
# Check runner status
sudo systemctl status actions.runner.*

# Verify it's registered with correct label
# Go to: https://github.com/cageforge/nexcage/settings/actions/runners
# Confirm runner0 shows label: self-hosted, runner0
```

## Workflows Using Runner0

The following workflows will execute on runner0:

- `ci_cncf.yml` - Build and test matrix (also uses Proxmox runner)
- `security.yml` - All security scans (CodeQL, Semgrep, Trivy, Gitleaks)
- `simple_ci.yml` - Simple CI builds
- `basic_test.yml` - Basic tests
- `oci_smoke.yml` - OCI smoke tests
- `docs.yml` - Documentation checks
- `dependencies.yml` - Dependency updates
- `permissions.yml` - Permission checks
- `ci.yml` - Main CI

## What Runner0 Does NOT Need

- ❌ Proxmox VE installation
- ❌ `pct` command
- ❌ `pvesh` command
- ❌ `pvesm` command
- ❌ LXC templates
- ❌ Special sudo permissions for Proxmox tools

## Testing

After setup, trigger a workflow to verify:

```bash
# From local machine
cd /path/to/nexcage
git checkout feat/optimize-github-actions
git pull
gh workflow run simple_ci.yml --ref feat/optimize-github-actions
```

Watch the run at: https://github.com/cageforge/nexcage/actions

The job should:
1. Start immediately (not queue)
2. Show runner name as "github-runner0"
3. Complete successfully

## Troubleshooting

### Workflows Still Queuing

**Problem**: Workflows remain in "queued" state

**Solution**: 
- Verify runner is online: `sudo systemctl status actions.runner.*`
- Check GitHub UI: Settings → Actions → Runners
- Ensure label is exactly `runner0` (not `proxmox-runner0`)

### Build Failures

**Problem**: Zig not found or wrong version

**Solution**:
```bash
# Check Zig version
zig version

# If wrong version, reinstall
sudo rm /usr/local/bin/zig
# Follow installation steps above
```

**Problem**: Missing libraries

**Solution**:
```bash
# Reinstall dependencies
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

## Support

For issues, check:
- Runner logs: `journalctl -u actions.runner.* -f`
- GitHub Actions: https://github.com/cageforge/nexcage/actions
- Documentation: `docs/SELF_HOSTED_RUNNER_SETUP.md`

