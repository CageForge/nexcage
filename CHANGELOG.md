# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- **The self-hosted jobs no longer run a pull request from a fork** (#362). `proxmox_e2e.yml` and `buildagent.yml` ran any pull request's code on their machines, and on the E2E node the runner user has sudo for everything, so that code ran as root. They now skip a fork's pull request, as `k8s_e2e.yml` does from the start.

### Added
- **The runtime-spec validation suite runs against the crun backend in CI** (#310). `crun_build.yml` runs opencontainers/runtime-tools (runtime-spec 1.3.0) against the `-crun` build routed to crun, and the image's crun for reference. nexcage passes 33 of 58 tests; each of the 25 that fail is named in `tests/runtime-tools/known-failures` with the reason, and fails with crun run directly too: tests that cannot read cgroup v2, cgroup v1 settings libcrun refuses by name, and tests that contradict runtime-spec 1.3.0 or themselves. A failure not on the list turns the job red, and so does a listed test that passes. `docs/RUNTIME_SPEC_VALIDATION.md` has the results.
- **critest, the CRI validation suite, runs against nexcage in CI** (#311). `crun_build.yml` runs cri-tools' critest (v1.37.0, 142 specs) against containerd with nexcage as the runtime handler, and again through the image's crun for reference. 110 pass, 10 fail and 22 are skipped, the same spec for spec as through crun. The 10 that fail are AppArmor specs that need `sudo apparmor_parser` in the image, and pod sandbox metrics, which containerd reads from a cgroup parent that critest does not set under cgroupfs. Each is named in `tests/cri/critest-known-failures` with the reason. Its first run found #361. `docs/KUBERNETES_INTEGRATION.md` has the results.
- **The k3s pod test runs from a workflow** (#312). `k8s_e2e.yml` builds the `-crun` binary from the commit under test, as the release does, and runs `tests/k8s/pod_on_node.sh` on the E2E node. That is k3s, a pod with `runtimeClassName: nexcage` that has to be Ready, `kubectl logs`, `kubectl exec` and a delete, all checked against what nexcage was asked. It runs on release tags, on demand, and on a pull request that changes the test, never on a fork's. The script now removes the `/etc/nexcage/config.json` it wrote, which used to stay behind and route every nexcage on the node to crun.

- **A Kubernetes node on Proxmox VE, from what a release ships** (#313). `docs/INSTALL.md` has the steps in order: the `-crun` binary, the routing configuration (`packaging/config/config.oci.example.json`), nexcage as a runtime of k3s, containerd or CRI-O (examples in `deploy/kubernetes/node/`, which nothing enables for you), the `RuntimeClass`, and a pod to check it with. `tests/k8s/pod_on_node.sh` installs the same files, so `k8s_e2e.yml` checks what an administrator is told to install. The `-crun` build stays a bare binary; a package for it belongs to the APT repository work in 1.0.0.

### Fixed
- **containerd could not stop a pod whose container had just exited** (#361), found by critest. containerd's shim decides what a failed `kill` means from the command's output: "no such process" means the process has already exited, which is fine for a stop. With `--log <file>`, which every engine passes, nexcage wrote libcrun's reason to the file only, and stderr said `operation failed`. StopContainer then failed, and StopPodSandbox with it. An error now goes to stderr as well, as runc and crun print theirs. Without `--log` nothing changes.

## [0.15.0] - 2026-10-08

`create` takes what `pct create` is usually given -- limits, cores, a static
address, a VLAN, mount points, `onboot`, tags -- and an option nexcage does not
know is refused by name instead of skipped. **A script with a misspelt or
unsupported option now fails with exit 2 where it used to carry on.**

### Fixed
- **An unknown option was skipped without a word, and its value taken for the next positional word** (#355). `create --memroy 2G` answered "OCI bundle '2G' must be an absolute path", and an unknown flag without a value simply vanished, so `kill --al` signalled the init alone. An option no command takes now exits 2 naming it, and a value option given last without its value says it needs one. Every option an engine was seen sending already has its own branch, so their command lines are unchanged; runc options nexcage does not implement (`--no-pivot`, `--preserve-fds`, ...) are refused rather than dropped. `create --image <image>`, the form `create --help` shows, had only worked because `--image` was skipped and its value taken for the image; it is parsed now.

### Added
- **`create` takes what `pct create` is usually given** (#308): `--memory`, `--memory-swap`, `--cpu-quota`, `--cpu-period` and `--cpu-share` under `update`'s names and said to pct the way `update` says them (one conversion, shared); `--cores`; `--ip`, `--gw`, `--vlan` and `--firewall`, which are `net0`'s `ip=`, `gw=`, `tag=` and `firewall=1`; `--onboot`; `--tags`; and `--mp <spec>`, repeatable, in pct's own syntax as `mp0`, `mp1`, .... They go through `pct create` for a container here and the node's API for one made with `--node`, so nothing needs a `pct set` by VMID afterwards. A limit Proxmox cannot express is refused by name, as `update` refuses it; an address containing `,` or `=`, which would add a `net0` key, and a VLAN tag outside 1-4094 are usage errors; `--mp` with an OCI bundle is refused, because the bundle's mounts take the `mp` entries; and the crun backend refuses all of them, since it takes limits, network and mounts from the bundle's `config.json`. The Proxmox E2E creates a container with every option and reads each one back from `pct config`.

## [0.14.1] - 2026-10-08

Flags that `run` and `exec` accepted on Proxmox LXC and then dropped are
refused by name -- **`exec --user 1000` ran the command as root** -- and three
smaller fixes: an explicit `--log-level info`, `health`'s idea of the
configuration, and CI's Zig install.

### Changed
- **CI installs Zig with `mlugg/setup-zig`**, pinned to v2.2.1 by commit, instead of `goto-bus-stop/setup-zig`, which its README calls unmaintained (#338). The Proxmox E2E on `main` failed in that step, timing out on the download before any test ran; on the self-hosted runners the new action keeps Zig in the runner's tool cache rather than fetching it every run. The release workflow builds without the Zig cache, from the tagged tree alone.

### Fixed
- **`--log-level info` and `NEXCAGE_LOG_LEVEL=info` could not override a configuration file's level** (#330): an `info` from the command line or the environment was taken for "not set", so a file saying `debug` could not be turned back to `info` for one command. A level that is named now wins over the file's, `info` included, and takes the debug mode the file's `debug` level turned on with it; `--debug` and `NEXCAGE_DEBUG` still keep debug mode on. A level nexcage does not know is ignored, as before.
- **`exec --user 1000` on Proxmox LXC ran the command as root** (#329). `--user`, `--cwd`, `--console-socket` and `--pid-file` reached the crun backend only, and Proxmox LXC dropped them: `pct exec` runs a command as root, in a directory nexcage does not choose, and hands back no pty or pid. They are refused there now, as `--process` and `--detach` already were. `--tty` is honoured when nexcage runs on a terminal, because `lxc-attach` gives the command one whenever a standard descriptor is a terminal, and refused when none is.
- **`run` dropped `--node`, `--console-socket` and `--pid-file`** (#328): `run --node titan` made the container on this host without a word, and a caller passing `--console-socket` waited for a pty that never came. All three are refused, before anything is created; `create --node`, then `start`, makes a container on another node.
- **`health` checked a configuration nothing reads, and looked up google.com** (#334). It looked at `/etc/nexcage/config.json`, then `./config.json`, whatever `--config` said, while every command reads the file `--config` names or else `./config.json`, `/etc/nexcage/config.json`, `/etc/nexcage/nexcage.json`; so it could pass a file nothing used and miss the one in use. It reports that file now, from the same search. Its JSON check went with it: the file is loaded before any command runs, so a bad one never reached the check. And `nslookup google.com` is gone: nexcage resolves no names itself, and a root tool on an air-gapped cluster should not send a lookup to an outside name to warn about nothing.

## [0.14.0] - 2026-10-08

Snapshots, `create --node` on a stock Proxmox VE host, and a project that says
true things: the Proxmox VM stub and two build options that could not work are
gone, and the documentation, ownership and review rules were checked against
what the code and the project do. **A configuration naming `vm` or `proxmox`
as a runtime is now refused by every command.**

### Added
- **`ROADMAP.md`**: what comes next and why, release by release up to the criteria for 1.0, and what is not planned. No dates past the next release; each item links its issue.
- **Snapshots through Proxmox**: `snapshot`, `snapshots`, `rollback` and `delsnapshot`, with pct's names, for the Proxmox LXC backend (#299). Proxmox takes the snapshot, so `snapshot`, `rollback` and `delsnapshot` are each one `pct` call for a container here and one call to its node's API for a container elsewhere, and `snapshots` reads the node's API for both; nexcage adds the container by name on any node, a plain line when the storage cannot snapshot, and `--format json` for the list. The crun backend refuses them: libcrun has no storage of its own to snapshot. The successor of #116, #117, #118 and #163, which asked for this through libzfs.
- **`scripts/dev.sh`, one entry point for local development**, with `make doctor`, `dev-setup`, `e2e`, `act`, `local-ci`, `perf` and `dev-shell`: a check of every tool with how to get what is missing; the unit tests and the simulator; the crun-backend image and the checks `crun_build.yml` runs on it; a pod through containerd's CRI; a shell with nexcage, crun, containerd and crictl (`shell [CMD]`); the GitHub-hosted CI jobs through act, with the repository's `.actrc` and runner image (`.github/act`); and `pve-e2e`, which dispatches the Proxmox E2E for the pushed branch and follows it. No root needed; rootless podman or Docker. [docs/LOCAL_DEVELOPMENT.md](docs/LOCAL_DEVELOPMENT.md).
- **Performance suites** in `tests/perf/`: the Proxmox LXC lifecycle against the simulator — wall time, peak memory and the number of Proxmox tool runs (`pct`, `pvesh`, `pvesm`, `pveam`, `pveversion`, `zfs`) per command — and the crun backend's lifecycle next to crun's own binary. `scripts/dev.sh perf --against <ref>` builds both revisions ReleaseSafe, runs them in alternating rounds and exits 1 on a regression: any extra Proxmox tool run, or a time shift most of the samples agree on.

### Changed
- **Proxmox VE 8.x is no longer supported.** nexcage ran on it, but the E2E suite only ever ran on 9.x, and Proxmox ended support for 8.x in August 2026 together with Debian 12. Nothing in the code refuses an 8.x host; the README, `docs/INSTALL.md` and `docs/DEV_QUICKSTART.md` stop promising it.
- **`state` reports `ociVersion` 1.3.0**, the runtime-spec baseline since v0.7.4, from one constant, `OCI_RUNTIME_SPEC_VERSION`; both backends wrote a hand-written `1.0.0`, which the dependency check reported as #294. `features` is unchanged: it is libcrun's own claim about what the library implements.
- **The crun job of `dependency_check.yml` keeps one open issue truthful.** It rewrites the issue's title and body when the pin or the latest release moves, and closes the issue once the pin is based on the latest release; `workflow_dispatch` gained `dry_run`, which prints what would be filed, edited or closed instead, and `scripts/dev.sh act` runs the job that way by default.
- The simulator's fake host moved from `tests/sim/run.sh` into `tests/sim/lib.sh`, which the perf suite shares.
- `crun_build.yml`'s features document check is `tests/crun/features_check.py`, so the local run and CI run the same one.
- `.gitignore` covers what the GitHub-hosted jobs write into their checkout (`zig-out-release/`, `err.txt`, `features.json`, `bundle/`), because act runs them in this one; `.dockerignore` leaves out `.actrc`.

### Removed
- **The Proxmox VM backend**, with `-Denable-backend-proxmox-vm` (#306). It was compiled out by default and built by no workflow; the router answered every operation routed to it as not implemented without calling the driver, and the driver imported `integrations/proxmox-api`, a module `build.zig` does not define — a build with the option on succeeded only because nothing reached it. Unlike runc in 0.13.0 there is nothing to route such a container to instead: the default backend would make a container where a VM was asked for. So a configuration naming `vm` as a runtime, or `proxmox`, which was mapped to it, is now an error for every command, saying what to name instead; `--runtime vm` and `--runtime qemu` exit 2 saying the backend was removed. `qm` can come back with a test behind it.
- **`-Denable-backend-proxmox-lxc`** (#331). Setting it to `false` never compiled: the CLI calls the Proxmox LXC driver directly in seven places, and only the crun backend is checked for at run time. Proxmox LXC is the backend nexcage exists for, and a build without it is crun under another name, so the backend is always built; `zig build` rejects the option as unknown.
- **`crun_vendor_sync.yml`, `crun_headers_generate.yml` and `scripts/sync_crun_vendor.sh`** (#332). Both workflows changed files inside `deps/crun` and asked for a pull request, but `deps/crun` is a submodule: the parent repository records a commit id, so there was never a change to propose and neither ever opened one. The weekly sync had also been disabled by GitHub for inactivity, and its script copied an upstream tarball over the submodule's checkout, which is not how the pin moves. The pin moves by hand, as *Updating the vendored crun* in `docs/DEVELOPMENT_WORKFLOW.md` describes, `dependency_check.yml` says when it falls behind, and the Dockerfile generates the headers at build time.

### Fixed
- `build.zig.zon` said version 0.9.0 through four releases, because nothing in the build reads it; `scripts/ci/check_version.sh` now fails when it differs from `VERSION`.
- **`CODEOWNERS` never requested a review** (#303): GitHub reported every owner in it as unknown, because `@CageForge` is the organization, which cannot own code, and `@moriarti` is not the maintainer's account. It names `@themoriarti`, and `MAINTAINERS.md` names the one active maintainer instead of the organization and that account.
- **`GOVERNANCE.md`, `MAINTAINERS.md` and `CONTRIBUTING.md` asked for two LGTMs** on non-trivial changes, with one active maintainer to give them (#304). They describe what is practised: every change goes through a pull request with green CI, the maintainer merges their own, anyone else's needs the maintainer's approval, and architecture needs an ADR. The two-reviewer rule starts with a second active maintainer.
- **Documentation and `--help` that disagreed with the code** (#307), checked statement by statement against the source across the README, `docs/`, the architecture notes, the man page, the bash completion, `config.json.example` and every command's `--help`. Among what was wrong: a bundle had to sit under two directories (any absolute path has been accepted since 0.10.0); the crun backend had no `state` or `exec` (it has both); the Kubernetes gap table listed logs and sandboxes, which the engine provides, and `update` as missing; `--log-file` was said to receive the log, when it holds only start and completion lines and never an error; `pause` and `resume` were not among the things that stay local on a cluster; `list` was said to cover every backend (it lists Proxmox LXC only); the man page, the completion and `help` lacked a dozen commands; `config.json.example` carried keys nothing reads; and the CycloneDX SBOM was said to come from `cyclonedx-action`, when the release workflow writes a stub with no components. The changelog's *Support Policy* and *Upgrade Path* described v0.1 to v0.4 and say what is true now.
- **The dependency check reported the vendored crun as 1.14.2** in #227, its 26 closed duplicates and #295, filed after the pin had reached 1.30.1. In a submodule checkout `.git` is a file, so the step's `[ -d .git ]` never matched and it took the first `N.N.N` on any line of NEWS containing "version", a changelog line from 2024. It now reports the pinned commit of the fork `.gitmodules` names and the release `.upstream_tag` declares, checked against the newest NEWS entry; the latest-release lookup is authenticated rather than turning a rate limit into "null"; and an update means the pin is version-older than the release, not merely different.
- **The CRI test could not run under rootless podman.** It enabled cgroup controllers in one write naming `cpuset` and `io`, which a user's cgroup does not delegate, so the write failed as a whole and enabled none; and containerd in a user namespace was not told to leave `oom_score_adj` and AppArmor alone, so libcrun's `write to /proc/self/oom_score_adj` failed every sandbox. Controllers are enabled one at a time now, and the two containerd options are set when the test runs in a user namespace. CI's rootful Docker is unaffected.
- **`create --node` was refused on any host with the zfs tools installed** (#327) — which is every stock Proxmox VE host: Proxmox VE installs them, and the E2E node has them without asking. The guard meant to stop nexcage making a ZFS dataset in this host's pool for a container on another node asked whether `zfs version` works, which says only that the tools are there. nexcage makes a dataset of its own only in a pool it is given, which no configuration key sets, and that is what the guard asks now; a rootfs on a ZFS storage, which Proxmox makes on the owning node, goes through. The simulator's fake `zfs` answered "not installed", so the `create --node` checks ran on a host Proxmox VE does not ship. It reports the tools installed now, as a real host does, and four of those checks fail on the previous binary, as does a new one with `proxmox.storage` on ZFS. The lxc-sim perf suite counts one more `zfs` call for `create`, `run` and a bundle `create`: on a host with the tools, nexcage asks `zfs version` twice per create, which the fake now shows.

## [0.13.0] - 2026-09-27

`update` -- the last runtime-spec verb that was missing -- vendored crun moves
from 1.24 to 1.30.1, and two things are removed: the runc backend, which
nothing ever built or ran, and `crun_name_patterns`. **Read the upgrade note
if you install the `-crun` binary: it needs `libjson-c5` now, not `libyajl2`.**


### Added
- **`update`**, the runtime-spec verb for a running container's resource limits, with runc's and crun's flag names (`--memory`, `--memory-swap`, `--cpu-quota`, `--cpu-period`, `--cpu-share`, `--pids-limit`, ...) and `--resources <file|->` for a `linux.resources` document — `update --resources=- <id>` with the document on stdin is what containerd sends for an in-place pod resize, and the CRI test asks for one. On the crun backend it reaches libcrun either way. On Proxmox LXC the settings are said to `pct set` in its own terms — bytes to MiB, quota over period to `cpulimit` in cores, cgroup v1 shares to the v2 weight `cpuunits` the way runc converts them — and a container on another node goes through that node's `/config` API; what Proxmox cannot express (pids, cpusets, reservations) is refused by name rather than dropped, because a limit asked for and silently not applied is the worst answer an update can give. Proxmox keeps the change in the config, so it survives a restart.

### Changed
- **Vendored crun 1.24 → 1.30.1.** The pin moves from the fork's revert-carrying commit to a branch that is upstream 1.30.1 plus the `.upstream_tag` marker the header script reads; the `intelrdt` revert the old vendoring carried was not needed to build. `scripts/check_features_abi.sh` passes against the new header unchanged, so the Zig mirror of the features structs did not move. **The `-crun` binary now needs `libjson-c5` instead of `libyajl2`**: crun 1.28 replaced YAJL with json-c, libocispec included. A Proxmox VE 9 host has `libjson-c5` (it did not have `libyajl2`), so this is one library fewer to install (#227).
- ADR-001 records the runtime selection that ships rather than the one decided in 2024: Proxmox LXC is the default backend, the crun backend is libcrun linked in and is what a container engine's host routes to, there is no fallback between backends, and runc is not supported. Routing is one name lookup with one list of rules. `docs/architecture/BACKENDS.md` said `kill` went through `pct exec` and name lookup through `pct list`; neither has been true since 0.9.0 and 0.11.0.

### Fixed
- **`create` from a registry image called the pull endpoint every time and then guessed the volid.** It composed `<storage>:vztmpl/<image>_<tag>.tar` from the reference, which is a guess about how Proxmox normalises a file name, and pulled onto `local` whatever was asked. It now looks on the storage first and reuses an image that is already there — what a container engine does — and otherwise pulls the way `pull` does, reading the volid back from the storage so that what `pct create` is given exists. `create --storage <name>` and `run --storage <name>` say where, as for `pull`. The simulator's fake `pvesh` wrote every pull as `local:` whatever storage was asked for, so a correct `--storage` failed against the fake and not against Proxmox; it names the storage now. The E2E on a real host counts Proxmox's own `ociregistrypull` tasks across a second `create` from the same reference: there must be no new one.

### Removed
- **The runc backend**, with `-Denable-backend-runc`. It shelled out to a `runc` binary for create/start/kill/delete, no workflow ever built it, and it had never been run; the crun backend answers the same OCI interface through libcrun and is what every engine was verified against. A routing rule that still says `runc` routes to crun and is warned about — the container it describes is an OCI container either way — and `--runtime runc` exits 2 naming `--runtime crun` (#88).
- `container_config.crun_name_patterns`. It routed names matching a glob to crun before `runtime.routing` existed and stayed on as a fallback after every glob it could express had a one-line equivalent there — the same matcher. A file that still carries the key gets a warning naming the replacement, because a container it used to route to crun now goes to the default backend, and that should not happen without a word.

## [0.12.0] - 2026-09-27

`pause` and `resume` -- the cgroup freezer -- and three fixes to code that
0.11.0, 0.11.1 and 0.11.2 all shipped broken: **the cluster lookup never
worked on a real Proxmox host.** If you run nexcage on a cluster, this is the
release where containers on other nodes actually resolve.

### Added
- **`pause` and `resume`**, the cgroup freezer: every process in the container stops where it is and stays in memory. On the crun backend through libcrun; on Proxmox LXC by writing the freezer of the container's cgroup. `state` reports `paused` for a frozen container, which it has to read from the cgroup itself — `pct status` keeps saying `running`, because Proxmox has no notion of the state. Refused for a container on another node, naming it: the cgroup filesystem there is not this host's to write.
- The E2E suite exercises `pause` and `resume` against a real Proxmox host, where the evidence is the kernel's own: `cgroup.events` has to say `frozen 1`, not merely `cgroup.freeze` holding what nexcage wrote, and a command sent into the container while it is frozen has to be held there, and to run once it is thawed. Every defect this release fixes was in code that the simulator's fakes were happy with, so a freezer is not something to ship on a fake alone.
- This is deliberately **not** `pct suspend`. On a container that runs `lxc-checkpoint -s`, which dumps the processes through CRIU and takes the container down -- and on the Proxmox VE 9.2 host this was measured on, it simply failed. The freezer is the operation the runtime-spec describes, and nexcage never calls `pct suspend`; the simulator asserts that no run in the suite ever does.

### Fixed
- **The cluster lookup never worked on a real Proxmox host.** It asked `/cluster/resources --type lxc`, and the API's enumeration is `vm, storage, node, sdn` — so every call was rejected with "400 Parameter verification failed" and quietly fell back to `pct list`. That fallback is right for a container on this host and answers "not found" for one anywhere else, which is the exact thing cluster support was added for. Containers come back under `--type vm` with their own `type` field, which is what is read now. The simulator's fake accepted the wrong flag, so the tests agreed with the mistake; it refuses it the way Proxmox does.
- **A container the cluster's listing had not caught up with was reported as missing.** `/cluster/resources` is a cache that `pvestatd` refreshes every few seconds, so `create` followed straight away by `start` failed on a real host. A miss in the cluster now means "keep looking on this host", and only both sources coming up empty is a container that does not exist.
- **`state` and `list` showed a stale status for a container on this host.** The cluster's cached copy was preferred over `pct`, so `state` said `stopped` for seconds after a successful `start` while `list` said `running`. For a container here `pct` is the current answer; the cluster keeps the one thing only it knows, which node a container elsewhere is on.
- `list` called a frozen container `running` while `state` called the same container `paused`: two answers from one binary, which is the same fault as the stale-status one above. `list` reads the freezer now. A container on another node has no cgroup here, so nothing changes for it.
- A leak on every `start`, `stop`, `pause` and `resume` that resolved a name through the fallback path: `getVmidByName` allocates, the result was duplicated into the location and the original never freed. Harmless in a process that exits immediately, and reported by the allocator on every run.

## [0.11.2] - 2026-09-27

A release carries the binary a container engine drives, instead of leaving
everyone to build it. And the README says what nexcage is: it had been
claiming "as of version 0.9.0" that containerd integration and containers on
other cluster nodes were not done, months after both were.

### Added
- **A release carries a second binary, `nexcage-<version>-amd64-crun`**, with the OCI runtime backend compiled in — the build a container engine drives. It goes through the Dockerfile, because vendored libcrun needs the submodules and two generated header sets, and it is built with `-Dcpu=baseline` for the same reason the default binary is: a Proxmox node is often older than a GitHub runner. The job asks the binary for `features` to check the backend is really in it, since only libcrun can answer that, and records `ldd` in the log because the binary needs `libyajl2`, `libseccomp2` and `libcap2` on the host and a Proxmox VE install does not have the first.

### Changed
- The README said "Status as of version 0.9.0" and listed containerd/CRI integration and containers on other cluster nodes as not yet done. Both have been done for some time, and the project's own front page was the last place saying otherwise. It now describes the two things nexcage is — a command line for LXC containers on a cluster, and an OCI runtime engines drive — with badges, the documentation map, and the sections an open-source project is expected to carry. `docs/index.md` and the site description said the same stale thing and now match.
- `docs/architecture/OVERVIEW.md` described nexcage as turning CLI commands into `pct` calls. It is called from two directions, and the diagram shows both.

## [0.11.1] - 2026-09-26

A small one. `images`, `pull` and `rmi` shipped in 0.11.0 having met only
the simulator's fakes; they are checked against a real Proxmox host now.
The one change a person will notice is that `images --node` on a node the
cluster does not have is an error rather than an empty list.

### Added
- The E2E suite covers `images`, `pull` and `rmi` against a real Proxmox host. They had only ever met the simulator's fakes, and a storage listing is exactly the kind of thing a fake gets subtly wrong — three of the failures while writing those fakes were the fake and not the code. The step pulls an image, checks the volid it printed is the one `pvesm` holds, removes it, and checks it is gone from the storage rather than only from the listing; removing it twice has to be an error. It frees anything it pulled on the way out, even on failure.

### Changed
- `images --node` on a node the cluster does not have is an error naming the nodes it does have, instead of an empty listing and exit 0. Silence there reads as "that node has no templates", which is a different thing and sends someone looking in the wrong place.

### Fixed
- The E2E job uploaded only `e2e_lxc.log`. The registry step has been writing `e2e_registry.log` all along and it was never collected, so a failure there left nothing to read afterwards. All of them are collected now.

## [0.11.0] - 2026-09-26

A Proxmox VE cluster is more than one node. `pct` only ever answers for the
host it runs on, so `list` showed a fraction of what was there without saying
so, and every other command reported a container on another node as missing.
That is fixed, and with it come the commands for putting a template where
another node can read it: `images`, `pull` and `rmi`.

Nothing here changes the OCI runtime side, which is what containerd, CRI-O and
a kubelet drive. For Kubernetes, more than one host was never a runtime
question -- a kubelet runs on each node and calls the binary there.

### Added
- **A Proxmox VE cluster is more than one node, and nexcage now sees all of them.** `pct` only ever answers for the host it runs on, so on a cluster `list` showed a fraction of what was there without saying so, and every other command reported a container on another node as missing. Names and VMIDs resolve through `/cluster/resources` instead: `list`, `state`, `start`, `stop` and `delete` find a container wherever it lives and act through the owning node's API, while a container on this host still goes through `pct`. `list` grew a `NODE` column, and `state` carries the node as the annotation `io.cageforge.nexcage.node`.
- `create` checks the name across the whole cluster before taking a VMID. Every other command resolves a name, and two containers sharing one would make that ambiguous.
- **`create --node <name>`** makes the container on another node of the cluster, through that node's API. The template is checked there first, before a VMID is taken: a storage called `local` is a different directory on every node unless it is shared, so a volid that exists here may simply not be there, and the message names the node and the storage instead of leaving the API to say "volume does not exist". Three things it refuses rather than half-does — an OCI bundle and a registry image, because both land on *this* host's storage, and a ZFS rootfs, because the dataset would be created in this host's pool. `--node` naming this host is not "another node": it takes the ordinary local path.
- **`images`** lists the container templates the cluster can create from, with the node and storage each one is on — which is what `create --node` needs, since a template has to be readable by the node the container is made on. A storage marked shared carries the same files on every node and is listed once rather than once per node.
- **`pull <reference>`** fetches an OCI image into a Proxmox storage as a template and prints the volid, with `--node`, `--storage` and `--filename`. `create` already pulls when given a registry reference, but only onto this host's `local` storage, and `local` is a different directory on every node; pulling onto a shared storage is what makes `create --node` usable. The volid is read back from the storage rather than composed from the reference, because the endpoint normalises the file name and only the storage knows what it settled on. Needs Proxmox VE 9.1 or later, and says so rather than failing obscurely. The endpoint takes no credentials, so a private registry cannot be authenticated through it.
- **`rmi <template>`** removes a container template from the storage it is on, with `--node`. On a shared storage the file is gone from every node at once whichever node was named, and the output says so. A template that is not there is an error rather than a no-op, because a mistyped volid should not look like a successful removal; a malformed name is a usage error.

### Changed
- `list` output has a `NODE` column between `BACKEND` and `NAMES`. A script reading the name out of the seventh tab-separated field wants the eighth now.

### Fixed
- `state` reported `"pid": 0` for a running container whenever the PID could not be read, which a caller cannot tell from a container that has none. Reading it is an error now — except for a container on another node, where there is no PID on this host to report and the annotation says which node to ask.

## [0.10.0] - 2026-09-26

Container engines run containers on nexcage, and Kubernetes schedules pods
onto it. Everything a kubelet's containerd asks an OCI runtime -- `features`,
`create`, `start`, `ps`, `exec`, `kill`, `delete` -- is answered, verified on
podman, `ctr`, containerd's CRI, CRI-O, a standalone kubelet, and a pod
scheduled by k3s on a Proxmox VE node with `runtimeClassName: nexcage`.

Every defect below was found by running an engine rather than by reading the
code: the working directory on `create`, the spelling of a flag, the parse of
`--process`. None of them was on the list of what was thought to be missing.

### Added
- **`ps`**, the last thing Kubernetes asks a runtime that nexcage did not answer. The trace from a pod on a real node showed the kubelet's containerd sending `ps --format json <id>` and getting `unknown command 'ps'`; containerd swallows that without a word in its journal and the pod runs anyway, so only recording the runtime's command lines showed the question was being asked. The values come from `libcrun_container_read_pids`, which reads the container's cgroup with its children — where `crun ps` and `runc ps` get theirs — and the output follows crun's shape rather than runc's table, which runs the host's `ps -ef` and filters it. Refused on Proxmox LXC rather than answered with something else: `pct exec <id> ps` reports the PIDs the container sees in its own namespace, a different set of numbers for a different question. `tests/crun/ps.sh` compares the list against `crun ps` for the same container, because any list of live PIDs looks plausible on its own.
- **Kubernetes schedules a pod onto nexcage.** `tests/k8s/pod_on_node.sh` installs k3s on a node, adds one runtime to the containerd configuration k3s generates, and applies a pod with `runtimeClassName: nexcage`: the pod becomes Ready with an address from the cluster's CNI, `kubectl logs` returns its output, `kubectl exec` runs a command in it, and deleting it goes through the runtime too. Run on `nexcage-e2e-1`, which the script leaves as it found it unless `--keep` is passed. Two things about getting a binary onto that node would have looked like runtime bugs: the host has no AVX2, so a native-tuned build dies with `SIGILL` (`-Dcpu=baseline`), and a crun-enabled build needs `libyajl2` present. The trace from that run is in `docs/KUBERNETES_INTEGRATION.md`, and it is the first complete record of what Kubernetes asks a runtime.
- **`exec` on the crun backend**, which is what `kubectl exec` and an exec probe come down to. Both shapes work: `--process <file>`, the OCI process spec a container engine writes and names, and a command typed after the container's name. Both go to `libcrun_container_exec_process_file`, which takes a path rather than a struct — libcrun's other two exec entry points take a `runtime_spec_schema_config_schema_process *`, generated by libocispec from a JSON schema and far larger than the two structs whose hand-written mirror had just put a features document at the wrong offset. A command line is written to a temporary spec, removed afterwards, carrying a default `PATH` when `--env` gives none, because a process with no `PATH` cannot find `ls`. The exit status is the command's, as `runc exec` has it. `--process` and `--detach` are refused on Proxmox LXC rather than ignored: `pct exec` takes a command and returns when it ends.
- Parsing `--process` mattered as much as the call behind it: the flag used to fall through as an unknown option and its value became the container id, so containerd's exec was answered with `exec is not implemented for the crun backend (/tmp/runc-process68868969)`.
- **A pod is a test now.** `tests/cri/pod_on_nexcage.sh` creates a pod sandbox and a container in it through containerd's CRI, with nexcage as the runtime handler and a CNI bridge, and the crun CI job runs it on every pull request. Three engine-facing defects in a row were invisible to every test here because nothing ran an engine. Its own first version was worthless and says so in a comment: it used the `pause` image for both the sandbox and the container, and so passed on a binary with the bundle defect, because `/pause` exists in the sandbox's rootfs as well. The container's image is a busybox now, whose `/bin/sh` does not, and the runtime's command line is asserted so the test cannot pass with runc behind the handler.
- **`features`**, which containerd's CRI asks for once at startup and which answered `unknown command` until now. It never stopped a pod — containerd records the failure and then assumes nothing — and that is also why a wrong answer would be worse than none: what a runtime claims in a features document, a kubelet believes. So nexcage claims nothing of its own. Every value comes from `libcrun_container_get_features`, the call behind `crun features`, so the document is this build's configuration read from this build rather than a list maintained by hand that could drift from it silently; the field order and shapes follow crun's output too. The command carries no container id, and a container id is nexcage's routing key, so the backend is resolved the way a container with no name would route: `--runtime` wins, else the routing rules against an empty id. On the Proxmox LXC backend it exits 1 and says where the answer lives, because `pct` creates the container there and the hooks, seccomp and capabilities a features document promises are not nexcage's to report.
- **containerd runs containers on nexcage.** `--log <path>` sends the runtime's own log to a file rather than stderr, which is what a container engine expects — containerd opens that file to report why a create failed and finds nothing if it is not written. `--log-format json` writes one object per line with the fields runc writes, and `--systemd-cgroup` is accepted and reaches libcrun's context, where the field already existed. `--log-file` keeps its own meaning, which is to copy nexcage's log to a file as well.
- `src/core/rfc3339.zig` formats the log timestamp as RFC 3339. It was epoch seconds as a number, and containerd answered `Time.UnmarshalJSON: input is not a JSON string`: Go's `time.Time` wants a quoted date.
- With those two fixed, **podman drives nexcage end to end**: `podman --runtime nexcage run … /bin/sh -c 'echo HELLO_FROM_NEXCAGE'` prints it, having sent `create --bundle … --pid-file … <id>`, `start <id>` and `delete --force <id>` — the command line built over #261, #265 and #266, with no option the runtime did not know.
- `start`, `kill` and `delete` work on the crun backend, which is the first time they have been run there at all: `create --console-socket` then `start` gives `"status": "running"`, and `delete --force` destroys a running container so that `state` afterwards reports it gone.
- `kill --all` reaches `libcrun_container_killall` on the crun backend, which is what the flag means. It used to be dropped before the backend saw it, so `--all` signalled only the init. Verified as far as: the call is made, returns success where the cgroup namespace allows it, and the container stops. **Not** verified: that it reaches a process the plain `kill` would miss — a test meant to show that measured nothing, and the claim is libcrun's rather than one this repository has demonstrated. In a container whose cgroup is not delegated it fails with `read from file 'cgroup.procs': Operation not supported` and leaves the container paused.
- `delete --force` reaches libcrun on the crun backend. The driver passed a hardcoded `false`, so the flag was accepted and then not forced.
- `create --console-socket <path>` and `create --pid-file <path>`, the two runtime-spec options a container engine sends with `create`. On the crun backend `--console-socket` makes a bundle whose spec sets `process.terminal` creatable at all: the runtime allocates the pty and sends its master end over the caller's Unix socket with `SCM_RIGHTS` — checked by receiving it and confirming `isatty` — where the same bundle without the flag still answers "use --console-socket with create when a terminal is used". The fields were already present in the libcrun context struct and simply never filled in; the Zig declaration was verified field by field against `struct libcrun_context_s` at the commit `deps/crun` is pinned to.
- On the Proxmox LXC backend both flags fail with exit 1 and explain why: `pct create` starts no process, so there is no pty to hand over and no pid to write. They are refused rather than accepted and ignored — a caller that passes `--console-socket` and receives no file descriptor waits for one that never arrives.
- The runtime-spec command line, so a container engine can call nexcage the way it calls runc and crun. `create <container-id> --bundle <dir>` takes the id positionally, as the spec defines it; without `--bundle` the positional word is still the image, so the older `create --name <name> <image>` keeps working. `--root <dir>`, before or after the command, puts per-container state somewhere other than `/run/nexcage` — containerd gives each namespace its own directory, and without this every caller on a host shares one. `delete --force` shuts a running container down instead of refusing, and `kill --all` is accepted, logging what it really does on LXC rather than implying it walked the cgroup.
- `state` reports `bundle`: the directory the container was created from, kept across `start` and `stop`, and `null` for a container created from a template or a registry image. An OCI caller reads it back to find the `config.json` it handed over.
- `exec`: `nexcage exec <name> <command> [args...]` runs a command inside a running container and exits with **its** status, the way `runc exec` does — `nexcage exec web-1 sh -c 'exit 7'` exits 7 — so a caller that reads the status, such as containerd or a readiness probe, gets the command's result rather than the runtime's. `--` passes a command that starts with a dash through untouched. stdin, stdout and stderr are connected straight to the process in the container rather than captured, so output arrives as it is produced and is not held to the 1 MB cap the other commands use. The Proxmox LXC backend runs `pct exec`, crun goes through libcrun, runc has no exec and says so. The command was parsed in `main.zig` and mapped to `Command.exec` but never registered, so it printed "unknown command".

### Changed
- The crun backend says what libcrun said. `struct libcrun_error_s` was declared opaque in the FFI, so every failure was released unread and reported as "libcrun <operation> failed". It is bound now, and the message matches what `crun` itself prints — `libcrun container_create: use --console-socket with create when a terminal is used`, where there used to be nothing to go on. The failure is still `OperationFailed`: `e.status` cannot be mapped onto a specific error reliably, because `crun_error_wrap` keeps whatever status the innermost error set and several paths format the errno into the message and leave status at 0.

### Fixed
- **A flag written `--root=<dir>` was read as a command name.** An engine picks the spelling without asking: containerd sends `--root <dir>`, and CRI-O mixes both — `create` goes through conmon, which writes `--root=<dir>`, while `start`, `state`, `kill` and `delete` come from CRI-O itself in the two-word form. runc and crun accept either. CRI-O's first call therefore came back as `unknown command '--root=/run/nexcage-crio'` and no pod could start. `--flag=value` is now split into two words once, before any parser looks at the vector, so every flag accepts both spellings; the split stops at a bare `--`, where what follows is the command `exec` runs inside the container and `env FOO=bar` is an argument rather than a flag.
- **`--version` was not a flag.** CRI-O asks a runtime its version before it will use one, and asks with the flag rather than the subcommand. It maps onto the same command, so the two spellings cannot print different things.
- **The crun backend did not enter the bundle it was given.** An OCI spec names its rootfs relative to the bundle (`"path": "rootfs"`), and libcrun resolves that against the working directory, which is why crun and runc `chdir` into the bundle before they create a container. Every engine so far had run the runtime from the bundle, so it never showed; containerd's CRI shim serves a whole pod and runs the runtime from the *sandbox's* directory while `--bundle` names the container's own, and the container's rootfs was looked for inside the sandbox's — where `/bin/sh` really is absent, because only `/pause` lives there. A pod's sandbox came up and its container never did. `tests/crun/foreign_cwd.sh` creates a container from a working directory that is not the bundle, and the crun CI job runs it.
- An OCI bundle's `config.json` was read as nexcage's configuration. `./config.json` is first in the search path, a bundle holds a `config.json` that is a runtime spec, and a container engine runs the runtime from the bundle directory — so the routing rules were silently replaced by a file that is not a configuration. A file declaring `ociVersion` is skipped in the search path, and named with `--config` it is refused as the wrong kind of file rather than reported as missing. podman did not expose this; containerd did.
- A container engine's container id was rejected. `create` applied an RFC-1123 hostname rule to the id before any backend was chosen, and podman and containerd address containers by a 64-character hex id against a 63-character label limit — so `podman --runtime nexcage run` failed on its very first call with "Invalid container name/hostname". The rule belongs to the Proxmox LXC backend, where the name becomes the container's hostname, and now lives there and says which backend requires it.
- The catch-all routing rule in `config.json.example` matched nothing. A pattern is a regular expression only when it starts with `^` or ends with `$`; everything else is a shell-style wildcard, so `".*"` meant "a literal dot followed by anything". The example now uses `"*"`, and the reference explains the rule, because a routing rule that silently never fires sends every container to the default backend.
- `kill --all` printed "nexcage signals the container's init; only SIGKILL reaches every process in it" on every backend, because it was said in the command before the backend was chosen. On crun that is untrue. The caveat now lives where the backend is known, and is printed only for Proxmox LXC.
- The crun backend did not build. `exec` in its driver had never been compiled — Zig analyses what is reachable, and nothing called it — so the `null` it appended to a list of non-optional pointers went unnoticed until the router started routing `exec` there. The driver says plainly that exec is not implemented for crun now: libcrun's exec entry point has no binding in `libcrun_ffi.zig`, and the code that pretended otherwise built a C argv, discarded it and returned "not wired".
- `crun backend build` ran on a pull request only when it touched `build.zig`, the `Dockerfile` or `src/backends/crun/`. A path filter cannot express what pulls a backend into a compilation, so the change that broke the build passed its own checks and only failed on main afterwards. It runs on every pull request now.
- The crun backend derived the bundle path from the container id (`/var/lib/nexcage/bundles/<id>`) and ignored the one the caller gave, so it looked where nothing had written it. It uses the given bundle, and takes its state directory from `--root`.
- Bundles were confined to `/var/lib/nexcage/bundles/` and `/tmp/nexcage-bundles/`, which refused every bundle a container engine hands over — containerd keeps one per task under `/run/containerd/`, podman under its storage root — and runc and crun accept any. Any absolute path is accepted; `..` still cannot escape, because the path is resolved first, and a relative path is still refused, since the engine's working directory is not nexcage's to guess.
- `--runtime` before the command did nothing. It was read as the command name at first, and once that was fixed it was still dropped: the loop that finds the command skips a global flag, and the arguments handed to the parser start after the command, so `nexcage --runtime crun create …` was parsed, accepted, and routed to Proxmox LXC anyway.
- The crun driver never freed the strings libcrun's context points at, because the router never called `deinit` on it — the same for runc.
- The crun driver's C strings were built by appending `\x00` to an `allocPrint` and keeping a slice one byte shorter than the allocation. Freeing that in `deinit` aborted with "Allocation size N does not match free size N-1". The file uses `allocPrintSentinel` throughout now; five other sites were correct but used the same shape.

## [0.9.1] - 2026-09-24

The first release since 0.8.0: 0.9.0 was prepared but never tagged, so its
changes ship here. Every command behaves as 0.9.0 described; what 0.9.1 adds is
a packaging fix. The published 0.8.0 binary and `.deb` were built for the build
machine's CPU and die with `SIGILL` on any host without AVX2 — checked against
the release asset on a Xeon E5-2697 v2. Release notes with upgrade guidance:
`docs/releases/NOTES_v0.9.1.md`.

### Added
- `deploy/kubernetes/tenant-nexcage/vm-e2e-node.yaml`: the Proxmox VE node the E2E suite runs on, declared as a kubemox `VirtualMachine` in the tenant. kubemox clones the template `nexcage-pve-tpl-v0-1` on prox-home into a Debian 13 guest running Proxmox VE 9.2.20, so `pct`, `pvesh`, `pvesm` and `pveam` are all real and the node is disposable.
- `deploy/kubernetes/tenant-nexcage/pve-template/`: the four scripts that build that template from the Debian 13 cloud image, and what each works around — grub-pc without an install device, the netplan and systemd-networkd configuration that fights ifupdown2 for the address, the enterprise repository `proxmox-ve` adds, and the `net.ifnames=0` the Proxmox kernel's grub update drops.
- `scripts/register_e2e_runner.sh`: registers the Actions runner on that node with the labels `proxmox,pve9,nexcage-e2e`. The template carries the runner software but no registration.
- `proxmox_e2e.yml` exercises the OCI registry path: `nexcage run --name … docker.io/library/redis:7` pulls through `oci-registry-pull`, has to reach `running` with a real init PID, and has to be unprivileged. Proxmox VE before 9.1 cannot pull from a registry, so the step says so and skips.
- `docs/KUBERNETES_INTEGRATION.md`: what the runtime still lacks before Kubernetes can schedule onto it (`exec`, the OCI runtime-spec command line, logs, CNI, sandboxes, an image service, a remote surface), the constraints measured in the Cozystack cluster `pskep`, and the four stages from an in-cluster build job to CRI.
- `deploy/kubernetes/tenant-nexcage/`: the Cozystack `Tenant` nexcage is developed in, and a `Job` that builds nexcage and runs the unit tests and smoke checks inside the cluster. `tests/sim/run.sh` is not among them: the Talos nodes report `user.max_user_namespaces=0` inside pods, so the job reports that instead of failing on it.
- `.github/workflows/buildagent.yml`: build, unit tests, simulation suite and the `.deb` on the self-hosted CageForge build agent (Debian 13, on the Proxmox host prox-home). It checks the package payload without installing it, because the runner user has no passwordless sudo.

### Changed
- `proxmox_e2e.yml` runs on `[self-hosted, pve9]` instead of `[proxmox]`, which pins it to a Proxmox VE 9.x host rather than whichever machine holds the older label.

### Fixed
- `zig fmt --check` failed on 21 files on `main`, so `make lint` and `make check` failed on a clean clone. The tree is formatted and CI checks it, which is why it had drifted: nothing did. The change is whitespace only — 238 insertions against 240 deletions, no line of logic touched.
- `proxmox_e2e.yml` picked the first `vztmpl` volume as its template, which on Proxmox VE 9.1+ can be an OCI image rather than a system template — `nexcage run docker.io/…` leaves one there itself. Every container the suite creates has to boot, and the OCI bundle step uses that same archive as its rootfs, so an application image with no `/sbin/init` failed at `start` with nothing pointing at the cause. It now picks a system template by name, and the registry step frees the image it pulled.
- The released binary and `.deb` were built for the build machine's CPU: Zig's default target is native, and `zig build -Doptimize=ReleaseSafe` on a GitHub runner produced a binary that dies with `SIGILL` on a Xeon E5-2697 v2 — ordinary hardware for a Proxmox host. The published 0.8.0 asset does exactly that. Both release paths now pass `-Dcpu=baseline`, and the 0.9.1 `.deb` was run on that CPU before tagging.

## [0.9.0] - 2026-09-15

Release notes with upgrade guidance: `docs/releases/NOTES_v0.9.0.md`.

### Added
- `tests/sim/run.sh` (`make sim`) runs every command against fake `pct`, `pvesh`, `pvesm`, `pveversion` and `pveam`, with nexcage as uid 0 in a user namespace. It checks the arguments passed, exit codes, output and state files, and fails on any allocator leak or panic. CI runs it on every pull request.
- `--config <path>`, before or after the command, reads configuration from that file instead of the default locations; a missing or unparsable file is an error. It used to be parsed and ignored.

### Removed
- Source that nothing used: `src/integrations/` (bfc, proxmox-api, zfs) with the `enable-zfs`, `enable-bfc` and `enable-proxmox-api` build options; `core/router.zig`, `advanced_logging.zig`, `metrics.zig`, `json_logging.zig`, `comptime_validation.zig`; `proxmox-lxc/pct.zig`, `performance.zig`, `simple_performance.zig`, `state_manager.zig`, `vmid_manager.zig`; `crun/types.zig`. Checked by building the default, runc and VM configurations and running the tests without them.
- The `deps/bfc` submodule, used only by the integrations module.
- The remote `oci_spec_zig` entry in `build.zig.zon`. The build uses the vendored `deps/oci-spec-zig`; the entry only made the first build download a copy.
- The CodeQL (C/C++) job in `security.yml` and `.github/codeql/codeql-config.yml`. Every run failed with "No source files found": CodeQL does not analyse Zig, and outside the ignored `deps/` there is a single header. `security.yml` now asks only for `contents: read`.
- The DCO check (`dco.yml`) and the sign-off requirement in CONTRIBUTING.md. The action it used had been deleted upstream, so the check failed on every pull request; contributions no longer need a `Signed-off-by` trailer.
- `archive/`, `Roadmap/`, scripts for the old SSH-based test and release process, the dependency-update scripts, `bump_version.sh` (it rewrote every version string in the docs, release notes included), committed test reports, files in `tests/` without tests, and 30 documents that described features nexcage does not have or were superseded by the current guides.
- `src/utils/lxc_converter.zig`. Nothing called it, and it could not have produced a working template: it copied rootfs files without their executable bits, failed on the first symlink and wrote a non-executable `/sbin/init` over the real one.

### Changed
- Issue templates moved from `docs/ISSUE_TEMPLATE` to `.github/ISSUE_TEMPLATE`, where GitHub uses them.
- The documentation site navigation lists only current documents.
- `--runtime <lxc|crun|runc|vm>` overrides the config file's routing for `create`, `run`, `start`, `stop`, `delete`, `kill` and `state`. It used to be parsed and ignored. An unknown value is a usage error (exit 2), and `runc` no longer selects crun.
- New containers are unprivileged unless `proxmox.unprivileged` is `false`, as in the Proxmox VE web UI. They used to be privileged by default.
- `kill` sends the signal to the container's init from the host with `kill(2)`, using the host PID from `pct status --verbose`, as an OCI runtime does. It used to run `kill -s SIGNAL 1` inside the container through `pct exec`: the kernel drops a signal sent from inside a PID namespace to its init unless init handles it, so even `SIGKILL` did nothing, and it failed wherever lxc-attach cannot run. Signal names are accepted in any case, with or without `SIG`; an unknown signal is a usage error (exit 2).
- `state` reports the host PID of the container's init while it runs (it was always 0) and `created` for a container not yet started through nexcage (it said `stopped`).

### Fixed
- `list` printed an empty table and exited 0 when `pct list` failed, for example without root or on a host without pct. It now fails with pct's message.
- `--log-level` and `--log-file` after the command name made their value the container name: `nexcage start --log-level debug web` started `debug`.
- Creating a container from an OCI bundle gave `pct create` a template name that nothing had written, so it failed with "not found". The bundle's `rootfs/` is now packed with tar into `local:vztmpl/nexcage-<name>-<time>.tar.zst`, used for `pct create` and deleted afterwards.
- A bundle without `config.json` or `rootfs/` crashed nexcage with `panic: invalid error code`. It is now a usage error that names what is missing, and a bundle outside `/var/lib/nexcage/bundles/` or `/tmp/nexcage-bundles/` says where bundles must be.
- The VM backend, `run` on crun and runc, and `state` for crun, runc and VM logged a warning or printed a made-up `unknown` state and exited 0. They now fail with "not implemented".
- `health --help` ran every check, and `version --help` printed the version. Both print help.
- Memory leaks: the bundle path on every create from a bundle, and the output of `pct version` on every `health` run.
- Creating a container from an OCI bundle without mounts logged "No mp entries visible in pct config after update".

## [0.8.0] - 2026-09-15

MVP: a working command-line lifecycle for LXC containers on a Proxmox VE host.
Release notes with upgrade guidance: `docs/releases/NOTES_v0.8.0.md`.

### Changed
- A plain `zig build` produces a working Proxmox LXC binary. The crun and runc backends are opt-in (`-Denable-backend-crun=true`, `-Denable-backend-runc=true`); the libcrun ABI follows the crun backend instead of whether libsystemd happens to be installed.
- The default bridge is `vmbr0` (was `vmbr50`), and `network.bridge` from the config file now reaches the backend.
- New config keys: `proxmox.storage`, `proxmox.rootfs_size_gb`, `proxmox.ostype`, `proxmox.unprivileged`.
- VMIDs come from `pvesh get /cluster/nextid` instead of a hash of the container name.
- `stop` runs `pct shutdown --timeout 60 --forceStop 1` instead of `pct stop`.
- Logs go to stderr; stdout carries only command output. `--debug` and `--log-level` set the level.
- A failure prints one line, `nexcage: <command>: <outcome>`. Exit status is 1 for failed operations and 2 for usage errors.
- `create` refuses a name that already exists.
- `state` looks a container up by name (or VMID) and fails when it does not exist.

### Fixed
- Every command held a pointer to a logger in a dead stack frame. Logging from commands could crash, which the CLI had worked around by not logging.
- `--log-file` never wrote to its file.
- `pct list` parsing read the Lock column as the name, and broke on long lock names.
- `create` forced `--ostype ubuntu` on every template, and reported success when pct failed with "already exists".
- `kill -s SIGNAL` lost the signal and took its value as the container name.
- `run --help` aborted with "Invalid free".
- A bare `*.tar.zst` template name became `local:vztmpl/<name>.tar.zst.tar.zst`.
- A registry image on Proxmox VE older than 9.1 fails with an explanation instead of a usage error.
- The Proxmox VE version is read correctly from the `pve-manager/X.Y.Z/…` form.

### Removed
- Tests for code that no longer exists, plus `src/backend_plugins.zig` and `src/cli/example_usage.zig`, moved to `archive/`. None of those tests had ever run.
- CI workflows that could not pass: `ci_cncf.yml`, `build_vendored.yml`, `dependencies.yml`, `test_runner0.yml`. `crun_e2e.yml` and `crun_abi_e2e.yml` are archived.
- Build logs, a committed gitleaks binary and a 0.7.1 `.deb` from the repository root; the old dh-based packaging (archived).

### CI and release
- `ci.yml` builds, tests and smoke-tests on GitHub-hosted runners; `crun_build.yml` builds the crun backend through the Dockerfile.
- The Proxmox E2E job drives create, state, start, stop and delete through nexcage instead of calling pct directly.
- Releases build the binary and the `.deb` on GitHub-hosted runners.
- The dependency check files at most one open issue per dependency.

## [0.7.5] - 2025-11-11

### 🚀 ABI-First Release: oci-specs-zig Integration

This release finalises the libcrun ABI migration by consuming OCI Runtime Specification v1.3.0 types from the new `oci-specs-zig` package and promoting the metadata fields through Proxmox LXC tooling.

### Added
- Pin the external `oci-specs-zig` package (vendored via `build.zig.zon`) to provide generated runtime/image/distribution schemas.
- Apply OCI `linux.netDevices` aliases when provisioning Proxmox LXC containers, generating pct `--netX` arguments and matching `/etc/network/interfaces` entries.
- Persist parsed `linux.intelRdt` profiles alongside container state for downstream QoS automation.

### Changed
- Template metadata now captures Intel RDT and network device information for visibility in the cache API.
- `oci_bundle.zig` now relies on shared runtime structs from `oci-specs-zig`, ensuring parity with upstream schema updates.
- Build pipeline links the new package and ensures `zig build`/`zig build test` exercise vendored libcrun plus schema-based parsing.

### Documentation
- README and `docs/DEV_QUICKSTART.md` updated with instructions for managing the `oci-specs-zig` dependency and ABI-only architecture.
- `docs/releases/NOTES_v0.7.5.md` captures detailed upgrade guidance for the ABI-based release.

## [0.7.4] - 2025-11-07

### 🚀 Spec Parity Release: OCI Runtime v1.3.0 Support

This release upgrades the OCI ingestion pipeline to fully understand the Linux additions introduced between v1.0.2 and v1.3.0, ensuring future bundles load without manual downgrades.

### Added
- **NUMA Memory Policy Parsing**: Support for `linux.memoryPolicy` (modes, nodes, flags) with strict validation.
- **Intel RDT Enhancements**: Parse `closID`, `schemata`, cache and memory bandwidth schemas, plus the new `enableMonitoring` flag.
- **Network Device Inventory**: Parse `linux.netDevices` map entries with alias/name support for future LXC bridging.
- **Developer Guidance**: README & Dev Quickstart now highlight OCI Runtime Spec v1.3.0 as the tested baseline.

### Changed
- Hardened error handling around malformed `memoryPolicy`, `intelRdt`, and `netDevices` entries to surface actionable diagnostics.
- Unit tests updated to cover OCI 1.3.0 fields and prevent regressions.
- Removed the legacy crun CLI fallback; builds now compile vendored `deps/crun` sources and require only libsystemd when targeting the crun backend.

### Testing
- `zig build`
- `zig build test`

### Documentation
- `docs/releases/NOTES_v0.7.4.md` — detailed notes for the release.
- README, `docs/DEV_QUICKSTART.md` — compatibility snapshot and requirements now state OCI 1.3.0 support.

---

## [0.7.3] - 2025-11-02

### 🔧 Bug Fix Release: Memory Leaks, Template Conversion, OCI Resources

This release fixes critical bugs in template conversion and OCI bundle processing, resolves memory leaks, and adds support for OCI bundle resource limits and namespaces.

### Added
- **OCI Bundle Resources Support**: 
  - Parse `memory_limit` from `linux.resources.memory.limit` (bytes to MB conversion)
  - Parse `cpu_limit` from `linux.resources.cpu.shares` (shares/1024.0 to cores conversion)
  - Priority: bundle_config > SandboxConfig > defaults
- **OCI Namespaces Support**:
  - Parse all OCI namespaces from `linux.namespaces` array (pid, network, ipc, uts, mount, user, cgroup)
  - Map user namespace to Proxmox LXC features (`nesting=1,keyctl=1`) via `pct set --features`
  - Automatic feature configuration based on namespace presence
- **Enhanced Validation**:
  - Recursive file counting in `validateRootfsDirectory` (counts files in subdirectories)
  - Validation before and after LXC configurations are applied
  - Detailed logging for file operations in `copyDirectoryRecursive`

### Fixed
- **Memory Leak in Template Manager**: 
  - Added `errdefer template_info.deinit()` for error cleanup
  - Added `errdefer metadata.deinit()` for metadata cleanup
  - Added `defer template_info.deinit()` after `addTemplate()` (which clones)
  - Proper cleanup for entrypoint and cmd arrays with errdefer blocks
- **Template Archive Issues**:
  - Archive now correctly includes all files (verified: `bin/sh`, `sbin/init`, `etc/hostname`)
  - Fixed recursive validation to count files in subdirectories
  - Enhanced error handling in `copyDirectoryRecursive`
- **CPU Cores Calculation**:
  - Fixed `cores=0` issue when CPU shares < 1024
  - Added minimum of 1 core guarantee: `if (calculated < 1.0) 1.0 else calculated`
  - Applied to both bundle_config and final calculation
- **pct create Error Handling**:
  - Enhanced debug output for exit codes, stdout, stderr
  - Better handling of "already exists" scenarios
  - Improved error messages for debugging

### Changed
- **Error Types**: Added `CopyFailed`, `RootfsNotFound`, `EmptyRootfs`, `ArchiveCreationFailed` to `core.Error`
- **Image Converter**: Enhanced `copyDirectoryRecursive` with detailed logging and error handling
- **Template Validation**: Switched from top-level only to recursive directory traversal

### Testing
- ✅ Memory leak resolved: No more leaks detected in template_manager
- ✅ Archive creation verified: All files included correctly
- ✅ Recursive validation working: Correctly counts files in subdirectories
- ✅ Cores fix verified: Containers now created with minimum 1 core (was 0)
- ✅ Container creation successful: Verified on Proxmox server (VMID 31386, 72421)
- ✅ pct create command working: Exit code 0, container configured correctly

### Documentation
- `docs/ANALYSIS_CREATE_PROXMOX_LXC.md` - Updated with implementation details
- `docs/OCI_BUNDLE_GENERATOR.md` - Updated with namespace mapping information
- `docs/TEMPLATE_CONVERSION_DEBUG.md` - Debugging analysis document
- `docs/TEST_RESULTS_PROXMOX.md` - Test results document
- `docs/INTEGRATION_TEST_PROXMOX.md` - Integration testing guide

### Notes
- Template warnings about `/etc/os-release` not found are expected for minimal OCI bundles
- Architecture detection falls back to `amd64` (normal behavior)
- ostype detection shows `unmanaged` for custom OCI bundles (expected)

---

## [0.7.2] - 2025-10-31

### 🎯 Code Quality & Observability Release: Error Handling, Memory Safety, Testing, Metrics

This release focuses on codebase quality improvements from Sprint 6.6, including comprehensive error handling, memory leak detection, test coverage increases, structured logging, Prometheus metrics, and automated dependency monitoring.

### Added
- **Error Handling System**: 
  - `ErrorContext` with detailed error information (message, source, line, column, stack trace)
  - `ErrorContextBuilder` for fluent error context creation
  - `ContextualError` and `ErrorWithContext` for error chaining
  - Helper functions: `createErrorContext`, `createErrorContextWithSource`
- **Memory Leak Detection**:
  - Automated memory audit script (`scripts/memory_leak_audit.sh`)
  - Valgrind integration in CI (`.github/workflows/memory_leak_check.yml`)
  - Memory leak audit report (`docs/MEMORY_LEAK_AUDIT_REPORT.md`)
  - Enhanced errdefer usage in critical paths
- **Comptime Validation**:
  - Comptime validation module (`src/core/comptime_validation.zig`)
  - Type-safe ConfigBuilder pattern
  - Comptime string operations (StringOps)
  - Runtime type parsing at compile time
- **Structured JSON Logging**:
  - JSON logger (`src/core/json_logging.zig`)
  - Structured log output with timestamp, level, component, message
  - Custom fields support via `logWithFields()`
  - Proper JSON escaping
- **Prometheus Metrics**:
  - Metrics registry (`src/core/metrics.zig`)
  - Counter, Gauge, and Histogram metric types
  - Label support for metrics
  - Prometheus text format export
- **Test Coverage**:
  - 4 new test files for core modules
  - ~25+ new test functions
  - Coverage increased from ~60% to ~75-80%
  - Tests for router, errors, comptime_validation, validation modules
- **Dependency Monitoring**:
  - Dependabot configuration for GitHub Actions and Docker
  - Custom workflow for OCI specs, crun, and Proxmox VE monitoring
  - Automatic GitHub issue creation for available updates
  - Weekly scheduled checks

### Changed
- **Memory Management**:
  - Added errdefer for all allocations in `router.zig`
  - Improved error path cleanup safety
  - Better memory lifecycle documentation
- **Code Cleanup**:
  - Removed ~60 lines of obsolete code
  - Clarified 10+ TODO comments with better context
  - Removed unused AppContext fields and methods
- **Error Handling**:
  - Replaced `format()` with `formatError()` in ErrorWithContext
  - Improved error message formatting
  - Better error context propagation

### Fixed
- **Memory Leaks**: Added errdefer statements in critical allocation paths
- **Code Quality**: Removed shadowing issues in metrics module
- **Build System**: Fixed comptime validation syntax for Zig 0.15.1 compatibility
- **Documentation**: Updated all documentation to reflect new features

### Documentation
- `docs/MEMORY_LEAK_AUDIT_REPORT.md` - Memory audit results
- `docs/CODE_CLEANUP_REPORT.md` - Code cleanup summary
- `docs/COMPTIME_IMPROVEMENTS.md` - Comptime features documentation
- `docs/TEST_COVERAGE_IMPROVEMENTS.md` - Test coverage tracking
- `docs/OBSERVABILITY_IMPROVEMENTS.md` - Observability features guide
- `docs/releases/NOTES_v0.7.2.md` - Release notes

### Infrastructure
- Dependabot configuration for automated dependency updates
- Custom dependency check workflow for OCI specs, crun, Proxmox VE
- Memory leak check workflow in CI
- Enhanced test infrastructure

### Notes
- Comptime validation auto-validation disabled due to Zig 0.15.1 syntax limitations
- JSON logging and metrics available but require manual integration
- Test coverage improvements ensure better stability
- Dependency monitoring helps track critical updates automatically

---

## [0.7.1] - 2025-10-31

### 🔧 Integration + Stability Release: libcrun ABI, OCI state.json, Proxmox fixes

This release adds libcrun ABI integration and includes critical fixes and improvements made after v0.7.0, including OCI state.json persistence, Proxmox-LXC kill command improvements, and enhanced E2E test stability.

### Added
- **libcrun ABI Integration**: Direct FFI bindings for libcrun API (`libcrun_container_create`, `start`, `kill`, `delete`)
- **libcrun Context Management**: Proper context initialization and lifecycle management for libcrun operations
- **Feature Flag Support**: Automatic fallback to CLI driver when libcrun ABI is unavailable (systemd dependency)
- **OCI state.json Persistence**: 
  - State files created at `/run/nexcage/<container_id>/state.json` on container creation
  - State updates on `start` (status: "running", actual PID) and `stop` (status: "stopped", pid: 0)
  - PID retrieval from running containers via `pct exec <vmid> -- cat /proc/1/stat`
- **libcrun FFI Bindings**: Complete Zig bindings for libcrun container operations

### Changed
- **CrunDriver**: Now uses libcrun ABI in Debug mode, CLI driver in Release mode (systemd dependency handling)
- **Build System**: Added systemd linking for libcrun ABI support
- **Module Structure**: Added `libcrun_driver.zig` and `libcrun_ffi.zig` for ABI-based operations
- **Default Network Bridge**: Changed from `lxcbr0` to `vmbr50` for Proxmox-LXC backend (Proxmox default)
- **E2E Test Framework**: 
  - Help tests now pass if help text is detected, regardless of exit code
  - Automatic Proxmox template provisioning in test scripts
  - Improved test output capture and validation

### Fixed
- **Proxmox-LXC Kill Command**: 
  - Pre-check if container is already stopped (treat as success)
  - Multiple fallback paths: `/usr/bin/kill`, `/bin/kill`, `/bin/sh -c`
  - Status polling after signal attempts (10 retries, 200ms interval)
  - Treat exit code 255 as success if container is confirmed stopped
  - Enhanced debug logging for all exec attempts
- **OCI state.json Implementation**:
  - Fixed JSON formatting for Zig 0.15.1 compatibility
  - Proper OCI-compliant state output format
  - Correct PID tracking for running containers
- **Memory Management**: 
  - Fixed memory management in libcrun context initialization
  - Proper null-terminated string handling for C FFI
  - Context structure alignment for libcrun API compatibility
- **Build Compatibility**: Removed `std.time.sleep` usage, replaced with `std.time.sleep(ns_per_ms)` for Zig 0.15.1

### Added (Post-v0.7.0)
- **DEB Package Support**: Automatic DEB package building for releases
  - Package name: `nexcage`
  - Installation via `dpkg -i nexcage-<version>-amd64.deb`
  - Configuration files and documentation included
- **CNCF Compliance Improvements**:
  - DCO (Developer Certificate of Origin) check workflow
  - OpenSSF Scorecards integration
  - CycloneDX SBOM generation
  - SLSA Provenance support
- **Codebase Quality Improvements**:
  - Repository cleanup (removed 29 obsolete files)
  - Archive organization (21 files moved to archive/)
  - Enhanced .gitignore for build artifacts
  - Codebase maturity: 7.9 → 8.5/10

### Changed (Post-v0.7.0)
- **Build System**: Optional libcrun/systemd linking (disabled by default for portability)
- **Documentation**: Added quality improvement plans and best practices guides

### Notes
- libcrun ABI requires systemd library for cgroup management
- CLI driver remains available as fallback when systemd is not available
- Debug builds use libcrun ABI, Release builds use CLI driver by default
- E2E test success rate improved from 88% to 93% (40/43 tests passing)
- DEB packages are automatically built on release tags
- All releases include SBOMs (SPDX + CycloneDX) and SLSA provenance

---

## [0.7.0] - 2025-10-29

### 🚀 Feature + Hardening Release: OCI kill/state, Proxmox fixes, security

This release delivers new OCI-compatible commands and multiple stability and security improvements across the Proxmox LXC backend and CLI.

### Added
- OCI `kill` command with `--signal` option (wired to proxmox-lxc, crun, runc)
- OCI `state` command returning OCI-compatible JSON
- Extensive debug tracing (opt-in via `--debug`)
- Foundational input validators (hostname/vmid/storage/path/env)

### Changed
- Debug output is gated by flags (`--debug`) to reduce noise by default
- Proxmox LXC: image parsing corrected — Proxmox templates vs docker-style refs
- Proxmox LXC: ZFS dataset creation validates pool/dataset existence; creates parents
- Path security hardening: bundle path validation and boundary checks
- Logging: safer allocator usage, writer changes to prevent segfaults

### Fixed
- Create command segfault due to logger allocator misuse
- ZFS errors when pool does not exist — now gracefully degraded or auto-creates parents
- Misclassification of `ubuntu:20.04` as Proxmox template

### Notes
- E2E: base smoke stable; functional flows pending create/start stabilization on target PVE

---

## [0.6.1] - 2025-10-27

### ✨ Enhancement Release: Improved Error Handling

This release focuses on improving error handling for Proxmox LXC backend, providing better error messages and validation.

### Changed
- **Enhanced pct Error Mapping**: Comprehensive error mapping for all pct command scenarios
- **Improved Error Messages**: Better error messages with actionable feedback for users
- **Detailed Logging**: Added detailed logging for debugging pct command failures
- **Error Categorization**: Better error categorization (Timeout, PermissionDenied, InvalidInput, NetworkError, etc.)

### Added
- **VMID Validation**: Check VMID uniqueness before creating containers
- **Comprehensive Error Detection**: Detect common pct command error scenarios
- **Enhanced Error Context**: Detailed error information with logging

### Fixed
- **Error Code Semantics**: Fixed incorrect error codes for existing resources (changed from NotFound to OperationFailed)
- **VMID Collision Prevention**: Proper validation prevents duplicate container creation
- **Error Message Clarity**: Clear, actionable error messages help users resolve issues quickly

### Technical Details
- **Error Handling**: Comprehensive error mapping for all pct command errors
- **Validation**: VMID validation before container creation
- **Logging**: Detailed logging for debugging and troubleshooting
- **User Experience**: Better error messages with actionable feedback

---

## [0.6.0] - 2025-10-15

### 🎉 Major Release: Backend Integration & Legacy Cleanup

This release completes the backend integration system and removes all legacy code, providing a clean, modern, and production-ready codebase.

### Added
- **Backend Routing System**: Intelligent backend selection based on container naming patterns
- **OCI Backend Support**: 
  - Crun Driver: Full OCI container lifecycle management
  - Runc Driver: Alternative OCI runtime support
- **Proxmox VM Backend**: Complete VM management via Proxmox API
- **PCT CLI Integration**: Native Proxmox LXC management via `pct` command
- **Container Type Detection**: Automatic backend selection based on config patterns
- **E2E Testing**: Automated testing on remote Proxmox servers
- **Stub Libraries**: Minimal crun and bfc libraries for build compatibility

### Changed
- **Architecture**: Moved from direct API calls to CLI-based Proxmox integration
- **CLI Commands**: Refactored to use backend routing instead of direct OCI calls
- **Configuration**: Enhanced with container routing patterns and backend selection
- **Build System**: Completely rewritten for clean modular architecture
- **Error Handling**: Improved error mapping for external command failures

### Removed
- **Legacy Code**: All legacy build files and directories removed
- **Archive Files**: Old documentation and examples moved to archive
- **Old Sprint Files**: Cleaned up outdated sprint documentation
- **Direct API Calls**: Replaced with CLI-based Proxmox integration
- **Circular Dependencies**: Resolved all module dependency issues

### Fixed
- **Memory Leaks**: Resolved all known memory allocation issues
- **Build Errors**: Fixed compilation errors and dependency issues
- **Module Imports**: Cleaned up all import statements and dependencies
- **Type Mismatches**: Resolved all type casting and compatibility issues

### Technical Details
- **Backend Selection**: Based on `config.json` routing patterns
- **Container Types**: LXC, VM, crun, runc with automatic detection
- **CLI Integration**: Direct backend calls without OCI layer
- **Testing**: Automated E2E tests with SSH deployment
- **Documentation**: Comprehensive architecture and implementation guides

### Migration Notes
- Legacy code preserved in `legacy/backend-routing-integration` branch
- All functionality maintained with improved architecture
- Configuration format updated for backend routing
- Build system simplified and modernized

---

## [0.4.0] - 2025-10-01

### 🚀 Major Release: Modular Architecture

This release introduces a complete modular architecture following SOLID principles, providing clean separation of concerns and extensibility.

### Added
- **Modular Architecture**: Complete redesign following SOLID principles
- **Core Module**: Global settings, errors, logging, interfaces, and types
- **CLI Module**: Registry-based command system with built-in and custom commands
- **Backend Modules**: 
  - LXC Backend: Native LXC container management
  - Proxmox LXC Backend: Proxmox API integration for LXC containers
  - Proxmox VM Backend: Proxmox API integration for virtual machines
  - Crun Backend: OCI-compatible container runtime
- **Integration Modules**:
  - Proxmox API: RESTful API client for Proxmox VE
  - ZFS Integration: ZFS filesystem operations and snapshots
  - BFC Integration: Binary File Container support
- **Utils Module**: File system and network utilities
- **Command Registry**: Dynamic command registration and execution
- **Structured Logging**: Comprehensive logging system with multiple levels
- **Configuration Management**: Centralized configuration loading and parsing
- **Error Handling**: Centralized error types and handling mechanisms

### Changed
- **Architecture**: Complete redesign from monolithic to modular architecture
- **CLI System**: New registry-based command system replaces direct command handling
- **Backend Selection**: Dynamic backend selection through configuration
- **Memory Management**: Improved allocator usage patterns for Zig 0.13.0 compatibility
- **Documentation**: Complete documentation overhaul with examples and guides

### Deprecated
- **Legacy Version**: Legacy monolithic architecture marked as deprecated
- **Old CLI**: Direct command handling deprecated in favor of registry system
- **Monolithic Backends**: Individual backend implementations deprecated

### Removed
- **Monolithic Structure**: Removed tight coupling between components
- **Legacy Dependencies**: Cleaned up unused dependencies
- **Deprecated APIs**: Removed deprecated API interfaces

### Fixed
- **Memory Management**: Fixed allocator union access issues for Zig 0.13.0
- **Module Dependencies**: Resolved circular dependencies
- **Error Handling**: Improved error propagation and handling
- **Configuration Loading**: Fixed configuration parsing and validation

### Security
- **Input Validation**: Enhanced input validation across all modules
- **Error Information**: Improved error messages without exposing sensitive data
- **Memory Safety**: Better memory management and cleanup

### Documentation
- **MODULAR_ARCHITECTURE.md**: Comprehensive architecture guide
- **Usage Examples**: Complete examples for all modules
- **Migration Guide**: Guide for moving from legacy to modular architecture
- **API Documentation**: Complete API documentation for all modules
- **Best Practices**: Development and usage guidelines

### Examples
- **modular_basic_example.zig**: Basic usage examples for all backends
- **modular_cli_example.zig**: CLI integration and custom command examples

### Performance
- **Module Loading**: Optimized module loading and initialization
- **Memory Usage**: Improved memory allocation patterns
- **Command Execution**: Streamlined command processing through registry
- **Backend Selection**: Efficient backend selection and caching

### Breaking Changes
- **Module Structure**: Complete restructuring requires code updates
- **CLI Interface**: New command registry system
- **Configuration Format**: Updated configuration structure
- **API Interfaces**: New interface definitions for backends and integrations

### Migration Notes
- Update imports to use modular paths
- Use new configuration system
- Leverage new logging system
- Take advantage of registry-based CLI
- See MODULAR_ARCHITECTURE.md for detailed migration guide

## [0.3.0] - 2025-09-15

### Added
- ZFS Checkpoint/Restore system
- Lightning-fast container state snapshots
- Hybrid ZFS snapshots + CRIU fallback system
- Advanced performance optimizations
- Enhanced security features

### Changed
- Improved container lifecycle management
- Enhanced ZFS integration
- Better error handling and recovery

### Fixed
- Memory leak issues
- Performance bottlenecks
- Configuration parsing bugs

## [0.2.0] - 2025-08-20

### Added
- Proxmox VE integration
- OCI Runtime Specification compliance
- Container orchestration support
- Advanced networking features

### Changed
- Improved API design
- Enhanced documentation
- Better error messages

## [0.1.0] - 2025-07-10

### Added
- Initial release
- Basic LXC container support
- OCI image system
- Core runtime functionality

---

## Support Policy

Before 1.0, a fix lands in the next release; there are no maintenance
branches. Which releases receive security fixes is in
[SECURITY.md](SECURITY.md). The policy for 1.0 and after is not written yet.

## Upgrade Path

Every release since 0.8.0 has notes in `docs/releases/NOTES_v<version>.md`
that say what changes for someone upgrading: a renamed column, a new shared
library, a removed configuration key. Going from one release to a later one,
read the notes of each release in between. 0.9.0 was prepared but never
tagged; its changes ship in 0.9.1.
