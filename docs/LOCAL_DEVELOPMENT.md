# Local Development

`scripts/dev.sh` is the one entry point for working on nexcage on a
workstation: it checks the tools, builds, runs every test that works without a
Proxmox host, runs the GitHub-hosted CI jobs through
[act](https://github.com/nektos/act), and times every command for performance
work. Nothing in it needs root. The `make` targets below call it.

```bash
scripts/dev.sh setup        # once: podman socket, act's runner image, a busybox rootfs
scripts/dev.sh check        # before a commit: zig fmt, unit tests, the simulator
scripts/dev.sh all          # before a pull request: check, then every CI job through act
```

## What runs where

| Command | `make` | What it runs | Needs | Time here¹ |
|---|---|---|---|---|
| `doctor` | `doctor` | Checks every tool below and says how to get what is missing | | 1 s |
| `setup` | `dev-setup` | Starts podman's API socket, builds act's runner image, fetches busybox | a container engine | minutes, once: the act image is 1.7 GB |
| `build` | `build` | Debug to `zig-out/bin`, ReleaseSafe to `zig-out/release/bin` | zig 0.15.1 | seconds |
| `test` | `check` | `zig fmt --check`, unit tests | zig | 6 s |
| `sim` | `sim` | Every command against fake `pct`/`pvesh`/`pvesm` ([TESTING.md](../TESTING.md#running-against-fake-proxmox-tools)) | zig, unshare | 12 s |
| `check` | | `test` + `sim` | | 20 s |
| `crun` | | The crun-backend image and what `crun_build.yml` checks on it: the features ABI, the features document, `ps` against crun, a bundle from a foreign working directory | a container engine | 3 min first, then seconds |
| `cri` | | A pod through containerd's CRI with nexcage as the runtime handler: sandbox, CNI address, container, `exec`, `update`, removal | a container engine | 5 s, plus the images |
| `e2e` | `e2e` | `sim` + `crun` + `cri` | | |
| `shell [CMD]` | `dev-shell` | A shell with nexcage (crun backend), crun, containerd and crictl, or CMD run there | a container engine | |
| `act` | `act` | The GitHub-hosted CI jobs, in the runner image | act, a container engine; gh logged in for `dependency_check.yml` | 1.5–4 min per job |
| `all` | `local-ci` | `check`, then `act`, whose `crun_build.yml` job is `crun` and `cri` as CI runs them | | 12 min |
| `pve-e2e` | | `proxmox_e2e.yml` on the self-hosted Proxmox VE runner, for this branch | gh, the branch pushed | 10 min |
| `perf` | `perf` | Times every command; see [Performance](#performance) | zig; a container engine for `--suite crun` | 1 min for `lxc`, 4 min for both with `--against` |

¹ A 12-core workstation with rootless podman, warm caches.

Multi-step commands (`check`, `e2e`, `act`, `all`) run every step even after
one fails, keep each step's output in `zig-out/dev/logs/<step>.log`, and end
with a summary; the exit status is 1 if any step failed.

## Setting up

1. **Zig 0.15.1**, exactly: `zig version` must print `0.15.1`. From
   <https://ziglang.org/download/#release-0.15.1>.
2. **A container engine.** Rootless podman is the tested one: its storage is
   under `~/.local/share/containers`, and files that containers write into the
   checkout stay yours. Docker works as well (`CONTAINER_ENGINE=docker`), but
   act's `--bind` then leaves root-owned files in the checkout.
3. **act**: download `act_Linux_x86_64.tar.gz` and `checksums.txt` from
   <https://github.com/nektos/act/releases>, check the sum, and put `act` in
   `~/.local/bin`. The `curl … | sudo bash` installer does the same but runs an
   unreviewed script as root.
4. `scripts/dev.sh setup`, then `scripts/dev.sh doctor` until it is all green.

The simulator runs nexcage as uid 0 in an unprivileged user namespace. On
Ubuntu 24.04 and later AppArmor forbids mounts there by default;
`doctor` says so, and the fix is
`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.

## Containers

`crun`, `cri`, `shell` and `perf --suite crun` build `localhost/nexcage:ci`
from the repository's `Dockerfile` — the same image `crun_build.yml` builds —
which clones vendored crun at its pin and builds the crun backend. With
unchanged sources the engine's layer cache makes a rebuild take seconds. The
CRI image `localhost/nexcage:cri-test` adds containerd, crictl and the CNI
plugins on top of it.

The tests run in a privileged container with its own cgroup namespace. Under
rootless podman two things differ from CI's rootful Docker, and the tests
handle both:

- Only `cpu`, `memory` and `pids` are delegated to a user's cgroups, so
  controllers are enabled one at a time; a single write naming `cpuset` or
  `io` would fail as a whole and enable nothing.
- containerd runs in a user namespace, where the kernel refuses to lower
  `oom_score_adj` and AppArmor profiles cannot be loaded.
  `tests/cri/pod_on_nexcage.sh` sees the user namespace and sets
  `restrict_oom_score_adj` and `disable_apparmor`, as containerd's own startup
  warning asks.

`scripts/dev.sh shell` leaves you in that container with the checkout at
`/src` (read-only) and a busybox bundle at `/bundle`, its processes already
moved out of the root cgroup as the tests do — otherwise containers get no
cgroup of their own and `ps` fails. `scripts/dev.sh shell CMD...` runs CMD
there instead.

```bash
nexcage --runtime crun create --bundle /bundle demo
nexcage --runtime crun start demo && nexcage --runtime crun ps demo
nexcage --runtime crun delete --force demo
/src/tests/cri/pod_on_nexcage.sh
```

## CI through act

`scripts/dev.sh act` runs, by default, every job a pull request gets on a
GitHub-hosted runner: `ci.yml` (`build-test`, `simulation`),
`version-check.yml`, `crun_build.yml` and `memory_leak_check.yml`, plus the
crun job of `dependency_check.yml` in its dry run. Name jobs to run others, and
pass act's own options after `--`:

```bash
scripts/dev.sh act ci.yml:simulation
scripts/dev.sh act crun_build.yml:docker -- --verbose
```

`.actrc` maps `ubuntu-latest`, `ubuntu-24.04` and `ubuntu-22.04` to
`localhost/nexcage-act:latest` — catthehacker's act image plus `gh`, built from
`.github/act` — turns pulling off, and adds `--bind`, because act's copy of the
checkout drops the submodule's `.git` file. `dev.sh` adds three things act
cannot know:

- `DOCKER_HOST` pointing at podman's socket.
- `DOCKER_BUILDKIT=0` under podman. A job's `docker build` goes to podman
  through the socket, and the act image's docker CLI then builds with buildx's
  `docker-container` driver, which keeps the result in its own cache and never
  loads it: the job's next `docker run` finds nothing, or an older image of the
  same name and passes on that. The classic builder hands the build to podman.
- In a linked `git worktree`, a read-only mount of the main repository's
  `.git`, which the worktree's `.git` file points into and which is otherwise
  outside the container.

`dependency_check.yml` is scheduled, so `dev.sh` dispatches it, with
`dry_run=true` and the token `gh auth token` holds: the job reads the
repository's open issues and the crun releases and prints what it would file,
edit or close. Without that input and with a token it does those things in
CageForge/nexcage, so keep `--input dry_run=true` when running act on it by
hand; without a gh login `dev.sh` skips the job and says so.

Not in the default set: `proxmox_e2e.yml` and `buildagent.yml` need
self-hosted runners, and `security.yml` uploads to GitHub's code scanning.

## The Proxmox E2E

The simulator shows what nexcage asks of Proxmox; only a Proxmox VE host shows
what Proxmox then does. `scripts/dev.sh pve-e2e` dispatches
`proxmox_e2e.yml` for the current branch on the self-hosted runner and follows
the run until it ends. The branch must be pushed at the commit you have
checked out; the script refuses otherwise, so the run is of the code in front
of you.

## Performance

```bash
scripts/dev.sh perf                      # this checkout
scripts/dev.sh perf --against main       # this checkout against main; exit 1 on a regression
scripts/dev.sh perf --suite lxc -n 40    # one suite, more passes
make perf PERF_ARGS='--against v0.13.0'
```

Both builds are ReleaseSafe: a Debug build's allocator checks would be much of
what gets timed. `--against REF` builds REF in a worktree under
`zig-out/dev/perf/`, and the two builds run the same suite scripts — this
checkout's — taking turns, so a change in the machine's load lands on both:
the LXC suite runs both binaries in every pass against the same fake host,
the crun suite alternates the two images in four rounds. Each run keeps
`samples.tsv`, `summary.json` and `report.txt` in `zig-out/dev/perf/<time>/`,
linked from `zig-out/dev/perf/latest`.

Two suites:

**`lxc-sim`** (`tests/perf/lxc_sim.sh`) runs the Proxmox LXC lifecycle —
`version`, `list` with ten containers, `create`, `state`, `start`, `exec`,
`kill`, `stop`, `delete`, `run`, `create` from an 8 MB OCI bundle — against the
simulator's fake tools. For each command:

- `calls`: how many times it ran `pct`, `pvesh`, `pvesm`, `pveam` or
  `pveversion`. On a real node each is a Perl process costing 0.3–1 s, so this
  is most of what a user of a real node waits for, and it does not vary
  between runs. Any increase is a regression.
- `wall_us`: nexcage's own wall time, measured inside the namespace. The fakes
  are shell scripts, so it includes a few milliseconds per call; it is for
  comparing two builds on one machine, not a prediction for a Proxmox host.
- `maxrss_kb`: peak memory, from one run under GNU time.

**`crun`** (`tests/perf/crun.sh`) runs `features`, `create`, `start`, `state`,
`ps`, `exec`, `kill` and `delete` on the crun backend inside the crun image,
and the same lifecycle through the image's own `crun` binary, taking turns. The
report shows nexcage's overhead over crun per operation. The reference is the
distribution's crun, not the vendored libcrun nexcage links, so part of a small
difference can be the version.

`tests/perf/report.py` decides what is a regression. A change in time counts
only if the median rose by more than 10 % and 0.5 ms and three quarters of the
new samples are above the old median: time on a workstation is noisy, and this
asks for a shift, not a blip. Comparing `main` with itself this way stays
within ±3 %. An extra `pct list` and 5 ms put into the lookup of a container's
init PID look like this, and the run exits 1:

```text
suite/op               main@e42238ca ms  head@e42238ca+dirty ms  change   calls
lxc-sim/list                      12.95                   13.27   +2.4%       2  ok
lxc-sim/state-running             32.09                   47.42  +47.8%  3 -> 4  MORE CALLS
lxc-sim/kill                      21.00                   36.29  +72.8%  2 -> 3  MORE CALLS
lxc-sim/stop                      24.56                   23.94   -2.5%       2  ok
```

`--threshold` and `--min-delta-us` change the bounds, and the script can be
run again on any `samples.tsv`:

```bash
python3 tests/perf/report.py zig-out/dev/perf/latest/samples.tsv \
    --compare main@e42238c head@1a2b3c4 --threshold 5
```

## Files

| Path | What |
|---|---|
| `scripts/dev.sh` | The entry point |
| `.actrc`, `.github/act/Dockerfile` | act's defaults and runner image |
| `tests/sim/lib.sh` | The fake Proxmox host, shared by the simulator and the perf suite |
| `tests/perf/lxc_sim.sh`, `tests/perf/crun.sh` | The perf suites; each writes samples |
| `tests/perf/report.py` | Summary, comparison, regression verdict |
| `tests/crun/features_check.py` | The features document check, shared with `crun_build.yml` |
| `zig-out/dev/` | Logs, the busybox bundle, act's artifacts, perf runs (`make clean` removes it) |

After `make clean`, run `git worktree prune` if `perf --against` had created a
worktree there.
