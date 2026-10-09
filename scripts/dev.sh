#!/usr/bin/env bash
# One entry point for working on nexcage on a workstation: the tools it needs,
# the builds, every test that runs without a Proxmox host, the GitHub-hosted CI
# jobs through act, and the performance suites. docs/LOCAL_DEVELOPMENT.md
# explains each command; `scripts/dev.sh help` lists them.
#
# Nothing here needs root. Containers run under rootless podman when it is
# there, otherwise Docker; CONTAINER_ENGINE=docker picks Docker.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

ZIG=${ZIG:-zig}
ZIG_VERSION=0.15.1
ACT=${ACT:-act}
ACT_IMAGE=localhost/nexcage-act:latest
CRUN_IMAGE=${CRUN_IMAGE:-localhost/nexcage:ci}
CRI_IMAGE=${CRI_IMAGE:-localhost/nexcage:cri-test}
BUSYBOX=docker.io/library/busybox:1.36
DEV=$REPO/zig-out/dev
BUNDLE=$DEV/bundle

# The jobs `act` runs by default: every job a pull request gets on a
# GitHub-hosted runner, except security.yml, whose scanners upload to GitHub,
# plus dependency_check.yml's crun job in its dry run, which reads the
# repository's issues and the crun releases and writes nothing.
ACT_JOBS_DEFAULT="ci.yml:build-test ci.yml:simulation version-check.yml:version crun_build.yml:docker memory_leak_check.yml:memory-leak-check dependency_check.yml:check-crun"

