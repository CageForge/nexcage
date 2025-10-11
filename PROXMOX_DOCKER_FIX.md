# Proxmox Runner Docker Permission Fix

## Problem

Docker-based GitHub Actions workflows fail with:
```
ERROR: permission denied while trying to connect to the Docker daemon socket
```

## Solution

On the **mgr.cp.if.ua** (proxmox-runner) server, run:

```bash
# Add github-runner user to docker group
sudo usermod -aG docker github-runner

# Restart runner service to apply group changes
sudo systemctl restart actions.runner.cageforge-nexcage.proxmox-runner.service

# Verify Docker access
sudo -u github-runner docker ps
```

## Verification

After applying the fix, the following workflows should work:
- **Documentation** → `dead-links` job (markdown link checking)
- **Security** → `semgrep` job (SAST scanning)
- **Security** → `trivy-fs` job (vulnerability scanning)

## Test

Trigger a workflow manually to verify:
```bash
gh workflow run docs.yml
```

Then check the status:
```bash
gh run list --workflow=docs.yml --limit 1
```

## Note

This fix is only needed on the **proxmox-runner** (mgr.cp.if.ua).

The **runner0** (github-runner0.cp.if.ua) does NOT have Docker installed and should not run Docker-based workflows.

