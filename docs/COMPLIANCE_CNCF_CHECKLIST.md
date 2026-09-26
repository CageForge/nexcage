# CNCF/Open-Source Compliance Checklist

Status legend: [x] present/ok, [~] partial, [ ] missing

## Required Files

- [x] LICENSE (Apache-2.0 or compatible)
- [x] CODE_OF_CONDUCT.md
- [x] CONTRIBUTING.md
- [x] SECURITY.md (vuln reporting)
- [x] GOVERNANCE.md
- [x] MAINTAINERS.md
- [x] CODEOWNERS
- [x] README.md (project overview, build, usage)
- [x] CHANGELOG.md (Keep a Changelog format)
- [x] Release notes (docs/releases/NOTES_vX.Y.Z.md)
- [x] Issue templates (.github/ISSUE_TEMPLATE/*)
- [x] Pull request template (docs/pull_request_template.md)
- [x] CI/CD docs (docs/CI_CD_SETUP.md)
- [x] SECURITY process (docs/SECURITY.md)
- [x] Contribution workflow (docs/DEVELOPMENT_WORKFLOW.md)
- [x] Testing guide (TESTING.md, scripts/*)

## CI/CD & Quality

- [x] **Automated CI gates** for unit/integration/e2e
  - Mandatory build, unit tests and exit-code smoke tests (`.github/workflows/ci.yml`)
  - Lifecycle E2E on a self-hosted Proxmox VE runner (`.github/workflows/proxmox_e2e.yml`)
  - Tests must pass for CI to succeed

- [x] **SBOM/Provenance**
  - SPDX JSON SBOM (existing, via anchore/sbom-action)
  - CycloneDX JSON SBOM (new, via cyclonedx-action)
  - SLSA Provenance (basic implementation in release workflow)
  - All artifacts uploaded to GitHub Releases

- [~] **Code scanning**
  - Semgrep, Trivy and Gitleaks (`.github/workflows/security.yml`), non-blocking
  - OpenSSF Scorecards (`.github/workflows/scorecards.yml`), currently disabled by GitHub for inactivity
  - No CodeQL: it supports C/C++ but not Zig, and the repository has no C/C++ sources of its own

- [ ] **DCO/CLA** — not used
  - The DCO check was removed on 2026-09-15: its action had been deleted
    upstream, so it failed on every PR, and no commit carried a
    `Signed-off-by` trailer. Contributions are accepted under the Apache
    License 2.0 without a sign-off.

- [x] Release artifacts (GitHub Releases with binaries, SBOMs, provenance)
  - Two binaries since 0.11.2: the default one, and `-crun` with the OCI
    runtime backend compiled in. The second is built through the Dockerfile,
    because vendored libcrun needs the submodules and generated headers, and
    the job checks the backend is really in it by asking the binary for
    `features` -- an answer only libcrun can give.

## Implementation Details

### CI Gates (`.github/workflows/ci.yml`)
- Debug and ReleaseSafe builds on GitHub-hosted runners
- `zig build test`: every test file is its own step
- Smoke tests check exit codes (1 without Proxmox tools, 2 for an unknown command)
- Proxmox E2E (`proxmox_e2e.yml`) runs the container lifecycle through nexcage

### SBOM & Provenance (`.github/workflows/release.yml`)
- **SPDX JSON**: Generated via `anchore/sbom-action@v0`
- **CycloneDX JSON**: Generated via `cyclonedx/cyclonedx-action@v1`
- **SLSA Provenance**: Basic in-toto statement with build metadata
- All artifacts uploaded and included in GitHub Releases

### Code Scanning
- **OpenSSF Scorecards**: `scorecards.yml`, weekly and on push (disabled by GitHub for inactivity)
- **Semgrep**: SAST scanning in `security.yml`
- **Trivy**: Filesystem scanning in `security.yml`
- **Gitleaks**: Secret scanning in `security.yml`

## Compliance Status

**Overall Status**: [~] **Partial**

- ✅ Required documentation files
- ✅ Automated CI with mandatory gates
- ✅ SBOM (SPDX + CycloneDX) generation
- ✅ SLSA Provenance (basic)
- ✅ Code scanning (Semgrep, Trivy, Gitleaks); Scorecards disabled
- ➖ DCO / CLA: not used; contributions need no sign-off

## Known Gaps

Named rather than left for someone to discover:

- [ ] **ADOPTERS.md** — there are none to list yet, and an empty file would say
      less than its absence.
- [ ] **ROADMAP.md** — what is missing is tracked in the gap table of
      `docs/KUBERNETES_INTEGRATION.md` and in each release's notes, not in a
      roadmap of its own.
- [~] **OpenSSF Scorecards** — the workflow exists and GitHub disabled it for
      inactivity, so there is deliberately no Scorecard badge in the README: a
      badge for a check that does not run is worse than none.
- [ ] **A public communication channel** beyond GitHub Issues.

## Optional Enhancements

- [ ] Enhance SLSA Provenance to Level 3 (requires additional setup)
- [ ] Add automated dependency vulnerability scanning
- [ ] Add license compliance checking in CI
- [ ] Consider CLA for enterprise contributions (if needed)
- [ ] Add SBOM attestation signing
- [ ] Enhanced provenance with full build attestation

## References

- [CNCF Project Requirements](https://www.cncf.io/about/charter/)
- [OpenSSF Best Practices](https://openssf.org/best-practices/)
- [SLSA Framework](https://slsa.dev/)
