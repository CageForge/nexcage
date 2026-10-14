#!/usr/bin/env bash
# scripts/dev.sh: every container it starts, every podman build it runs and
# act's job container carry a memory and pids cap. A copy of dev.sh runs in a
# scratch tree with a fake podman and a fake act that record what they are
# asked; nothing is built or run for real.
#
#   bash tests/scripts/dev_caps.sh [path/to/dev.sh]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/../.." && pwd)
DEVSH=$(realpath "${1:-$REPO/scripts/dev.sh}")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

failed=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failed=1; }

mkdir -p "$T/repo/scripts" "$T/repo/zig-out/dev/bundle/rootfs/bin" "$T/bin"
cp "$DEVSH" "$T/repo/scripts/dev.sh"
cp -r "$REPO/.github" "$T/repo/.github"
: > "$T/repo/zig-out/dev/bundle/rootfs/bin/sh"
(cd "$T/repo" && git init -q)
cat > "$T/bin/podman" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$T/calls"
exit 0
FAKE
cat > "$T/bin/act" <<'FAKE'
#!/bin/sh
printf 'act %s\n' "$*" >> "$T/calls"
exit 0
FAKE
chmod +x "$T/bin/podman" "$T/bin/act"
export T

# DOCKER_HOST and XDG_RUNTIME_DIR are the scratch tree's, so the test needs no
# podman API socket and takes no lock of the machine it runs on: a CI runner
# has neither socket nor runtime directory.
mkdir -p "$T/run"
devsh() {
  : > "$T/calls"
  rc=0
  env PATH="$T/bin:$PATH" CONTAINER_ENGINE=podman ACT="$T/bin/act" \
    DOCKER_HOST="unix://$T/run/podman.sock" XDG_RUNTIME_DIR="$T/run" \
    bash "$T/repo/scripts/dev.sh" "$@" > "$T/out" 2>&1 || rc=$?
}
caps='--memory 2g --memory-swap 2g --pids-limit 4096'

# Every `podman run` and `podman build` the command made, and whether each
# carries its caps.
check_calls() {
  local what=$1 runs builds bare
  runs=$(grep -c '^run ' "$T/calls" || true)
  builds=$(grep -c '^build ' "$T/calls" || true)
  if [ "$runs" -eq 0 ] && [ "$builds" -eq 0 ]; then
    bad "$what: no podman run or build was recorded (rc=$rc): $(head -c 300 "$T/out")"
    return
  fi
  bare=$(grep '^run ' "$T/calls" | grep -vF -- "run $caps " || true)
  if [ -n "$bare" ]; then bad "$what: a podman run without the caps: $(echo "$bare" | head -1)"
  else ok "$what: each of $runs podman run carries $caps"; fi
  bare=$(grep '^build ' "$T/calls" | grep -vF -- '--memory 4g' || true)
  if [ -n "$bare" ]; then bad "$what: a podman build without --memory 4g: $(echo "$bare" | head -1)"
  else ok "$what: each of $builds podman build carries --memory 4g"; fi
}

devsh shell true; check_calls "shell"
devsh cri;        check_calls "cri"

# act's job container: --container-options carries the caps.
devsh act ci.yml:simulation
if grep -q '^act ' "$T/calls"; then
  if grep '^act ' "$T/calls" | grep -qF -- "--container-options"; then
    opts=$(grep '^act ' "$T/calls" | head -1)
    case "$opts" in
      *"$caps"*) ok "act: the job container is given $caps" ;;
      *) bad "act: --container-options without the caps: $opts" ;;
    esac
  else
    bad "act: no --container-options: $(grep '^act ' "$T/calls" | head -1)"
  fi
else
  bad "act was not run (rc=$rc): $(head -c 300 "$T/out")"
fi

# A cap given in the environment is the one used.
: > "$T/calls"; rc=0
env PATH="$T/bin:$PATH" CONTAINER_ENGINE=podman CONTAINER_MEMORY=512m XDG_RUNTIME_DIR="$T/run" \
  bash "$T/repo/scripts/dev.sh" shell true > "$T/out" 2>&1 || rc=$?
if grep -q '^run --memory 512m --memory-swap 512m ' "$T/calls"; then ok "CONTAINER_MEMORY=512m is the cap used"
else bad "CONTAINER_MEMORY=512m not used: $(grep '^run ' "$T/calls" | head -1)"; fi

exit "$failed"
