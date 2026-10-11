# CI/CD

## Workflows

| Workflow | Runs on | Trigger | What it checks |
|---|---|---|---|
| `ci.yml` | ubuntu-24.04 | push/PR to `main` | Debug and ReleaseSafe builds (the release build has to be a PIE), `zig build test`, smoke tests of exit codes; every command against fake Proxmox tools (`tests/sim/run.sh`); shellcheck at error level and the tests of `scripts/` (`tests/scripts/run.sh`); the Dockerfile's crun is the one `deps/crun` pins. **The required check.** |
| `proxmox_e2e.yml` | ubuntu-24.04, then self-hosted `pve9` | push/PR to `main`/`develop` | The release binary, built as `release.yml` builds it (both backends, ReleaseSafe, `-Dcpu=baseline`), on Proxmox VE: create → state → start → stop → delete, `pct config` against the config file, exit codes, `kill`, `run`, create from an OCI bundle |
| `crun_build.yml` | ubuntu-24.04 | push/PR to `main` | Docker build with `-Denable-backend-crun=true`; the `.deb` packs that binary and installs on Debian 13 (`scripts/ci/check_deb.sh`); the features document against libcrun's; `ps` against crun; a pod through containerd's CRI; the runtime-spec validation suite ([RUNTIME_SPEC_VALIDATION.md](RUNTIME_SPEC_VALIDATION.md)); critest, the CRI validation suite ([KUBERNETES_INTEGRATION.md](KUBERNETES_INTEGRATION.md#critest-what-kubernetes-checks-of-a-runtime)) |
| `k8s_e2e.yml` | ubuntu-24.04, then self-hosted `pve9` | tag `v*`, dispatch, PR touching `tests/k8s/` | `tests/k8s/pod_on_node.sh` with the `.deb` built from the commit and installed with apt: k3s, `runtimeClassName: nexcage`, the pod Ready, `kubectl logs`, `kubectl exec`, delete, all through nexcage |
| `memory_leak_check.yml` | ubuntu-22.04 | push/PR | Valgrind over basic commands; a memory error fails it |
| `security.yml` | ubuntu-24.04 | push/PR to `main`, weekly | zizmor over the workflows, Semgrep, Trivy, Gitleaks. Each fails on what it finds; Semgrep and Gitleaks first show they find a planted secret. Findings accepted on purpose, with reasons: `.trivyignore.yaml`, `.gitleaksignore`, `# nosemgrep: <rule>` comments, `.github/zizmor.yml` |
| `version-check.yml` | ubuntu-22.04 | push/PR | `VERSION` is semver, matches `build.zig.zon` and appears in `nexcage --help` |
| `release.yml` | ubuntu-24.04 | tag `v*` | Tests; the one binary, with both backends; the `.deb` that packs it, installed on Debian 13; SBOMs; GitHub release |
| `dependency_check.yml` | ubuntu-latest | weekly | New OCI spec / crun releases; at most one open issue per dependency |
| `scorecards.yml`, `pages.yml`, `docs_mike.yml` | ubuntu-latest | various | OpenSSF Scorecards, documentation site |
| `buildagent.yml` | self-hosted, `buildagent`, `nexcage` | push/PR to `main`, daily | On Debian 13: Debug build, `zig build test`, `tests/sim/run.sh`, `make deb` and what the `.deb` carries. **Not running**: no registered runner has these labels since 2026-10-04, so every run waits until the next one cancels it ([#339](https://github.com/CageForge/nexcage/issues/339)) |

## Self-hosted runners and forks

A pull request's workflows are the pull request's own: GitHub runs the
workflow files of its merge commit. The `if:` on the self-hosted jobs
(`proxmox_e2e.yml`, `k8s_e2e.yml`'s node job, `buildagent.yml`) keeps *these*
workflows from running a fork's code there, but a fork can delete that line,
or add `.github/workflows/anything.yml` with `runs-on: [self-hosted, pve9]`.
The `if:` is not a security boundary, and it is not what #362 needed.

On the E2E node the runner user has sudo for everything, so a job there runs
as root, and the runner is persistent, so what one job leaves behind is
there for every later job. What keeps a fork's code off it is outside this
repository's files:

1. **Approval of every outside contributor's run.** The repository's
   fork-PR approval policy is `all_external_contributors` (since
   2026-10-11); under the old `first_time_contributors` one merged pull
   request, a typo fix, was enough never to be asked again. Approving a run
   is approving that pull request's code on these machines: read its
   `.github/`, `scripts/`, `build.zig` and `Makefile` changes first.
2. **Runners only the named workflows can use.** Repository-level runners
   have no such restriction. The runners belong in an organization runner
   group with "Restrict to selected workflows", for example
   `CageForge/nexcage/.github/workflows/proxmox_e2e.yml@refs/heads/main` and
   `CageForge/nexcage/.github/workflows/k8s_e2e.yml@refs/tags/v*`, visible to
   this repository only. A workflow a pull request adds or edits does not
   match, so it cannot reach them. The cost: the E2E then runs on `main`, on
   tags and by dispatch from those refs, not on every pull request, and
   `scripts/dev.sh pve-e2e`, which dispatches it on a branch, works only for
   a ref the group lists.

Dependabot's pull requests come from a branch here, so the `if:` lets them
through; a bumped action runs on the node before anyone has read it, which is
one more reason every third-party action is pinned by commit.

### Still to do, by an administrator

The audit of 2026-10 found these, and they are settings and machines, not
files. `bash scripts/check_runner_exposure.sh`, with gh logged in as a
repository admin, reads the settings and fails until the first three are
done:

- **Deregister `proxmox-runner`**, the runner on the Proxmox VE host
  mgr.cp.if.ua (labels `proxmox`, `ubuntu`). No workflow uses it, it is
  online, and a pull request's own workflow could select it.
  `scripts/manage_github_runner.sh remove` does it (gh, as a repository
  admin), or `gh api -X DELETE repos/CageForge/nexcage/actions/runners/<id>`
  and then disable the service on the host.
- **Delete and rotate four stale secrets**: `PVE_HOST`, `PVE_PASSWORD`,
  `PROXMOX_SSH_KEY` and `GH_TOKEN`. No workflow references them, and any
  workflow pushed to a branch here receives repository secrets, printed
  encoded past the log masking. Deleting them does not undo a read: remove
  the key from root's `authorized_keys` on mgr.cp.if.ua, change that host's
  root password, and revoke the `GH_TOKEN` personal access token. A future
  job that needs credentials gets them from an environment with required
  reviewers, not from repository secrets.
- **Move `nexcage-e2e` (and the build agent, #339) into a workflow-restricted
  runner group**, as above, and remove the repository-level registration.
- Worth doing as well: register the E2E runner with `--ephemeral` and re-clone
  its VM per job, and keep the VM off the 192.168.3.0/24 LAN it shares with
  prox-home and the build agent.

## Self-hosted Proxmox runner

`proxmox_e2e.yml` needs a GitHub Actions runner with the `pve9` label on a
Proxmox VE host, and on that host:

- **The libraries the release binary links**: `libjson-c5`, `libseccomp2`,
  `libcap2` and `libsystemd0`, what the `.deb`'s `Depends` brings. The job
  tests the binary a release ships, built on a GitHub-hosted runner, and
  stops with an explicit error when one is missing.
- **sudo without a password** for the runner user to run the downloaded
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
   and checks that the crun backend answers; if either check fails, nothing
   is published. The binary and the `.deb` are attested where they are built
   (`actions/attest-build-provenance`; `gh attestation verify <file> -R
   CageForge/nexcage`), and the SBOMs are made in a job of their own that
   holds no signing token. It then publishes the release, with the notes file
   as its body. Signing with a project key is #318; what the SBOMs list is
   #333.
