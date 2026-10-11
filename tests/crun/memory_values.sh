#!/bin/sh
# Memory values libcrun would overflow on are refused before it sees them, and
# `delete --force` removes the cgroup a create that never finished left.
#
# libcrun is compiled with UBSan in trap mode (build.zig), so an int64
# overflow in it kills the root process with SIGILL. write_memory_swap
# computes swap minus limit, and a bundle with a limit of
# -9223372036854775808 and swap 1 made create die half way (exit 132), after
# the container's cgroup existed and before the status file did; delete
# --force then said 0 and left the cgroup, one per attempt. The same document
# through update died after memory.max had been rewritten to max.
#
# The kernel's files are the check: the cgroup directory, memory.max, and
# the processes in a cgroup that must be left alone. cgroup v2 only.
#
# Usage: memory_values.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
ID=memory-values-$$
CG=/sys/fs/cgroup

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f $CG/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"

if [ -w $CG/cgroup.subtree_control ]; then
    mkdir -p $CG/init 2>/dev/null || true
    for p in $(cat $CG/cgroup.procs 2>/dev/null); do
        echo "$p" > $CG/init/cgroup.procs 2>/dev/null || true
    done
    for c in memory pids; do
        echo "+$c" > $CG/cgroup.subtree_control 2>/dev/null || true
    done
fi

spec() {  # <memory object>
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
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ],
    "resources": { "memory": $1 }
  }
}
JSON
}

nx() { "$NEXCAGE" --runtime crun "$@"; }
busy=
cleanup() {
    cd /
    [ -z "$busy" ] || kill "$busy" 2>/dev/null || true
    for id in "$ID" "$ID-c" "$ID-u" "$ID-b" "$ID-p"; do
        nx delete --force "$id" >/dev/null 2>&1 || true
        rmdir "$CG/$id" 2>/dev/null || true
        rm -rf "/run/crun/$id"
    done
}
trap cleanup EXIT
cd /

# 1. create: refused before libcrun, and nothing is left.
spec '{ "limit": -9223372036854775808, "swap": 1 }'
rc=0; nx create --bundle "$BUNDLE" "$ID-c" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "create with memory.limit -9223372036854775808 exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
grep -q "memory.limit is -9223372036854775808" /tmp/memory.err || fail "the refusal does not name the value: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "/run/crun/$ID-c" ] || fail "a refused create left /run/crun/$ID-c"
[ ! -e "$CG/$ID-c" ] || fail "a refused create left the cgroup $CG/$ID-c"
echo "ok: create with memory.limit INT64_MIN exits 2 and leaves nothing"

# 2. update: refused, memory.max as it was.
spec '{ "limit": 67108864 }'
nx create --bundle "$BUNDLE" "$ID-u" >/dev/null 2>&1 || fail "create"
nx start "$ID-u" >/dev/null 2>&1 || fail "start"
pid=$(nx state "$ID-u" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
cg=$CG$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "memory.max is $(cat "$cg/memory.max") after create, not 67108864"
rc=0; printf '{"memory":{"limit":-9223372036854775808,"swap":1}}' | nx update --resources - "$ID-u" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "update --resources with memory.limit INT64_MIN exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "a refused update changed memory.max to $(cat "$cg/memory.max")"
rc=0; nx update --memory -1 --memory-swap 9223372036854775807 "$ID-u" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "update --memory -1 --memory-swap 9223372036854775807 exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "a refused update changed memory.max to $(cat "$cg/memory.max")"
echo "ok: update with values libcrun would overflow on exits 2, memory.max still 67108864"

# 3. What a create killed half way leaves: libcrun's state directory with the
# config it kept and no status file, and the default cgroup. delete --force
# removes the cgroup as well as the directory.
leftover() {  # <id> <linux object>: the state and cgroup of an unfinished create
    mkdir -p "/run/crun/$1" "$CG/$1"
    printf '{"ociVersion":"1.0.0","linux":%s}' "$2" > "/run/crun/$1/config.json"
}
leftover "$ID" '{"namespaces":[{"type":"pid"}]}'
rc=0; nx delete --force "$ID" 2>/tmp/memory.err || rc=$?
[ "$rc" = 0 ] || fail "delete --force of an unfinished create exited $rc: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "/run/crun/$ID" ] || fail "delete --force left /run/crun/$ID"
[ ! -e "$CG/$ID" ] || fail "delete --force left the cgroup $CG/$ID that the unfinished create made"
echo "ok: delete --force of an unfinished create removes its cgroup"

# ... but never a cgroup with a process in it: nothing proves it is this
# container's, so it is left, and so is the process.
leftover "$ID-b" '{}'
sleep 300 &
busy=$!
echo "$busy" > "$CG/$ID-b/cgroup.procs"
rc=0; nx delete --force "$ID-b" 2>/tmp/memory.err || rc=$?
[ "$rc" = 0 ] || fail "delete --force exited $rc: $(tr '\n' ' ' < /tmp/memory.err)"
[ -d "$CG/$ID-b" ] || fail "delete --force removed a cgroup that had a process in it"
kill -0 "$busy" 2>/dev/null || fail "delete --force killed a process in a cgroup it could not prove its own"
grep -q "left in place" /tmp/memory.err || fail "the cgroup left in place is not named: $(tr '\n' ' ' < /tmp/memory.err)"
echo "$busy" > "$CG/init/cgroup.procs" 2>/dev/null || echo "$busy" > "$CG/cgroup.procs"
kill "$busy"; busy=
echo "ok: a leftover cgroup with a process in it is left, and named"

# ... nor one the kept config does not point at.
leftover "$ID-p" '{"cgroupsPath":"/elsewhere"}'
nx delete --force "$ID-p" >/dev/null 2>&1 || fail "delete --force of an unfinished create with a cgroupsPath"
[ -d "$CG/$ID-p" ] || fail "delete --force removed $CG/$ID-p, which the container's cgroupsPath does not name"
echo "ok: with a cgroupsPath in the kept config, $CG/<id> is not touched"

echo "PASS: memory values are checked before libcrun, and an unfinished create is cleaned up"
