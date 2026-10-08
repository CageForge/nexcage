#!/usr/bin/env bash
# What each nexcage command costs on the Proxmox LXC backend, measured against
# the fake Proxmox tools of tests/sim. Per command:
#
#   wall_us    nexcage's wall time from exec to exit, taken inside the
#              namespace so that unshare and the mounts are not counted. The
#              fakes are small shell scripts, so this is nexcage plus a few
#              milliseconds for each tool it runs.
#   calls      how many times it ran pct, pvesh, pvesm, pveam, pveversion or zfs.
#              On a real node each of those is a Perl process that takes
#              0.3-1 s, so this is most of what a user waits for there. It does
#              not vary between runs, which makes it the number to gate on.
#   maxrss_kb  nexcage's peak resident memory, from one run under GNU time.
#
#   tests/perf/lxc_sim.sh [-n ITER] [-w WARMUP] [-p POP] [-b MB] [-o FILE]
#                         [-l LABEL | -x LABEL=BINARY -x LABEL=BINARY ...]
#
#   -n  measured passes over the whole command sequence (default 20)
#   -w  passes run first and not recorded (default 1)
#   -p  containers created before measuring, so `list` has rows (default 10)
#   -b  size of the OCI bundle's rootfs in MB, packed on every bundle create
#       (default 8)
#   -l  label for the samples of $NEXCAGE (default "run")
#   -x  a binary to measure and its label; give it more than once to compare
#       builds. Every pass runs each of them, in turn and in a rotating order,
#       against the same fake host, so a change in the machine's load lands on
#       all of them rather than on whichever ran during it.
#   -o  file the samples are appended to (default stdout)
#
# A sample is one tab-separated line: label, suite, op, metric, value.
# tests/perf/report.py summarises them and compares two labels.
#
# NEXCAGE and SIM_DIR as for tests/sim/run.sh. Measure ReleaseSafe builds: in
# a Debug build the allocator's own checks are much of what gets timed.
set -uo pipefail

ITER=20 WARMUP=1 POP=10 BUNDLE_MB=8 LABEL=run OUT=/dev/stdout
LABELS=() BINARIES=()
while getopts "n:w:p:b:l:x:o:h" opt; do
  case "$opt" in
    n) ITER=$OPTARG ;; w) WARMUP=$OPTARG ;; p) POP=$OPTARG ;;
    b) BUNDLE_MB=$OPTARG ;; l) LABEL=$OPTARG ;; o) OUT=$OPTARG ;;
    x) case "$OPTARG" in
         ?*=?*) LABELS+=("${OPTARG%%=*}"); BINARIES+=("${OPTARG#*=}") ;;
         *) echo "-x wants LABEL=BINARY" >&2; exit 2 ;;
       esac ;;
    h) sed -n '2,/^set -uo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) exit 2 ;;
  esac
done

