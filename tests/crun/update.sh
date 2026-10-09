#!/bin/sh
# `update`'s value flags reach the container's cgroup on the crun backend (#359),
# and a command after create finds that backend without --runtime (#372).
#
# The flags are nexcage's own code: src/main.zig maps each one to crun's
# section and field, src/cli/update.zig turns a size into bytes, and
# libcrun_container_update_from_values applies them. An engine's in-place
# resize takes the other path, `update --resources=-`, which libcrun reads
# itself; tests/cri/pod_on_nexcage.sh covers that one. Nothing ran this one
# against a cgroup.
#
# The kernel's word is the check: the files of the cgroup the container's
# process is in, read after each update. cgroup v2 only.
#
# Usage: update.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
ID=update-check-$$
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f /sys/fs/cgroup/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"

# The controllers the checks read, delegated into this container's own
# cgroup, one at a time: a write naming one the parent lacks fails whole.
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    for c in cpu cpuset memory pids; do
        echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
    done
fi

cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/"
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "$ID",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ]
  }
}
JSON

nx() { "$NEXCAGE" --runtime crun "$@"; }
cleanup() { cd /; nx delete --force "$ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

cd /
nx create --bundle "$BUNDLE" "$ID" >/dev/null 2>&1 || fail "create"
nx start "$ID" >/dev/null 2>&1 || fail "start"
pid=$(nx state "$ID" 2>/dev/null | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
[ -n "$pid" ] && [ -d "/proc/$pid" ] || fail "no running process for $ID (state gave pid '$pid')"
cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ -f "$cg/memory.max" ] || fail "no memory.max in $cg: the memory controller is not there"
echo "ok: $ID runs as PID $pid in $cg"

upd() { nx update "$@" "$ID" 2>/tmp/update.err || fail "update $* failed: $(tail -1 /tmp/update.err)"; }
is() {  # <cgroup file> <expected> <what was asked>
    got=$(cat "$cg/$1")
    [ "$got" = "$2" ] || fail "$3: $1 holds '$got', not '$2'"
    echo "ok: $3 -> $1 $got"
}

upd --memory 64M
is memory.max 67108864 "--memory 64M"
upd --memory-reservation 32M
is memory.low 33554432 "--memory-reservation 32M"
# cgroup v2 counts swap apart from memory; the flag gives the total, as runc's.
upd --memory 64M --memory-swap 192M
is memory.swap.max 134217728 "--memory 64M --memory-swap 192M"
upd --pids-limit 123
is pids.max 123 "--pids-limit 123"
upd --cpu-quota 25000 --cpu-period 100000
is cpu.max "25000 100000" "--cpu-quota 25000 --cpu-period 100000"
upd --cpuset-cpus 0
is cpuset.cpus 0 "--cpuset-cpus 0"

# libcrun turns shares into cpu.weight by a formula of its own, so the
# expected value is the one libcrun writes for the same shares in a
# linux.resources document -- the path an engine takes.
resources() { printf '{"cpu":{"shares":%s}}' "$1" | nx update --resources - "$ID" >/dev/null 2>&1 || fail "update --resources (the reference)"; }
resources 2;   low=$(cat "$cg/cpu.weight")
resources 512; want=$(cat "$cg/cpu.weight")
[ "$want" != "$low" ] || fail "shares 2 and 512 give the same cpu.weight ($low): the comparison would prove nothing"
resources 2
upd --cpu-share 512
is cpu.weight "$want" "--cpu-share 512, as --resources gives it"
upd --cpu-shares 2
is cpu.weight "$low" "--cpu-shares 2, runc's spelling"

# What cgroup v2 has no file for is refused, not dropped.
if nx update --kernel-memory 64M "$ID" >/dev/null 2>/tmp/update.err; then
    fail "--kernel-memory was accepted on cgroup v2, where there is nothing to set"
fi
echo "ok: --kernel-memory is refused on cgroup v2: $(tail -1 /tmp/update.err)"

# After create the container decides its backend, not the configuration
# (#372). This image routes nothing to crun, so without --runtime these went
# to the Proxmox backend, which does not have the container.
"$NEXCAGE" state "$ID" >/dev/null 2>/tmp/state.err || fail "state without --runtime missed the crun container: $(tail -1 /tmp/state.err)"
echo "ok: state without --runtime finds the crun container"
if "$NEXCAGE" --runtime lxc state "$ID" >/dev/null 2>/tmp/state.err; then
    fail "--runtime lxc was obeyed for a container on the crun backend"
fi
grep -q "is a container on the crun backend" /tmp/state.err || fail "--runtime lxc was refused without saying why: $(tail -1 /tmp/state.err)"
echo "ok: --runtime lxc on a crun container is refused"

echo "PASS: update's flags reach the container's cgroup"
