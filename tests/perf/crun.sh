#!/usr/bin/env bash
# What a container's lifecycle costs on nexcage's crun backend, next to the
# same lifecycle driven through crun's own binary. Both end in libcrun, so the
# difference is nexcage's: argument parsing, config and routing, logging, and
# whatever it does around each call. The crun binary is the distribution's, not
# the vendored libcrun nexcage links, so small differences can be the version.
#
# Runs as root in a privileged container with its own cgroup namespace, the
# way tests/crun/ps.sh does; `scripts/dev.sh perf` starts it in the crun image:
#
#   tests/perf/crun.sh [-n ITER] [-w WARMUP] [-l LABEL] [-o FILE]
#
# BUNDLE   directory holding a rootfs/ with busybox (default /bundle); the
#          script writes its config.json
# NEXCAGE, CRUN  the two binaries (default /usr/local/bin/nexcage, /usr/bin/crun)
#
# Samples, one per line: label, suite (nexcage-crun or crun), op, metric, value.
set -uo pipefail

ITER=20 WARMUP=2 LABEL=run OUT=/dev/stdout
while getopts "n:w:l:o:h" opt; do
  case "$opt" in
    n) ITER=$OPTARG ;; w) WARMUP=$OPTARG ;; l) LABEL=$OPTARG ;; o) OUT=$OPTARG ;;
    h) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) exit 2 ;;
  esac
done

BUNDLE=${BUNDLE:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
CRUN=${CRUN:-/usr/bin/crun}
# nexcage's crun backend keeps its state in /run/crun; the reference gets its
# own root so the two never see each other's containers.
NX_ROOT=/run/crun
REF_ROOT=/run/crun-perf-ref
ERR=$(mktemp)

fail() { echo "perf: $*" >&2; exit 1; }
[ -e "$BUNDLE/rootfs/bin/sh" ] || fail "no rootfs in $BUNDLE: put busybox there first"
[ "$(id -u)" = 0 ] || fail "run as root, in a privileged container"

# Controllers for the containers' cgroups, as in tests/crun/ps.sh
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
  mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
  for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
    echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
  done
  for c in cpu memory pids; do
    echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
  done
fi

cat > "$BUNDLE/config.json" <<'JSON'
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "3600" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/"
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "perf",
  "mounts": [
    { "destination": "/proc", "type": "proc", "source": "proc" },
    { "destination": "/dev", "type": "tmpfs", "source": "tmpfs",
      "options": [ "nosuid", "strictatime", "mode=755", "size=65536k" ] }
  ],
  "linux": {
    "namespaces": [
      { "type": "pid" }, { "type": "ipc" }, { "type": "uts" },
      { "type": "mount" }, { "type": "network" }
    ]
  }
}
JSON

nx()  { "$NEXCAGE" --runtime crun "$@"; }
ref() { "$CRUN" --root "$REF_ROOT" "$@"; }

RECORD=0
# measure SUITE OP CMD...: time CMD; a failure ends the run with its stderr.
measure() {
  local suite=$1 op=$2 t0 t1; shift 2
  t0=$EPOCHREALTIME
  "$@" > /dev/null 2> "$ERR" || { sed 's/^/    /' "$ERR" | tail -20 >&2; fail "$suite $op failed: $*"; }
  t1=$EPOCHREALTIME
  [ "$RECORD" = 1 ] || return 0
  printf '%s\t%s\t%s\twall_us\t%s\n' "$LABEL" "$suite" "$op" \
    "$(( 10#${t1//[.,]/} - 10#${t0//[.,]/} ))" >> "$OUT"
}
# Not timed: SIGKILL is asynchronous, and delete needs the container stopped.
wait_stopped() {
  local root=$1 id=$2 i
  for i in $(seq 1 100); do
    "$CRUN" --root "$root" state "$id" 2>/dev/null | grep -q '"status": *"stopped"' && return 0
    sleep 0.05
  done
  fail "$id did not stop after SIGKILL"
}

# One container through its whole life on one runtime. $1 is nx or ref.
lifecycle() {
  local rt=$1 id=$2 suite root
  case "$rt" in nx) suite=nexcage-crun root=$NX_ROOT ;; ref) suite=crun root=$REF_ROOT ;; esac
  cd /
  measure "$suite" features "$rt" features
  measure "$suite" create   "$rt" create --bundle "$BUNDLE" "$id"
  measure "$suite" start    "$rt" start "$id"
  measure "$suite" state    "$rt" state "$id"
  measure "$suite" ps       "$rt" ps --format json "$id"
  measure "$suite" exec     "$rt" exec "$id" /bin/true
  measure "$suite" kill     "$rt" kill "$id" 9
  wait_stopped "$root" "$id"
  measure "$suite" delete   "$rt" delete "$id"
}

cleanup() {
  local d
  for d in "$NX_ROOT"/perf-*/; do [ -d "$d" ] && nx delete --force "$(basename "$d")" >/dev/null 2>&1; done
  for d in "$REF_ROOT"/*/; do [ -d "$d" ] && ref delete --force "$(basename "$d")" >/dev/null 2>&1; done
  rm -f "$ERR"
}
trap cleanup EXIT

echo "perf: crun, $("$CRUN" --version | head -1) as the reference, $WARMUP warm-up + $ITER measured passes" >&2
# The two runtimes take turns, so drift in the machine's load lands on both.
for i in $(seq 1 "$WARMUP"); do lifecycle nx "perf-w$i"; lifecycle ref "ref-w$i"; done
RECORD=1
for i in $(seq 1 "$ITER"); do
  if [ $((i % 2)) = 0 ]; then lifecycle nx "perf-$i"; lifecycle ref "ref-$i"
  else lifecycle ref "ref-$i"; lifecycle nx "perf-$i"; fi
done
echo "perf: crun done" >&2
