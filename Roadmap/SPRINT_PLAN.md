# Sprint Plan (Current)

Date: 2025-10-05
Sprint Length: 1–2 weeks

## Goals (Zig 0.15.1 Adoption included)
- Verify alignment with current architecture (docs/architecture/*, ADR-001)
- Stabilize LXC via pct create/start/stop/delete
- Minimal OCI (crun/runc) create/start/stop/delete with bundle generation
- CI/CD: stable green across all workflows, amd64 only (Zig 0.15.1)
- Docs: Developer onboarding complete and consistent
- Release target: version 0.6.0 at sprint end

## Scope / Tasks

### 1) Architecture Conformance Check
- Review ADR-001 against implementation (routing via core Config.getContainerType) [A]
- Ensure CLI does not call BackendManager directly; uses routing + direct backend calls [A]
- Confirm `src/backends/lxc` uses pct CLI for all ops [A]
- Ensure `src/backends/crun` and `src/backends/runc` minimal parity (create/start/stop/delete) [A]
- Output: short report in `docs/architecture/CONFORMANCE_REPORT.md`

### 2) LXC Backend (pct) – Complete Create
- Implement `pct create` with required args (hostname, cores, memory, net) [A]
- Error mapping → core.Error; structured logs [A]
- Acceptance: create/start/stop/delete via self-hosted E2E passes

### 3) OCI Backends (crun/runc) – Minimal Lifecycle
- Bundle generator: rootfs path + minimal config.json [A]
- Commands: create/start/stop/delete with exit code handling [A]
- Acceptance: local smoke (no Proxmox) runs; self-hosted E2E optional smoke

### 4) CI/CD & Security
- Keep all workflows green (Basic Test, AMD64 Only, Simple CI, Security, Proxmox E2E, CI (CNCF), Release) on Zig 0.15.1 [A]
- SBOM published in releases (done); validate artifact naming [A]
- Documentation workflow remains green (lint/spell/links) [A]

### 5) Documentation
- README: quick start (done), keep up-to-date [A]
- DEV_QUICKSTART & CLI_REFERENCE present and accurate; update all Zig references to 0.15.1 [A]
- Add `docs/architecture/CONFORMANCE_REPORT.md` [A]
- Documentation standards reflect archival policy (done)

### 6) Developer Onboarding Verification
- Walk through docs/DEV_QUICKSTART.md and docs/dev_guide.md on a clean Ubuntu host [A]
- Validate environment setup steps (deps, Zig 0.15.1, build, run, tests) [A]
- Confirm steps are minimal and unambiguous; note time-to-first-build [A]
- File issues/PRs if any blockers or unclear steps are found [A]

## Acceptance Criteria
- All CI workflows green on main for 3 successive commits
- LXC create works on Proxmox self-hosted runner with basic template
- OCI crun/runc commands run locally (help + no-crash), bundle generated in expected path
- Conformance report created and linked from `docs/architecture/OVERVIEW.md`
- Release v0.6.0 tagged and notes published

## Out of Scope
- Multi-arch builds
- Full networking/CNI stack
- Advanced security hardening

## Risks
- pct create instability on environment differences → mitigate with detailed logs
- Missing templates on Proxmox host → document prerequisites

## Tracking
- Owner: TBD (@cageforge/@moriarti)
- Report: `Roadmap/SPRINT_PROGRESS.md` (daily/at end)
- Note: This sprint includes adoption and verification of Zig 0.15.1 across codebase, docs, and CI.
