# CI/CD

## Workflows

| Workflow | Runs on | Trigger | What it checks |
|---|---|---|---|
| `ci.yml` | ubuntu-24.04 | push/PR to `main` | Debug and ReleaseSafe builds, `zig build test`, smoke tests of exit codes. **The required check.** |
| `proxmox_e2e.yml` | self-hosted, `proxmox` | push/PR to `main`/`develop` | create → state → start → stop → delete through the built binary on Proxmox VE |
| `crun_build.yml` | ubuntu-24.04 | push to `main`; PRs touching build, Dockerfile or crun | Docker build with `-Denable-backend-crun=true` |
| `memory_leak_check.yml` | ubuntu-22.04 | push/PR | Valgrind over basic commands |
| `security.yml` | ubuntu-latest | push/PR to `main`, weekly | Semgrep, Trivy, Gitleaks (non-blocking) |
| `version-check.yml` | ubuntu-22.04 | push/PR | `VERSION` is semver and appears in `nexcage --help` |
| `release.yml` | ubuntu-24.04 | tag `v*` | Tests, ReleaseSafe binary, `.deb`, SBOMs, GitHub release |
| `dependency_check.yml` | ubuntu-latest | weekly | New OCI spec / crun releases; at most one open issue per dependency |
| `scorecards.yml`, `pages.yml`, `docs_mike.yml` | ubuntu-latest | various | OpenSSF Scorecards, documentation site |

## Self-hosted Proxmox runner

`proxmox_e2e.yml` needs a GitHub Actions runner with the `proxmox` label on a
Proxmox VE host, and on that host:

- **sudo without a password** for the runner user to run the checked-out
  `zig-out/bin/nexcage`, `pct` and `pvesm`, plus `mkdir`, `tar`, `tee`, `rm`
  and `find` for the OCI bundle test. nexcage needs root; the job stops with an
  explicit error when `sudo -n` is refused for nexcage.
- **`pct exec` working under the runner service**, for the `kill` test. On the
  current runner it fails with `Permission denied - Failed to rexec as memfd`:
  `lxc-attach` re-executes itself from a sealed memfd, and the service's
  sandbox refuses that. The likely cause is the hardening in
  `scripts/setup_secure_runner.sh` (`MemoryDenyWriteExecute=true`,
  `SystemCallFilter=@system-service`, `RestrictNamespaces=true`). Until
  `pct exec` works, the job skips signal delivery with a warning.
- **A container template** in storage `local` (`pveam download local …`), or
  `TPL` set in the runner environment.
- **The bridge** `vmbr50`, or `BRIDGE` set in the runner environment.
- **Container storage**: `local-lvm` if present, otherwise `local`; override
  with `ROOTFS`.
- **A workspace the runner user owns.** Container actions run as root and can
  leave root-owned files behind; a root-owned
  `/opt/github-runner/_work/nexcage/nexcage/.cache` makes checkout fail with
  `EACCES`. The job tries `sudo -n rm -rf` on it first; if that is not allowed,
  remove it once by hand. No workflow runs container actions on this runner
  any more.

The job names its containers `gh-e2e-<run id>-<attempt>` and destroys any
leftover `gh-e2e-*` container at the end, pass or fail.

## Releasing

1. Update `VERSION`, `CHANGELOG.md` and `docs/releases/NOTES_v<version>.md`.
2. Tag and push: `git tag -a v<version> -m "Release v<version>" && git push origin v<version>`.
3. `release.yml` checks that the tag matches `VERSION`, runs the tests, builds
   the binary and the `.deb`, installs the `.deb` on the runner as a smoke
   test, and publishes the release with the notes file as its body.