[ "${#BINARIES[@]}" -gt 0 ] || { LABELS=("$LABEL"); BINARIES=("${NEXCAGE:-$(dirname "$0")/../../zig-out/bin/nexcage}"); }
# nexcage runs from the fake host's working directory, so no relative paths
for k in "${!BINARIES[@]}"; do
  b=${BINARIES[$k]}
  [ -x "$b" ] || { echo "no nexcage binary at '$b'" >&2; exit 2; }
  BINARIES[k]=$(realpath "$b")
  case "${BINARIES[$k]}/" in /tmp/*) echo "$b is under /tmp, which the tmpfs hides from nexcage" >&2; exit 2 ;; esac
done
NEXCAGE=${BINARIES[0]}

# The fake host: $SIM, $NEXCAGE, $TPL, reset_sim, cfg, nexcage_ns
source "$(dirname "$0")/../sim/lib.sh"

# nexcage_ns runs whatever $NEXCAGE names inside the namespace, so a wrapper
# there can time the real binary without counting the namespace's setup.
PERF_DIR=$SIM/perf
mkdir -p "$PERF_DIR"
cat > "$PERF_DIR/nexcage-measured" <<'EOF'
#!/usr/bin/env bash
# Written by tests/perf/lxc_sim.sh. EPOCHREALTIME follows LC_NUMERIC, so its
# separator may be a comma.
if [ "$PERF_MODE" = rss ]; then
  exec /usr/bin/time -f %M -o "$PERF_OUT" "$PERF_REAL" "$@"
fi
t0=$EPOCHREALTIME
"$PERF_REAL" "$@"; rc=$?
t1=$EPOCHREALTIME
echo $(( 10#${t1//[.,]/} - 10#${t0//[.,]/} )) > "$PERF_OUT"
exit $rc
EOF
chmod +x "$PERF_DIR/nexcage-measured"
# Setup runs the first binary; each pass sets its own.
export PERF_REAL=${BINARIES[0]} PERF_OUT=$PERF_DIR/sample PERF_MODE=time
NEXCAGE=$PERF_DIR/nexcage-measured

RSS=1
[ -x /usr/bin/time ] || { RSS=0; echo "perf: no /usr/bin/time, so no maxrss_kb" >&2; }

RECORD=0
emit() { printf '%s\tlxc-sim\t%s\t%s\t%s\n' "$LABEL" "$1" "$2" "$3" >> "$OUT"; }
# measure OP ARGS...: run `nexcage ARGS` and, when recording, emit its samples.
# A command that fails aborts the run: the cost of an error path is not the
# cost of the command.
measure() {
  local op=$1 before calls; shift
  before=$(wc -l < "$S/calls")
  rm -f "$PERF_OUT"
  if ! nexcage_ns "$@" > "$S/out" 2> "$S/err"; then
    echo "perf: 'nexcage $*' failed; stderr:" >&2
    sed 's/^/    /' "$S/err" | tail -20 >&2
    exit 1
  fi
  calls=$(( $(wc -l < "$S/calls") - before ))
  [ "$RECORD" = 1 ] || return 0
  case "$PERF_MODE" in
    rss)  emit "$op" maxrss_kb "$(tail -n1 "$PERF_OUT")" ;;
    time) emit "$op" wall_us "$(cat "$PERF_OUT")"; emit "$op" calls "$calls" ;;
  esac
}
quiet() { nexcage_ns "$@" > /dev/null 2>&1 || { echo "perf: setup step 'nexcage $*' failed" >&2; exit 1; }; }

# One pass over the lifecycle with binary number $2. Names carry the pass and
# the binary, so no pass can collide with what another left behind.
lifecycle() {
  local i=$2-$1
  PERF_REAL=${BINARIES[$2]} LABEL=${LABELS[$2]}
  measure version       version
  measure list          list
  measure create        create --name "pc-$i" "$TPL"
  measure state         state "pc-$i"
  measure start         start "pc-$i"
  measure state-running state "pc-$i"
  measure exec          exec "pc-$i" true
  measure kill          kill "pc-$i" SIGCONT
  measure stop          stop "pc-$i"
  measure snapshot      snapshot "pc-$i" perf
  measure snapshots     snapshots "pc-$i"
  measure rollback      rollback "pc-$i" perf
  measure delsnapshot   delsnapshot "pc-$i" perf
  measure delete        delete "pc-$i"
  measure run           run --name "pr-$i" "$TPL"
  quiet stop "pr-$i"; quiet delete "pr-$i"
  measure create-bundle create --name "pb-$i" /tmp/nexcage-bundles/perf
  quiet delete "pb-$i"
}

reset_sim
cfg '{"network":{"bridge":"vmbr50"},"proxmox":{"storage":"local-lvm","rootfs_size_gb":2}}'

# The bundle: a small tree of files plus incompressible data, so packing it
# costs what packing a real rootfs of that size would.
R=$S/bundles/perf/rootfs
mkdir -p "$R/bin" "$R/etc"
for j in $(seq 1 200); do echo "file $j" > "$R/etc/f$j"; done
head -c "$((BUNDLE_MB * 1024 * 1024))" /dev/urandom > "$R/bin/payload"
printf '#!/bin/sh\n' > "$R/bin/busybox"; chmod 755 "$R/bin/busybox"
ln -s busybox "$R/bin/sh"
cat > "$S/bundles/perf/config.json" <<'JSON'
{"ociVersion":"1.0.2","hostname":"perf","process":{"args":["/bin/sh"],"cwd":"/"},"root":{"path":"rootfs"},
 "linux":{"namespaces":[{"type":"pid"}]}}
JSON

for j in $(seq 1 "$POP"); do quiet create --name "pop-$j" "$TPL"; done

# every_binary PASS: one lifecycle per binary, starting with a different one
# on each pass.
every_binary() {
  local k n=${#BINARIES[@]}
  for k in $(seq 0 $((n - 1))); do lifecycle "$1" $(( (k + ${2:-0}) % n )); done
}

echo "perf: lxc-sim (${LABELS[*]}), $POP containers listed, ${BUNDLE_MB} MB bundle, $WARMUP warm-up + $ITER measured passes" >&2
if [ "$RSS" = 1 ]; then
  PERF_MODE=rss RECORD=1
  every_binary rss
fi
PERF_MODE=time RECORD=0
for i in $(seq 1 "$WARMUP"); do every_binary "w$i"; done
RECORD=1
for i in $(seq 1 "$ITER"); do every_binary "$i" "$i"; done
echo "perf: lxc-sim done" >&2
