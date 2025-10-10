# Sprint 6.4 Plan: GitHub Actions Optimization

**Issue**: #106  
**Branch**: `feat/optimize-github-actions`  
**Duration**: 1-2 days

## Objectives

Optimize GitHub Actions CI/CD pipeline by removing duplicate workflows, adding multi-runner support, and implementing crun E2E tests.

## Tasks

### 1. Remove Duplicate Workflows
- [x] Delete `.github/workflows/amd64_only.yml` (duplicates ci_cncf.yml functionality)
- **Time estimate**: 5 minutes
- **Rationale**: Both workflows build Debug/Release, run tests, and upload artifacts

### 2. Add Second Runner Support
- [x] Update `.github/workflows/ci_cncf.yml` with matrix for both runners
- [x] Update `.github/workflows/proxmox_e2e.yml` with matrix for both runners
- [x] Add runner labels: `[self-hosted, proxmox]` and `[self-hosted, proxmox-runner0]`
- **Time estimate**: 20 minutes
- **Expected benefit**: 2x throughput via parallel execution

### 3. Implement Crun E2E Tests
- [x] Create `.github/workflows/crun_e2e.yml`
- [x] Implement test for `crun create`
- [x] Implement test for `crun start`
- [x] Implement test for `crun stop` (kill TERM)
- [x] Implement test for `crun delete`
- [x] Add cleanup logic for test containers
- **Time estimate**: 45 minutes
- **Expected benefit**: Improved OCI runtime test coverage

### 4. Update Documentation
- [x] Add multi-runner setup section to `docs/SELF_HOSTED_RUNNER_SETUP.md`
- [x] Document runner installation steps
- [x] Document workflow distribution strategy
- [x] Update `scripts/setup_runner_permissions.sh` with multi-runner notes
- **Time estimate**: 25 minutes

### 5. Create GitHub Issue
- [x] Create issue #106 with detailed description
- [x] Include success criteria and timeline
- **Time estimate**: 10 minutes

## Acceptance Criteria

- [x] `amd64_only.yml` deleted and CI passes without it
- [ ] Both runners (`proxmox` and `proxmox-runner0`) operational (requires runner installation)
- [ ] Matrix workflows execute in parallel on both runners
- [ ] Crun E2E tests pass on both runners
- [x] Documentation complete and accurate
- [ ] CI execution time reduced by ~30-40% (to be verified after runner0 setup)

## Expected Benefits

1. **Performance**: 2x throughput for parallel test execution
2. **Reliability**: High availability if one runner fails
3. **Coverage**: Comprehensive OCI runtime testing
4. **Efficiency**: Reduced CI execution time and maintenance overhead

## Dependencies

- Second runner (`github-runner0`) must be installed on Proxmox server
- Busybox or minimal shell must be available on runners for crun tests
- Crun runtime must be installed on runners

## Risks & Mitigations

**Risk**: Crun not installed on runners  
**Mitigation**: Tests will skip gracefully with clear error message

**Risk**: Runner0 not configured  
**Mitigation**: Workflows will queue for available runner (proxmox)

**Risk**: Resource contention on same Proxmox host  
**Mitigation**: Concurrency limits and resource isolation via separate runner processes

## Timeline

- Sprint start: 2025-10-10
- Implementation: 2025-10-10 (1.5 hours)
- Testing: 2025-10-10-11 (pending runner0 setup)
- Sprint completion: 2025-10-11 (estimated)

