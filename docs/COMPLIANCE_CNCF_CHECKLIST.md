# CNCF/Open-Source Compliance Checklist (Initial)

Status legend: [x] present/ok, [~] partial, [ ] missing

- [x] LICENSE (Apache-2.0 or compatible)
- [x] CODE_OF_CONDUCT.md
- [x] CONTRIBUTING.md
- [x] SECURITY.md (vuln reporting)
- [x] GOVERNANCE.md
- [x] MAINTAINERS.md
- [x] CODEOWNERS
- [x] README.md (project overview, build, usage)
- [x] CHANGELOG.md (Keep a Changelog)
- [x] Release notes (docs/releases/NOTES_v0.7.0.md)
- [x] Roadmap (Roadmap/*)
- [x] Issue templates (docs/ISSUE_TEMPLATE/*)
- [x] Pull request template (docs/pull_request_template.md)
- [x] CI/CD docs (docs/CI_CD_SETUP.md)
- [x] SECURITY process (docs/SECURITY.md)
- [x] Contribution workflow (docs/DEVELOPMENT_WORKFLOW.md)
- [x] Testing guide (TESTING.md, scripts/*)
- [~] Automated CI gates for unit/integration/e2e (improve coverage and gating)
- [~] SBOM/Provenance (consider adding SLSA/Provenance, CycloneDX)
- [~] Code scanning (CodeQL/scorecards)
- [~] DCO/CLA (consider DCO bot)
- [x] Release artifacts (GitHub Releases with binaries)

Next steps:
- Add CI matrix with mandatory unit/integration/e2e and artifacts upload
- Integrate OpenSSF Scorecards and CodeQL
- Provide SBOM (CycloneDX) and provenance (SLSA) for releases
- Consider DCO bot for contributions
