#!/bin/sh
# `ps` reports the host PIDs in a container, and reports the same ones crun does.
#
# Kubernetes asks for this: the kubelet's containerd sends `ps --format json
# <id>` for a task's PID list. Until it existed nexcage answered `unknown
# command 'ps'`, containerd swallowed that without a word in its journal, and
# the pod ran anyway — so nothing short of recording the runtime's command lines
# showed it was being asked.
#
# The check that matters is the comparison: nexcage and crun, same container,
# same state root, same set of numbers. A list of plausible PIDs proves nothing
# on its own, because any list of numbers looks plausible.
#
# Usage: ps.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
ID=ps-check-$$
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
CRUN=${CRUN:-/usr/bin/crun}
ROOT=/run/crun

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    echo "+cpu +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi

# Three processes, so an answer of "one" would be wrong rather than merely short.
cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sh", "-c", "sleep 120 & sleep 120 & sleep 120" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/"
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "$ID",
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

cleanup() { cd /; "$NEXCAGE" --runtime crun delete --force "$ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

cd /
"$NEXCAGE" --runtime crun create --bundle "$BUNDLE" "$ID" >/dev/null 2>&1 || fail "create"
"$NEXCAGE" --runtime crun start "$ID" >/dev/null 2>&1 || fail "start"
# The shell has to get as far as starting its children.
sleep 2
echo "ok: a container with several processes is running"

json=$("$NEXCAGE" --runtime crun ps --format json "$ID" 2>/dev/null) || fail "ps --format json"
nx_pids=$(echo "$json" | tr -d ' ,[]' | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')
[ -n "$nx_pids" ] || { echo "$json" >&2; fail "ps --format json listed no PID"; }
echo "ok: ps --format json -> $nx_pids"

# Every number must be a process that exists, which a made-up list would fail.
for pid in $nx_pids; do
    [ -d "/proc/$pid" ] || fail "PID $pid from ps does not exist on the host"
done
echo "ok: every PID it reported is a live process"

# And the same numbers crun gives for the same container. This is the check:
# without it, any list of live PIDs on the host would pass the one above.
crun_json=$("$CRUN" --root "$ROOT" ps --format json "$ID" 2>/dev/null) || fail "crun ps (the control) failed"
crun_pids=$(echo "$crun_json" | tr -d ' ,[]' | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')
[ "$nx_pids" = "$crun_pids" ] || {
    echo "nexcage: $nx_pids" >&2
    echo "crun:    $crun_pids" >&2
    fail "nexcage and crun disagree about the container's processes"
}
echo "ok: the same PIDs crun reports for this container"

table=$("$NEXCAGE" --runtime crun ps "$ID" 2>/dev/null) || fail "ps (table)"
case "$table" in
    PID*) : ;;
    *) echo "$table" >&2; fail "the table form has no PID header" ;;
esac
tbl_pids=$(echo "$table" | grep -E '^[0-9]+$' | sort -n | tr '\n' ' ')
[ "$tbl_pids" = "$nx_pids" ] || fail "the two formats disagree: '$tbl_pids' and '$nx_pids'"
echo "ok: the table form lists the same PIDs"

echo "PASS: ps reports the container's processes, and crun agrees"
