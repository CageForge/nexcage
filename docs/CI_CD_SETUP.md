# CI/CD

## Workflows

| Workflow | Runs on | Trigger | What it checks |
|---|---|---|---|
| `ci.yml` | ubuntu-24.04 | push/PR to `main` | Debug and ReleaseSafe builds, `zig build test`, smoke tests of exit codes; every command against fake Proxmox tools (`tests/sim/run.sh`). **The required check.** |
| `proxmox_e2e.yml` | self-hosted, `pve9` | push/PR to `main`/`develop` | Through the built binary on Proxmox VE: create → state → start → stop → delete, `pct config` against the config file, exit codes, `kill`, `run`, create from an OCI bundle |
| `crun_build.yml` | ubuntu-24.04 | push/PR to `main` | Docker build with `-Denable-backend-crun=true` |
| `memory_leak_check.yml` | ubuntu-22.04 | push/PR | Valgrind over basic commands |
| `security.yml` | ubuntu-latest | push/PR to `main`, weekly | Semgrep, Trivy, Gitleaks (non-blocking) |
| `version-check.yml` | ubuntu-22.04 | push/PR | `VERSION` is semver, matches `build.zig.zon` and appears in `nexcage --help` |
| `release.yml` | ubuntu-24.04 | tag `v*` | Tests, ReleaseSafe binary, `-crun` binary, `.deb`, SBOMs, GitHub release |
| `dependency_check.yml` | ubuntu-latest | weekly | New OCI spec / crun releases; at most one open issue per dependency |
| `scorecards.yml`, `pages.yml`, `docs_mike.yml` | ubuntu-latest | various | OpenSSF Scorecards, documentation site |
| `buildagent.yml` | self-hosted, `buildagent`, `nexcage` | push/PR to `main`, daily | On Debian 13: Debug build, `zig build test`, `tests/sim/run.sh`, `make deb` and what the `.deb` carries |

## Self-hosted Proxmox runner

`proxmox_e2e.yml` needs a GitHub Actions runner with the `pve9` label on a
Proxmox VE host, and on that host:

- **sudo without a password** for the runner user to run the checked-out
  `zig-out/bin/nexcage`, `pct`, `pvesm`, `pvesh` and `pveversion`, plus
  `mkdir`, `tar`, `tee`, `rm`, `find`, `cat`, `grep` and `kill` for the OCI
  bundle, cgroup and cleanup checks. nexcage needs root; the job stops with an
  explicit error when `sudo -n` is refused for nexcage.
- **`pct exec` working under the runner service**, for the `exec`, pause and
  snapshot checks; `kill` signals the container's init from the host and does
  not need it. Without `pct exec` the job fails. Under the hardened service
  `scripts/setup_secure_runner.sh` installs, `pct exec` failed with
  `Permission denied - Failed to rexec as memfd`: `lxc-attach` re-executes
  itself from a sealed memfd, and the service's sandbox refuses that. The
  likely cause is its hardening (`MemoryDenyWriteExecute=true`,
  `SystemCallFilter=@system-service`, `RestrictNamespaces=true`); the E2E
  node's runner service is installed by `scripts/register_e2e_runner.sh` with
  `svc.sh` instead.
- **A container template** in storage `local` (`pveam download local …`), or
  `TPL` set in the runner environment.
- **The bridge** `vmbr50`, or `BRIDGE` set in the runner environment.
- **Container storage**: `local-lvm` if present, otherwise `local`; override
  with `ROOTFS`.
- **A storage that can snapshot** for the snapshot checks: the first lvm-thin
  or ZFS storage in `pvesm status`, or `SNAPSTORE`. `local` cannot snapshot a
  raw volume, so on a node without one the checks are skipped with a warning;
  `03-prepare-runner-host.sh` makes a ZFS pool on a file and adds it as the
  storage `e2e-zfs` for them.
- **A workspace the runner user owns.** Container actions run as root and can
  leave root-owned files behind; a root-owned `.cache` in the job's workspace
  (`$GITHUB_WORKSPACE/.cache`) makes checkout fail with `EACCES`. The job tries
  `sudo -n rm -rf` on it first; if that is not allowed,
  remove it once by hand. No workflow runs container actions on this runner
  any more.

The job names its containers `gh-e2e-<run id>-<attempt>` and destroys any
leftover `gh-e2e-*` container at the end, pass or fail.

## Releasing

1. Update `VERSION`, `CHANGELOG.md` and `docs/releases/NOTES_v<version>.md`.
2. Tag and push: `git tag -a v<version> -m "Release v<version>" && git push origin v<version>`.
3. `release.yml` checks that the tag matches `VERSION`, runs the tests, builds
   the binary, the `-crun` binary and the `.deb`, installs the `.deb` on the
   runner as a smoke test, and publishes the release with the notes file as its
   body.