if [ -t 2 ]; then B=$'\033[1m' R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' N=$'\033[0m'; else B='' R='' G='' Y='' N=''; fi
say()  { echo "${B}==> $*${N}" >&2; }
warn() { echo "${Y}warning:${N} $*" >&2; }
die()  { echo "${R}dev.sh:${N} $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: scripts/dev.sh <command> [options]

Set up
  doctor            check the tools each command needs, and say how to get them
  setup             start the podman socket, build act's runner image, fetch
                    the busybox rootfs the container tests use

Build and test (no containers)
  build             Debug build (zig-out/bin) and ReleaseSafe (zig-out/release/bin)
  test              zig fmt --check and the unit tests
  sim               every command against fake Proxmox tools (tests/sim)
  check             test + sim: the quick gate before a commit

Containers (rootless podman or Docker)
  crun              the crun-backend image, and what crun_build.yml checks on it
  cri               a pod through containerd's CRI with nexcage as the runtime
  e2e               sim + crun + cri: everything that runs without Proxmox
  shell [CMD...]    a shell (or CMD) in the CRI image: nexcage, crun, containerd, crictl

CI
  act [WF:JOB...]   GitHub-hosted jobs through act; default: $ACT_JOBS_DEFAULT
                    Arguments after -- go to act.
  all               check, then act: what a pull request will run, minus Proxmox
  pve-e2e           run proxmox_e2e.yml on the self-hosted Proxmox runner for
                    this branch (pushed first), and follow it

Performance
  perf [options]    time the lifecycle commands; see docs/LOCAL_DEVELOPMENT.md
    --against REF   also measure REF (e.g. main) and fail on a regression
    --suite S       lxc, crun or all (default all)
    -n N            measured passes per binary (default 20)

Environment: CONTAINER_ENGINE (podman|docker), ZIG, ACT, CRUN_IMAGE, CRI_IMAGE
EOF
}

# --- helpers ----------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

ENGINE=''
engine() {
  [ -n "$ENGINE" ] && return 0
  local e
  for e in ${CONTAINER_ENGINE:-podman docker}; do
    if have "$e" && "$e" info >/dev/null 2>&1; then ENGINE=$e; return 0; fi
  done
  die "no container engine answers. Install podman (preferred: rootless, storage under ~) or start Docker, or set CONTAINER_ENGINE"
}
# podman's default image format drops fields Docker's has; ask for Docker's.
engine_build() { engine; if [ "$ENGINE" = podman ]; then podman build --format docker "$@"; else docker build "$@"; fi; }
image_exists() { engine; "$ENGINE" image inspect "$1" >/dev/null 2>&1; }

podman_socket() { echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"; }

# act talks to the Docker API; rootless podman serves it on a per-user socket.
act_env() {
  engine
  if [ "$ENGINE" = podman ] && [ -z "${DOCKER_HOST:-}" ]; then
    local sock; sock=$(podman_socket)
    [ -S "$sock" ] || die "act needs podman's API socket: systemctl --user start podman.socket (or scripts/dev.sh setup)"
    export DOCKER_HOST=unix://$sock
  fi
  if [ "$ENGINE" = docker ]; then
    warn "with Docker, act's --bind leaves root-owned files in the checkout; rootless podman does not"
  fi
}

zig_ok() { have "$ZIG" && [ "$("$ZIG" version 2>/dev/null)" = "$ZIG_VERSION" ]; }
need_zig() { zig_ok || die "needs zig $ZIG_VERSION (found: $(have "$ZIG" && "$ZIG" version || echo none)); see scripts/dev.sh doctor"; }

# step NAME CMD...: run CMD with its output shown and kept in zig-out/dev/logs,
# and record whether it passed. A failed step does not stop the ones after it.
STEPS=()
step() {
  local name=$1 t0 rc=0 log; shift
  mkdir -p "$DEV/logs"; log=$DEV/logs/$name.log
  say "$name"
  t0=$SECONDS
  # Not `... || rc=$?`: in that position bash ignores set -e even inside the
  # subshell, and a step would carry on past its first failure.
  set +e
  ( set -e; "$@" ) 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e
  if [ "$rc" = 0 ]; then STEPS+=("${G}PASS${N}  $name  ($((SECONDS - t0))s)")
  else STEPS+=("${R}FAIL${N}  $name  ($((SECONDS - t0))s, exit $rc, log: ${log#"$REPO"/})"); fi
  return 0
}
summary() {
  local s failed=0
  [ "${#STEPS[@]}" -gt 0 ] || return 0
  echo >&2; say "summary"
  for s in "${STEPS[@]}"; do echo "  $s" >&2; case "$s" in *FAIL*) failed=1 ;; esac; done
  return "$failed"
}

# --- doctor and setup --------------------------------------------------------

doctor() {
  local bad=0
  ok()   { printf '  %s%-26s%s %s\n' "$G" "$1" "$N" "$2"; }
  miss() { printf '  %s%-26s%s %s\n' "$R" "$1" "$N" "$2"; bad=1; }
  opt()  { printf '  %s%-26s%s %s\n' "$Y" "$1" "$N" "$2"; }

  echo "${B}build, test, sim, perf${N}"
  if zig_ok; then ok "zig $ZIG_VERSION" "$(command -v "$ZIG")"
  else miss "zig $ZIG_VERSION" "found: $(have "$ZIG" && "$ZIG" version || echo none); https://ziglang.org/download/#release-$ZIG_VERSION"; fi
  local t
  for t in python3 tar zstd unshare git; do
    if have "$t"; then ok "$t" "$(command -v "$t")"; else miss "$t" "install it with the system package manager"; fi
  done
  if have unshare && unshare -rm bash -c 'mount -t tmpfs tmpfs /tmp' 2>/dev/null; then
    ok "user namespace mounts" "the simulator can run nexcage as uid 0 without root"
  else
    miss "user namespace mounts" "sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu 24.04+)"
  fi
  if [ -x /usr/bin/time ]; then ok "GNU time" "perf reports peak memory"
  else opt "GNU time" "optional: apt install time, for peak memory in perf"; fi

  echo "${B}crun, cri, e2e, shell, perf --suite crun${N}"
  local e found=''
  for e in ${CONTAINER_ENGINE:-podman docker}; do
    if have "$e" && "$e" info >/dev/null 2>&1; then
      found=$e
      if [ "$e" = podman ] && [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = true ]; then
        ok "podman (rootless)" "$(podman --version)"
      else ok "$e" "$("$e" --version)"; fi
      break
    elif have "$e"; then opt "$e" "installed but not answering"
    fi
  done
  [ -n "$found" ] || miss "container engine" "install podman (apt install podman) or start Docker"
  if [ -n "$found" ]; then
    image_exists "$CRUN_IMAGE" && ok "crun image" "$CRUN_IMAGE" || opt "crun image" "built on first use by 'crun' (about 3 minutes)"
    [ -d "$BUNDLE/rootfs/bin" ] && ok "busybox bundle" "${BUNDLE#"$REPO"/}" || opt "busybox bundle" "fetched by 'setup' or first use"
  fi

  echo "${B}act${N}"
  if have "$ACT"; then ok "act" "$("$ACT" --version)"
  else miss "act" "download act_Linux_x86_64.tar.gz and checksums.txt from https://github.com/nektos/act/releases, check the sum, put act in ~/.local/bin"; fi
  if [ "$found" = podman ]; then
    [ -S "$(podman_socket)" ] && ok "podman API socket" "$(podman_socket)" || miss "podman API socket" "systemctl --user start podman.socket (or scripts/dev.sh setup)"
  fi
  if [ -n "$found" ]; then
    image_exists "$ACT_IMAGE" && ok "act runner image" "$ACT_IMAGE" || miss "act runner image" "scripts/dev.sh setup builds it from .github/act"
  fi
  [ -f .actrc ] && ok ".actrc" "maps ubuntu-* to $ACT_IMAGE, --bind, --pull=false" || miss ".actrc" "missing from the checkout"

  echo "${B}pve-e2e${N}"
  if have gh && gh auth status >/dev/null 2>&1; then ok "gh (logged in)" "$(gh --version | head -1)"
  else opt "gh" "optional: gh auth login, to dispatch the Proxmox E2E and to run dependency_check through act"; fi

  echo
  if [ "$bad" = 0 ]; then echo "${G}everything the commands need is here${N}"
  else echo "${R}something above is missing; 'scripts/dev.sh setup' fixes what it can without root${N}"; fi
  return "$bad"
}

fetch_bundle() {
  [ -e "$BUNDLE/rootfs/bin/sh" ] && return 0
  engine
  say "busybox rootfs into ${BUNDLE#"$REPO"/}"
  rm -rf "$BUNDLE"; mkdir -p "$BUNDLE/rootfs"
  local c=nexcage-dev-busybox-$$
  "$ENGINE" create --name "$c" "$BUSYBOX" >/dev/null
  "$ENGINE" export "$c" | tar -x -C "$BUNDLE/rootfs"
  "$ENGINE" rm "$c" >/dev/null
}

setup() {
  engine
  if [ "$ENGINE" = podman ] && [ ! -S "$(podman_socket)" ]; then
    say "starting podman's API socket for act"
    systemctl --user start podman.socket
  fi
  if ! image_exists "$ACT_IMAGE"; then
    say "building act's runner image $ACT_IMAGE (catthehacker act-latest plus gh)"
    engine_build -t "$ACT_IMAGE" .github/act
  fi
  fetch_bundle
  doctor
}

# --- build and test ----------------------------------------------------------

build()   { need_zig; "$ZIG" build --summary all && "$ZIG" build -Doptimize=ReleaseSafe -p zig-out/release; }
unit()    { need_zig; "$ZIG" fmt --check src/ tests/ && "$ZIG" build test --summary all; }
sim()     { need_zig; "$ZIG" build && bash tests/sim/run.sh; }

# --- containers ----------------------------------------------------------------

# The Dockerfile clones vendored crun at its pin and builds from a clean tree;
# the engine's layer cache makes a rebuild with unchanged sources quick.
crun_image() { say "crun image $CRUN_IMAGE"; engine_build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t "$CRUN_IMAGE" .; }
privileged() { "$ENGINE" run --rm --privileged --cgroupns=private "$@"; }

# What crun_build.yml checks, in the same order, on the same scripts.
crun_checks() {
  engine; crun_image; fetch_bundle
  say "the binary runs";   "$ENGINE" run --rm "$CRUN_IMAGE" version
  say "the features ABI still matches the vendored header"
  engine_build --target builder -t localhost/nexcage:builder .
  "$ENGINE" run --rm -v "$REPO/scripts:/s:ro" localhost/nexcage:builder sh /s/check_features_abi.sh
  say "the features document comes from this build's libcrun"
  "$ENGINE" run --rm "$CRUN_IMAGE" --runtime crun features > "$DEV/features.json"
  python3 tests/crun/features_check.py "$DEV/features.json"
  say "ps reports the container's processes, and crun agrees"
  privileged -v "$BUNDLE:/bundle" -v "$REPO/tests/crun:/t:ro" --entrypoint /bin/sh "$CRUN_IMAGE" /t/ps.sh
  say "a bundle is found from a working directory that is not it"
  privileged -v "$BUNDLE:/bundle" -v "$REPO/tests/crun:/t:ro" --entrypoint /bin/sh "$CRUN_IMAGE" /t/foreign_cwd.sh
}

# Always through crun_image: an image left from older sources would test them.
cri_image() { engine; crun_image; engine_build -f tests/cri/Dockerfile --build-arg BASE="$CRUN_IMAGE" -t "$CRI_IMAGE" tests/cri; }
cri() { cri_image; privileged -v "$REPO/tests/cri:/t:ro" "$CRI_IMAGE" /t/pod_on_nexcage.sh; }

# Containers need their own cgroups, and a process in the root of the
# container's cgroup namespace keeps the kernel from giving them any: `ps` then
# fails reading cgroup.procs. The tests do the same before they start.
SHELL_INIT='if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
  mkdir -p /sys/fs/cgroup/init
  for p in $(cat /sys/fs/cgroup/cgroup.procs); do echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null; done
  for c in cpu memory pids; do echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null; done
fi'
shell() {
  cri_image; fetch_bundle
  local run=(run --rm --privileged --cgroupns=private -v "$REPO:/src:ro" -v "$BUNDLE:/bundle" -w /src --entrypoint /bin/bash)
  if [ $# -gt 0 ]; then
    "$ENGINE" "${run[@]}" -i "$CRI_IMAGE" -c "$SHELL_INIT"'
exec "$@"' bash "$@"
    return
  fi
  cat >&2 <<EOF
${B}A privileged container with nexcage (crun backend), crun, containerd and crictl.${N}
  /src      this checkout, read-only        /bundle   a busybox bundle
  nexcage --runtime crun create --bundle /bundle demo && nexcage --runtime crun start demo
  nexcage --runtime crun ps demo            nexcage --runtime crun delete --force demo
  /src/tests/cri/pod_on_nexcage.sh          a pod through containerd's CRI
  /src/tests/perf/crun.sh -n 5              the crun perf suite
EOF
  "$ENGINE" "${run[@]}" -it "$CRI_IMAGE" -c "$SHELL_INIT"'
exec bash'
}

# --- act -----------------------------------------------------------------------

act_jobs() {
  have "$ACT" || die "act is not installed; see scripts/dev.sh doctor"
  act_env
  image_exists "$ACT_IMAGE" || die "no $ACT_IMAGE; run scripts/dev.sh setup"
  local jobs=() extra=() a
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then shift; extra=("$@"); break; fi
    jobs+=("$1"); shift
  done
  [ "${#jobs[@]}" -gt 0 ] || read -r -a jobs <<< "$ACT_JOBS_DEFAULT"
  # In a linked worktree .git is a file pointing into the main repository's
  # .git, which is outside the mounted checkout, so git fails in the job
  # container. Mounting that directory read-only at the same path fixes it.
  local common gitdir
  common=$(git rev-parse --path-format=absolute --git-common-dir)
  gitdir=$(git rev-parse --path-format=absolute --git-dir)
  [ "$common" = "$gitdir" ] || extra=(--container-options "-v $common:$common:ro" "${extra[@]}")
  # A job's `docker build` goes to podman through the socket. The act image's
  # docker CLI then builds with buildx's docker-container driver, which leaves
  # the image in its cache and never loads it, so the job's next `docker run`
  # finds nothing -- or an older image of the same name, and passes on it. The
  # classic builder hands the build to podman itself.
  [ "$ENGINE" != podman ] || extra=(--env DOCKER_BUILDKIT=0 "${extra[@]}")
  mkdir -p "$DEV/act-artifacts"
  for a in "${jobs[@]}"; do
    local wf=${a%%:*} job=${a#*:} event=pull_request
    local -a run=("$ACT") with=()
    [ -f ".github/workflows/$wf" ] || die "no workflow .github/workflows/$wf"
    [ "$job" != "$a" ] || die "'$a': name a job as WORKFLOW:JOB, e.g. ci.yml:simulation"
    case "$wf" in
      dependency_check.yml)
        # Scheduled, so it is dispatched here. Given a token its last step
        # files, edits or closes issues in the repository; dry_run prints
        # what it would do instead. The token is gh's, read inside the step
        # so that it never appears on a command line or in a log.
        if ! gh auth token >/dev/null 2>&1; then
          warn "skipping $a: it reads GitHub with gh's token (gh auth login)"; continue
        fi
        event=workflow_dispatch
        with=(--input dry_run=true -s GITHUB_TOKEN)
        # shellcheck disable=SC2016  # the inner shell expands these
        run=(bash -c 'GITHUB_TOKEN=$(gh auth token) exec "$0" "$@"' "$ACT") ;;
    esac
    step "act-${wf%.yml}-$job" "${run[@]}" "$event" -W ".github/workflows/$wf" -j "$job" \
      --artifact-server-path "$DEV/act-artifacts" "${with[@]}" "${extra[@]}"
  done
}

# --- Proxmox E2E on the self-hosted runner -------------------------------------

pve_e2e() {
  have gh || die "needs gh, logged in"
  local branch sha
  branch=$(git rev-parse --abbrev-ref HEAD)
  sha=$(git rev-parse HEAD)
  [ "$branch" != HEAD ] || die "check out a branch first"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || warn "uncommitted changes are not part of the run"
  [ "$(git rev-parse -q --verify "origin/$branch" 2>/dev/null)" = "$sha" ] || \
    die "origin/$branch is not $sha; push the branch first: git push -u origin $branch"
  say "dispatching proxmox_e2e.yml on $branch ($sha)"
  gh workflow run proxmox_e2e.yml --ref "$branch"
  local id='' _
  for _ in $(seq 1 30); do
    id=$(gh run list --workflow proxmox_e2e.yml --branch "$branch" --event workflow_dispatch \
           --json databaseId,headSha --jq "map(select(.headSha == \"$sha\")) | first | .databaseId // empty")
    [ -n "$id" ] && break
    sleep 2
  done
  [ -n "$id" ] || die "the dispatched run did not show up; see: gh run list --workflow proxmox_e2e.yml"
  gh run watch "$id" --exit-status
}

# --- performance -----------------------------------------------------------------

perf() {
  local against='' suite=all n=20 rounds=4
  while [ $# -gt 0 ]; do
    case "$1" in
      --against) against=$2; shift 2 ;;
      --suite)   suite=$2; shift 2 ;;
      -n)        n=$2; shift 2 ;;
      *) die "perf: unknown option $1" ;;
    esac
  done
  case "$suite" in lxc|crun|all) ;; *) die "perf: --suite is lxc, crun or all" ;; esac
  need_zig
  local run; run=$DEV/perf/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$run"
  local samples=$run/samples.tsv

  # head: this checkout, as it is. base: REF, built in a worktree of its own.
  local head_label base_label='' base_dir='' base_bin='' base_image=''
  head_label=head@$(git rev-parse --short HEAD)
  [ -z "$(git status --porcelain --untracked-files=no)" ] || head_label+=+dirty
  say "ReleaseSafe build of $head_label"
  "$ZIG" build -Doptimize=ReleaseSafe -p zig-out/release
  local head_bin=$REPO/zig-out/release/bin/nexcage

  if [ -n "$against" ]; then
    local sha; sha=$(git rev-parse --verify "$against^{commit}") || die "perf: no commit '$against'"
    base_label=${against//\//-}@$(git rev-parse --short "$sha")
    base_dir=$DEV/perf/base-$sha
    if [ ! -d "$base_dir" ]; then
      git worktree add --detach "$base_dir" "$sha" >/dev/null
    fi
    say "ReleaseSafe build of $base_label in ${base_dir#"$REPO"/}"
    (cd "$base_dir" && "$ZIG" build -Doptimize=ReleaseSafe -p zig-out/release)
    base_bin=$base_dir/zig-out/release/bin/nexcage
  fi

  # Both builds run the same suite scripts -- this checkout's -- taking turns,
  # so a change in the machine's load lands on both. lxc_sim.sh alternates
  # them within every pass; the crun suite, one image per container,
  # alternates in rounds.
  if [ "$suite" != crun ]; then
    local x=(-x "$head_label=$head_bin")
    [ -z "$base_bin" ] || x=(-x "$base_label=$base_bin" "${x[@]}")
    say "lxc-sim"
    SIM_DIR=$DEV/perf/sim bash tests/perf/lxc_sim.sh -n "$n" "${x[@]}" -o "$samples"
  fi
  local per=$(( (n + rounds - 1) / rounds )) r
  if [ "$suite" != lxc ]; then
    engine; crun_image; fetch_bundle
    if [ -n "$base_dir" ]; then
      base_image=localhost/nexcage:perf-${base_label##*@}
      say "crun image of $base_label"
      (cd "$base_dir" && engine_build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t "$base_image" .)
    fi
    for r in $(seq 1 "$rounds"); do
      if [ -n "$base_image" ]; then
        say "crun, $base_label, round $r/$rounds"
        privileged -v "$BUNDLE:/bundle" -v "$REPO/tests/perf:/p:ro" -v "$run:/out" \
          --entrypoint /bin/bash "$base_image" /p/crun.sh -n "$per" -l "$base_label" -o /out/samples.tsv
      fi
      say "crun, $head_label, round $r/$rounds"
      privileged -v "$BUNDLE:/bundle" -v "$REPO/tests/perf:/p:ro" -v "$run:/out" \
        --entrypoint /bin/bash "$CRUN_IMAGE" /p/crun.sh -n "$per" -l "$head_label" -o /out/samples.tsv
    done
  fi

  local cmp=()
  [ -z "$base_label" ] || cmp=(--compare "$base_label" "$head_label")
  local rc=0
  python3 tests/perf/report.py "$samples" "${cmp[@]}" --json "$run/summary.json" | tee "$run/report.txt" || rc=${PIPESTATUS[0]}
  ln -sfn "$run" "$DEV/perf/latest"
  say "samples, summary and report in ${run#"$REPO"/} (also zig-out/dev/perf/latest)"
  return "$rc"
}

# --- dispatch ----------------------------------------------------------------------

cmd=${1:-help}; [ $# -gt 0 ] && shift
case "$cmd" in
  help|-h|--help) usage ;;
  doctor)  doctor ;;
  setup)   setup ;;
  build)   build ;;
  test)    unit ;;
  sim)     sim ;;
  check)   step test unit; step sim sim; summary ;;
  crun)    crun_checks ;;
  cri)     cri ;;
  e2e)     step sim sim; step crun crun_checks; step cri cri; summary ;;
  shell)   shell "$@" ;;
  act)     act_jobs "$@"; summary ;;
  # act's crun_build.yml job is the crun and cri steps, exactly as CI runs them
  all)     step test unit; step sim sim; act_jobs "$@"; summary ;;
  pve-e2e) pve_e2e ;;
  perf)    perf "$@" ;;
  *) usage >&2; exit 2 ;;
esac
