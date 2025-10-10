# GitHub Runner Verification Guide

## Overview

This guide describes how to verify that self-hosted GitHub Actions runners are properly configured and operational.

## 1. Check Runner Status via GitHub API

```bash
# List all runners with their status
gh api repos/cageforge/nexcage/actions/runners --jq '.runners[] | {id, name, status, busy, labels: [.labels[].name]}'

# Check specific runner by ID
gh api repos/cageforge/nexcage/actions/runners/22 --jq '{name, status, busy, labels: [.labels[].name]}'
```

Expected output:
```json
{
  "busy": false,
  "labels": ["self-hosted", "Linux", "X64", "runner0"],
  "name": "github-runner0",
  "status": "online"
}
```

## 2. Verify Runner Configuration on Server

### On github-runner0.cp.if.ua:

```bash
# Check systemd service status
sudo systemctl status actions.runner.cageforge-nexcage.github-runner0.service

# View runner configuration
cat ~/actions-runner/.runner

# Check runner logs
journalctl -u actions.runner.cageforge-nexcage.github-runner0.service -f
```

### On mgr.cp.if.ua (proxmox-runner):

```bash
# Check systemd service status
sudo systemctl status actions.runner.cageforge-nexcage.proxmox-runner.service

# View runner configuration
cat /opt/github-runner/.runner

# Check runner logs
journalctl -u actions.runner.cageforge-nexcage.proxmox-runner.service -f
```

## 3. Test Runner with Workflow Dispatch

### Method 1: Via GitHub CLI

```bash
# Trigger a workflow that runs on runner0
gh workflow run basic_test.yml

# Wait and check which runner executed it
gh run list --workflow=basic_test.yml --limit 1
RUN_ID=$(gh run list --workflow=basic_test.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view $RUN_ID --log | grep "Runner name"
```

### Method 2: Via GitHub Web UI

1. Go to https://github.com/cageforge/nexcage/actions
2. Select a workflow (e.g., "Basic Test")
3. Click "Run workflow" button
4. Select branch and click "Run workflow"
5. Click on the running workflow
6. Expand "Set up job" step
7. Look for "Runner name: 'github-runner0'" or "Runner name: 'proxmox-runner'"

## 4. Verify Runner Labels

Runners must have correct labels to match workflow `runs-on` requirements:

### github-runner0 (Build/Test Runner)
- **Labels**: `self-hosted`, `Linux`, `X64`, `runner0`
- **Purpose**: Build, unit tests, security scans (no Proxmox)
- **Workflows**: `basic_test.yml`, `simple_ci.yml`, `security.yml`, `oci_smoke.yml`

### proxmox-runner (E2E Runner)
- **Labels**: `self-hosted`, `Linux`, `X64`, `proxmox`, `ubuntu`
- **Purpose**: E2E tests with Proxmox LXC/crun
- **Workflows**: `proxmox_e2e.yml`, `crun_e2e.yml`

## 5. Common Issues and Solutions

### Issue: Workflow runs on wrong runner

**Symptom**: Workflow configured with `runs-on: [self-hosted, runner0]` executes on `proxmox-runner`

**Possible causes**:
1. Runner labels not properly configured
2. GitHub Actions cache not updated
3. Runner service not restarted after configuration change

**Solution**:
```bash
# On github-runner0.cp.if.ua
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall

# Re-configure with correct labels
./config.sh remove --token <REMOVAL_TOKEN>
./config.sh --url https://github.com/cageforge/nexcage \
  --token <NEW_TOKEN> \
  --name github-runner0 \
  --labels self-hosted,runner0 \
  --unattended

# Reinstall service
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

### Issue: Runner shows as offline

**Symptom**: `gh api` shows `"status": "offline"`

**Solution**:
```bash
# Check service status
sudo systemctl status actions.runner.cageforge-nexcage.github-runner0.service

# Restart service
sudo systemctl restart actions.runner.cageforge-nexcage.github-runner0.service

# Check logs for errors
journalctl -u actions.runner.cageforge-nexcage.github-runner0.service -n 50
```

### Issue: Runner registration token expired

**Symptom**: `HTTP 404: Not Found` or `Response status code does not indicate success: 404 (Not Found)`

**Solution**:
```bash
# Generate new registration token (valid for 1 hour)
gh api -X POST repos/cageforge/nexcage/actions/runners/registration-token --jq '.token'

# Use the new token immediately
./config.sh --url https://github.com/cageforge/nexcage \
  --token <NEW_TOKEN> \
  --name github-runner0 \
  --labels self-hosted,runner0 \
  --unattended
```

## 6. Monitoring Runner Activity

### Real-time monitoring via GitHub API

```bash
# Watch runner status (refresh every 5 seconds)
watch -n 5 'gh api repos/cageforge/nexcage/actions/runners --jq ".runners[] | {name, status, busy}"'

# List recent workflow runs
gh run list --limit 10

# Watch specific workflow
watch -n 5 'gh run list --workflow=basic_test.yml --limit 5'
```

### Check runner resource usage

```bash
# On runner server
top -u github-runner
ps aux | grep Runner.Listener
df -h  # Check disk space
free -h  # Check memory
```

## 7. Verification Checklist

- [ ] Both runners show `"status": "online"` in GitHub API
- [ ] Each runner has correct labels configured
- [ ] Systemd services are active and enabled
- [ ] Test workflows execute on correct runners
- [ ] Workflow logs show correct "Runner name"
- [ ] No errors in runner service logs
- [ ] Runners have required dependencies installed (Zig, build tools)
- [ ] Sufficient disk space and memory available

## 8. Quick Verification Script

```bash
#!/bin/bash
# verify_runners.sh

echo "=== GitHub Runners Status ==="
gh api repos/cageforge/nexcage/actions/runners --jq '.runners[] | "Runner: \(.name)\nStatus: \(.status)\nBusy: \(.busy)\nLabels: \(.labels | map(.name) | join(", "))\n---"'

echo -e "\n=== Recent Workflow Runs ==="
gh run list --limit 5

echo -e "\n=== Test Basic Workflow on runner0 ==="
gh workflow run basic_test.yml
sleep 10
RUN_ID=$(gh run list --workflow=basic_test.yml --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Run ID: $RUN_ID"
gh run view $RUN_ID --log | grep "Runner name" | head -1
```

## References

- [GitHub Actions Self-hosted Runners Documentation](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub REST API - Actions Runners](https://docs.github.com/en/rest/actions/self-hosted-runners)
- [Project Self-hosted Runner Setup](./SELF_HOSTED_RUNNER_SETUP.md)

