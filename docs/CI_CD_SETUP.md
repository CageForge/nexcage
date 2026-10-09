# CI/CD

## Workflows

| Workflow | Runs on | Trigger | What it checks |
|---|---|---|---|
| `ci.yml` | ubuntu-24.04 | push/PR to `main` | Debug and ReleaseSafe builds, `zig build test`, smoke tests of exit codes; every command against fake Proxmox tools (`tests/sim/run.sh`). **The required check.** |
| `proxmox_e2e.yml` | self-hosted, `pve9` | push/PR to `main`/`develop` | Through the built binary on Proxmox VE: create → state → start → stop → delete, `pct config` against the config file, exit codes, `kill`, `run`, create from an OCI bundle |
| `crun_build.yml` | ubuntu-24.04 | push/PR to `main` | Docker build with `-Denable-backend-crun=true`; the `.deb` packs that binary and installs on Debian 13 (`scripts/ci/check_deb.sh`); the features document against libcrun's; `ps` against crun; a pod through containerd's CRI; the runtime-spec validation suite ([RUNTIME_SPEC_VALIDATION.md](RUNTIME_SPEC_VALIDATION.md)); critest, the CRI validation suite ([KUBERNETES_INTEGRATION.md](KUBERNETES_INTEGRATION.md#critest-what-kubernetes-checks-of-a-runtime)) |
| `k8s_e2e.yml` | ubuntu-24.04, then self-hosted `pve9` | tag `v*`, dispatch, PR touching `tests/k8s/` | `tests/k8s/pod_on_node.sh` with the `.deb` built from the commit and installed with apt: k3s, `runtimeClassName: nexcage`, the pod Ready, `kubectl logs`, `kubectl exec`, delete, all through nexcage |
| `memory_leak_check.yml` | ubuntu-22.04 | push/PR | Valgrind over basic commands |
| `security.yml` | ubuntu-latest | push/PR to `main`, weekly | Semgrep, Trivy, Gitleaks (non-blocking) |
| `version-check.yml` | ubuntu-22.04 | push/PR | `VERSION` is semver, matches `build.zig.zon` and appears in `nexcage --help` |
| `release.yml` | ubuntu-24.04 | tag `v*` | Tests; the one binary, with both backends; the `.deb` that packs it, installed on Debian 13; SBOMs; GitHub release |
| `dependency_check.yml` | ubuntu-latest | weekly | New OCI spec / crun releases; at most one open issue per dependency |
| `scorecards.yml`, `pages.yml`, `docs_mike.yml` | ubuntu-latest | various | OpenSSF Scorecards, documentation site |
| `buildagent.yml` | self-hosted, `buildagent`, `nexcage` | push/PR to `main`, daily | On Debian 13: Debug build, `zig build test`, `tests/sim/run.sh`, `make deb` and what the `.deb` carries |

## Self-hosted runners and forks

The jobs on self-hosted runners (`proxmox_e2e.yml`, `buildagent.yml`,
`k8s_e2e.yml`'s node job) skip a pull request from a fork: the job shows as
skipped and the GitHub-hosted checks run as usual. On the E2E node the runner
user has sudo for everything, so a fork's code there would run as root, and
GitHub's approval for first-time contributors stops applying once someone has
had a contribution merged. To run them on such code, push it to a branch in
this repository.

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
3. `release.yml` checks that the tag matches `VERSION` and runs the tests.
   It builds the one binary, with both backends, through the Dockerfile, and
   the `.deb` that packs it. It installs the `.deb` in a Debian 13 container
   and checks that the crun backend answers. It then publishes the release,
   with the notes file as its body.
