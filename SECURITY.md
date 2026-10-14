# Security Policy

## Reporting a Vulnerability
- Please report security issues privately, through GitHub's private vulnerability reporting: [Report a vulnerability](https://github.com/CageForge/nexcage/security/advisories/new) on the repository's Security tab. The maintainer is listed in [MAINTAINERS.md](MAINTAINERS.md), which gives no e-mail address: if a report cannot go through GitHub, open an issue asking the maintainer for another way to send it, with no detail of the vulnerability in it.
- We aim to acknowledge within 2 business days and provide a remediation plan or timeline.

## Supported Versions
- We support the latest minor version and the previous minor for critical security fixes.

## Disclosure
- Coordinated disclosure preferred; we'll credit reporters in release notes unless anonymity requested.

## What nexcage protects, and what it does not
- [ADR-003](docs/architecture/ADR-003-Security-Architecture.md) is the threat model of what ships: what nexcage runs as, what it trusts, what it validates and refuses, and where, each claim pointing at the code or a test. [ISOLATION.md](docs/architecture/ISOLATION.md) says what each execution mode keeps a container from, and what it leaves to the bundle and to the operator.
- Something nexcage does that those documents say it refuses or prevents is a vulnerability. What they list as not guaranteed is a known limit, not a vulnerability: for example host bind mounts from a bundle on Proxmox LXC, hooks and `run.oci.*` annotations libcrun honours on crun, or what an isolation profile does not cover.
- nexcage does not scan or verify images, keep an audit log, monitor containers or enforce network policy, and makes no compliance claim.
- [The 2026-10 hardening audit](docs/audits/2026-10-hardening-audit.md) lists the defects found in 0.17.0, which are fixed, fixed in part or wait on the maintainer, the commits and tests for each, and the risks still open, each with an owner.

## Verifying a release
- `checksums.txt` shows a download is the file published next to it. From the first release after 0.17.0, `release.yml` makes a GitHub build attestation for the binary and the `.deb` when it builds them; no release has been made with that step yet. For such a release, `gh attestation verify <file> -R CageForge/nexcage` checks that the file came from that workflow in this repository, and from which commit ([docs/INSTALL.md](docs/INSTALL.md)). `provenance.json` is a statement the workflow writes about itself and is not signed, and the CycloneDX SBOM lists no components ([#318](https://github.com/CageForge/nexcage/issues/318), [#333](https://github.com/CageForge/nexcage/issues/333)).

## CI
- Workflows pin every third-party action to a commit and grant each job only the token permissions it needs; `security.yml` fails on what zizmor, Semgrep, Trivy and Gitleaks find. None of these scanners reads Zig or libcrun's C.
- The self-hosted Proxmox VE runners run jobs as root. A pull request runs its own copy of the workflows, so a workflow's `if:` does not keep a fork off them. Every outside contributor's run needs a maintainer's approval (the fork-PR approval policy is `all_external_contributors`), and until the runners are restricted that approval is the only barrier. What else is to be done, by an administrator, is in [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md#self-hosted-runners-and-forks) and in the audit's [remaining steps](docs/audits/2026-10-hardening-audit.md#the-maintainers-remaining-steps).
