## Sprint 6.5 — Docs & Roadmap Final Audit (v0.7.0)

This document consolidates what was delivered vs. not delivered based on `docs/` and `Roadmap/` contents for Sprint 6.5 and adjacent work related to v0.7.0.

### Delivered (Done)
- CLI features:
  - OCI `kill` (with `--signal`) and `state` commands documented in `docs/CLI_REFERENCE.md` and `docs/user_guide.md`.
  - Debug logging gating via `--debug` reflected in docs.
- Proxmox LXC:
  - Image parsing rules clarified (templates vs docker-style refs) in docs; implementation in driver.
  - ZFS pool/dataset validation (+ parent auto-create) implemented; behavior captured in Roadmap progress.
  - Path security hardening for OCI bundles (canonicalization, allowed prefixes) noted in Roadmap and represented in code.
- Stability:
  - Logger allocator fix; segfault in `create` resolved (Roadmap entries present).
  - Input validators added; hostname validation enforced in CLI.
- Release management:
  - `VERSION` bumped to `0.7.0`; `CHANGELOG.md` updated; release notes added `docs/releases/NOTES_v0.7.0.md`.
  - GitHub Release v0.7.0 published (artifact uploaded).
- Roadmap docs added/updated:
  - `SPRINT_6.5_PROGRESS.md`, `SPRINT_6.5_CLOSURE.md`, `SPRINT_6.5_FINAL_SUMMARY.md`.
  - Compliance checklist created: `docs/COMPLIANCE_CNCF_CHECKLIST.md`.

### Partially Delivered (In Progress / Partial)
- E2E coverage:
  - Proxmox e2e smoke passes; functional `create/start/stop/kill/delete` flows not yet fully green on target PVE (see test report path in Roadmap).
- CNCF/Open Source maturity:
  - Checklist added; gaps remain (CI gating matrix, SBOM/provenance, code scanning, DCO).
- Documentation completeness:
  - Core docs are aligned, but need a CNCF-focused CONTRIBUTING/SECURITY references to governance + automation details.

### Not Delivered (Out of Scope or Pending)
- Automatic handling of docker-style refs (`ubuntu:20.04`) in Proxmox flow (explicitly not supported; requires future feature for fetching/conversion).
- 100% green e2e for all backends and operations on Proxmox (pending create/start stabilization and environment provisioning).
- CI hard gates for unit/integration/e2e with artifacts; SBOM/Provenance generation in CI; CodeQL/Scorecards; DCO bot.

### Recommended Next Steps
1. Stabilize Proxmox `create/start` lifecycle; raise e2e pass rate to ~100%.
2. Extend validators and path hardening across remaining backends.
3. CI improvements:
   - Add matrix (unit/integration/e2e) with gates; upload test reports/artifacts.
   - Add OpenSSF Scorecards and CodeQL scanning.
   - Generate SBOM (CycloneDX) and SLSA provenance for releases.
   - Consider DCO bot for contributions.
4. Optional: implement image fetch/convert for docker-style refs in Proxmox workflow.

### References (selected)
- `docs/CLI_REFERENCE.md`, `docs/user_guide.md`
- `docs/releases/NOTES_v0.7.0.md`
- `Roadmap/SPRINT_6.5_PROGRESS.md`, `Roadmap/SPRINT_6.5_CLOSURE.md`, `Roadmap/SPRINT_6.5_FINAL_SUMMARY.md`
- `docs/COMPLIANCE_CNCF_CHECKLIST.md`
