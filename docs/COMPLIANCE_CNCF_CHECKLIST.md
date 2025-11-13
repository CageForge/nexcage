# CNCF/Open-Source Compliance Checklist

Status legend: [x] present/ok, [~] partial, [ ] missing

## Required Files

- [x] LICENSE (Apache-2.0 or compatible)
- [x] CODE_OF_CONDUCT.md
- [x] CONTRIBUTING.md (includes DCO information)
- [x] SECURITY.md (vuln reporting)
- [x] GOVERNANCE.md
- [x] MAINTAINERS.md
- [x] CODEOWNERS
- [x] README.md (project overview, build, usage)
- [x] CHANGELOG.md (Keep a Changelog format)
- [x] Release notes (docs/releases/NOTES_vX.Y.Z.md)
- [x] Roadmap (Roadmap/*)
- [x] Issue templates (docs/ISSUE_TEMPLATE/*)
- [x] Pull request template (docs/pull_request_template.md)
- [x] CI/CD docs (docs/CI_CD_SETUP.md)
- [x] SECURITY process (docs/SECURITY.md)
- [x] Contribution workflow (docs/DEVELOPMENT_WORKFLOW.md)
- [x] Testing guide (TESTING.md, scripts/*)

## CI/CD & Quality

- [x] **Automated CI gates** for unit/integration/e2e
  - Mandatory unit tests (`.github/workflows/ci_cncf.yml`)
  - Mandatory smoke tests with proper exit codes
  - Mandatory integration tests when conditions are met
  - Tests must pass for CI to succeed

- [x] **SBOM/Provenance**
  - SPDX JSON SBOM (existing, via anchore/sbom-action)
  - CycloneDX JSON SBOM (new, via cyclonedx-action)
  - SLSA Provenance (basic implementation in release workflow)
  - All artifacts uploaded to GitHub Releases

- [x] **Code scanning**
  - CodeQL (`.github/workflows/security.yml`)
  - OpenSSF Scorecards (`.github/workflows/scorecards.yml` - new)
  - Weekly scheduled runs for continuous monitoring

- [x] **DCO/CLA**
  - DCO check workflow (`.github/workflows/dco.yml` - new)
  - Automatic PR checking for DCO signoff
  - DCO documentation in CONTRIBUTING.md
  - Clear failure messages with instructions

- [x] Release artifacts (GitHub Releases with binaries, SBOMs, provenance)

## Implementation Details

### CI Gates (`.github/workflows/ci_cncf.yml`)
- Unit tests: `continue-on-error: false` - mandatory
- Smoke tests: Proper exit code checking - mandatory
- Integration tests: Mandatory when Proxmox available
- All tests must pass for CI to succeed

### SBOM & Provenance (`.github/workflows/release.yml`)
- **SPDX JSON**: Generated via `anchore/sbom-action@v0`
- **CycloneDX JSON**: Generated via `cyclonedx/cyclonedx-action@v1`
- **SLSA Provenance**: Basic in-toto statement with build metadata
- All artifacts uploaded and included in GitHub Releases

### Code Scanning
- **CodeQL**: Integrated in `security.yml`, runs on push/PR
- **OpenSSF Scorecards**: New workflow `scorecards.yml`, runs weekly + on push
- **Semgrep**: SAST scanning in `security.yml`
- **Trivy**: Filesystem scanning in `security.yml`
- **Gitleaks**: Secret scanning in `security.yml`

### DCO Check (`.github/workflows/dco.yml`)
- Runs on PR open/update/ready_for_review
- Checks all commits for `Signed-off-by:` trailer
- Provides clear instructions for fixing failed checks
- Fully documented in CONTRIBUTING.md

## Compliance Status

**Overall Status**: ✅ **CNCF Compliant**

All required CNCF compliance items are implemented:
- ✅ Required documentation files
- ✅ Automated CI/CD with mandatory gates
- ✅ SBOM (SPDX + CycloneDX) generation
- ✅ SLSA Provenance (basic)
- ✅ Code scanning (CodeQL + Scorecards)
- ✅ DCO enforcement for contributions

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
- [DCO](https://developercertificate.org/)
