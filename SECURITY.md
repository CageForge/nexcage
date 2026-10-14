# Security Policy

## Reporting a Vulnerability
- Please report security issues privately via GitHub Security Advisories or by email to maintainers listed in MAINTAINERS.md.
- We aim to acknowledge within 2 business days and provide a remediation plan or timeline.

## Supported Versions
- We support the latest minor version and the previous minor for critical security fixes.

## Disclosure
- Coordinated disclosure preferred; we'll credit reporters in release notes unless anonymity requested.

## Verifying a release
- `checksums.txt` shows a download is the file published next to it. Releases after 0.17.0 also have a GitHub build attestation for the binary and the `.deb`, made by `release.yml` when it built them: `gh attestation verify <file> -R CageForge/nexcage` checks that the file came from that workflow in this repository, and from which commit ([docs/INSTALL.md](docs/INSTALL.md)).

## CI
- Workflows pin every third-party action to a commit and grant each job only the token permissions it needs; `security.yml` fails on what zizmor, Semgrep, Trivy and Gitleaks find.
- The self-hosted Proxmox VE runners run jobs as root. A pull request runs its own copy of the workflows, so a workflow's `if:` does not keep a fork off them; what does, and what is still to be done, is in [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md#self-hosted-runners-and-forks).
