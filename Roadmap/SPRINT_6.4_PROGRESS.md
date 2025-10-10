# Sprint 6.4 Progress: GitHub Actions Optimization

**Issue**: #106  
**Branch**: `feat/optimize-github-actions`

## Time Spent

- 2025-10-10: Created new branch and deleted duplicate workflow — 5m
- 2025-10-10: Implemented crun E2E test workflow — 45m
- 2025-10-10: Added multi-runner support to ci_cncf.yml and proxmox_e2e.yml — 20m
- 2025-10-10: Updated documentation and setup script — 25m
- 2025-10-10: Created GitHub issue #106 — 10m
- 2025-10-10: Committed and pushed changes — 5m
- 2025-10-10: Created pull request #107 — 5m
- 2025-10-10: Fixed matrix syntax in crun_e2e.yml — 5m
- 2025-10-10: Configured runner0 for build/test workloads (separate from Proxmox) — 30m
- 2025-10-10: Updated runner version to 2.328.0 in setup scripts — 10m
- 2025-10-10: Registered github-runner0 on github-runner0.cp.if.ua — 15m
- 2025-10-10: Created runner verification guide and test workflow — 30m
- 2025-10-10: Reorganized workflows and release notes — 45m

**Total time**: 4 hours 15 minutes

## Completed Tasks

- [x] Deleted `.github/workflows/amd64_only.yml`
- [x] Created `.github/workflows/crun_e2e.yml` with full lifecycle tests
- [x] Updated `.github/workflows/ci_cncf.yml` with runner matrix
- [x] Updated `.github/workflows/proxmox_e2e.yml` with runner matrix
- [x] Added multi-runner documentation to `docs/SELF_HOSTED_RUNNER_SETUP.md`
- [x] Updated `scripts/setup_runner_permissions.sh` with notes
- [x] Created GitHub issue #106
- [x] Committed and pushed all changes
- [x] Created pull request #107
- [x] Fixed workflow syntax issues
- [x] Registered and configured github-runner0
- [x] Created runner verification documentation
- [x] Reorganized workflows (deleted obsolete, disabled unused)
- [x] Reorganized release notes into docs/releases/

## Pending Tasks

- [x] Install and configure `github-runner0` on github-runner0.cp.if.ua
- [x] Register runner with correct labels
- [x] Reorganize and cleanup workflows
- [ ] Verify runner executes workflows correctly (requires server-side troubleshooting)
- [ ] Test crun E2E workflow execution
- [ ] Measure CI execution time improvement
- [ ] Review and merge PR #107

## Notes

- All code changes implemented and pushed to `feat/optimize-github-actions` branch
- Runner separation implemented:
  - **Proxmox runner** (`[self-hosted, proxmox]`): LXC and crun E2E tests
  - **Runner0** (`[self-hosted, runner0]`): Build, unit tests, security scans
- Runner0 location: github-runner0.cp.if.ua (no Proxmox installed)
- `ci_cncf.yml` uses matrix to run on both runners in parallel
- Crun E2E tests include minimal OCI bundle generation
- Tests use busybox for minimal rootfs
- Graceful cleanup of test containers implemented
- Documentation updated with runner purposes and setup instructions

## Workflow Reorganization

- **Deleted obsolete workflows**:
  - `ci.yml` - replaced by `ci_cncf.yml`
  - `basic_test.yml` - functionality merged into other workflows
  - `simple_ci.yml` - replaced by `ci_cncf.yml`
  - `Dockerfile` - not a workflow file

- **Disabled workflows** (renamed to `.disabled`):
  - `oci_smoke.yml` - pending OCI implementation
  - `permissions.yml` - not currently needed
  - `simple-ci.yml.disabled` - already disabled

- **Updated workflows**:
  - All workflows now use appropriate self-hosted runner labels
  - Removed dependency installation steps (pre-installed on runners)
  - Fixed matrix configurations for multi-runner support

- **Release notes reorganization**:
  - Moved to `docs/releases/` directory
  - Renamed to `NOTES_v*.md` format for consistency
  - Added `NOTES_v0.4.0.md` for upcoming release

## Current Issue

**Problem**: Workflows with `runs-on: [self-hosted, runner0]` are executing on `proxmox-runner` instead of `github-runner0`.

**Status**: 
- ✅ github-runner0 registered and online with correct labels: `self-hosted`, `Linux`, `X64`, `runner0`
- ✅ proxmox-runner online with labels: `self-hosted`, `Linux`, `X64`, `proxmox`, `ubuntu`
- ❌ GitHub Actions not routing workflows to correct runner

**Troubleshooting steps**:
1. Verify runner configuration on server: `cat ~/actions-runner/.runner`
2. Restart runner service: `sudo systemctl restart actions.runner.cageforge-nexcage.github-runner0.service`
3. Check runner logs: `journalctl -u actions.runner.cageforge-nexcage.github-runner0.service -n 50`
4. If needed, reconfigure runner with correct labels

**Documentation created**:
- `docs/RUNNER_VERIFICATION.md` - Complete verification guide
- `.github/workflows/test_runner0.yml` - Test workflow for runner0

## Next Steps

1. Troubleshoot runner label matching issue on github-runner0.cp.if.ua
2. Ensure runner0 has required dependencies (Zig, build tools)
3. Test workflow execution and verify parallel execution
4. Measure CI execution time improvement
5. Review and merge PR #107

