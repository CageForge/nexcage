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
# The checks hold for what libcrun is given: it gets the bytes nexcage read,
# not the bundle's file to read again. And for how libcrun reads them: its
# parser ends a key at a NUL and keeps the last of two keys that are then the
# same, so "limit\u0000" after "limit" was the limit libcrun overflowed on,
# while the check read the first.
#
# The kernel's files are the check: the cgroup directory, memory.max, and
# the processes in a cgroup that must be left alone. cgroup v2 only.
#
# The cleanup is asked for as an engine asks: no --runtime, so it is what the
# killed create left on disk that has to send the id to libcrun. The routing
# for an engine's create is /etc/nexcage/config.json, as on a node, so run
# this in a throwaway container.
#
# Usage: memory_values.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
ID=memory-values-$$
CG=/sys/fs/cgroup
WORK=$(mktemp -d)

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f $CG/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"
[ ! -e /etc/nexcage/config.json ] || fail "/etc/nexcage/config.json exists: run this in a throwaway container"

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
# An engine names no backend: containerd's shim and conmon send the command
# with --root and --log, and nexcage goes by the routing for a create and by
# what is on disk for everything else.
eng() { "$NEXCAGE" "$@"; }
ROOT=/run/memory-values-root
busy=
feeder=
held=
cleanup() {
    cd /
    [ -z "$busy" ] || kill "$busy" 2>/dev/null || true
    [ -z "$feeder" ] || kill "$feeder" 2>/dev/null || true
    [ -z "$held" ] || kill -9 $held 2>/dev/null || true
    for id in "$ID" "$ID-c" "$ID-f" "$ID-u" "$ID-b" "$ID-p" "$ID-s" "$ID-g" "$ID-k" "$ID-r"; do
        nx delete --force "$id" >/dev/null 2>&1 || true
        nx --root "$ROOT" delete --force "$id" >/dev/null 2>&1 || true
        rmdir "$CG/$id" 2>/dev/null || true
        rm -rf "/run/crun/$id"
    done
    rm -rf "$WORK" "$ROOT"
    rm -f /etc/nexcage/config.json
}
trap cleanup EXIT
mkdir -p /etc/nexcage
echo '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' > /etc/nexcage/config.json
cd /

# 1. create: refused before libcrun, and nothing is left.
spec '{ "limit": -9223372036854775808, "swap": 1 }'
rc=0; nx create --bundle "$BUNDLE" "$ID-c" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "create with memory.limit -9223372036854775808 exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
grep -q "memory.limit is -9223372036854775808" /tmp/memory.err || fail "the refusal does not name the value: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "/run/crun/$ID-c" ] || fail "a refused create left /run/crun/$ID-c"
[ ! -e "$CG/$ID-c" ] || fail "a refused create left the cgroup $CG/$ID-c"
echo "ok: create with memory.limit INT64_MIN exits 2 and leaves nothing"

# ... and so with the value behind a second "limit" that ends in a NUL.
spec '{ "limit": 67108864, "limit\u0000": -9223372036854775808, "swap": 1 }'
rc=0; nx create --bundle "$BUNDLE" "$ID-c" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "create with a second memory.limit behind \"limit\\u0000\" exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
# limit\u0000 in the refusal, with stderr's backslash written \\
grep -qF 'has a NUL in the key at linux.resources.memory.limit\\u0000:' /tmp/memory.err || fail "the refusal does not name the key: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "/run/crun/$ID-c" ] || fail "a refused create left /run/crun/$ID-c"
[ ! -e "$CG/$ID-c" ] || fail "a refused create left the cgroup $CG/$ID-c"
echo "ok: create with memory.limit INT64_MIN behind \"limit\\u0000\" exits 2 and leaves nothing"

# ... and what passed the check is what libcrun creates from. A config.json
# that is a FIFO answers the first read with a spec that passes, and every
# later one with the spec above: handed the path, libcrun read it again, to
# parse it and to copy it into its state, and died of the trap the check is
# there to prevent. In a bundle of its own, so no other step or script ever
# writes into a FIFO; the rootfs is the shared one, by its absolute path.
mkdir "$WORK/fifo"
as_own() { sed "s|\"path\": \"rootfs\"|\"path\": \"$BUNDLE/rootfs\"|" "$BUNDLE/config.json"; }
checked=$(spec '{ "limit": 67108864 }'; as_own)
swapped=$(spec '{ "limit": -9223372036854775808, "swap": 1 }'; as_own)
mkfifo "$WORK/fifo/config.json"
# printf is the shell's own, so the open that waits for a reader is in this
# process, and killing it leaves nothing blocked. A reader that closes early
# must not end it: SIGPIPE is ignored. The later answers wait for nexcage to
# close the FIFO after the first, as read in /proc: a writer that opened it
# while nexcage still read ran the two specs together into one document,
# which is not JSON, and failed this check on correct code. A second open,
# libcrun's, still finds them.
sh -c 'trap "" PIPE
held() { for fd in /proc/[0-9]*/fd/*; do [ "$(readlink "$fd" 2>/dev/null)" = "$1" ] && return 0; done; return 1; }
printf "%s" "$1" > "$3"
n=0; while held "$3" && [ $n -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
while :; do printf "%s" "$2" > "$3" 2>/dev/null; done' \
    sh "$checked" "$swapped" "$WORK/fifo/config.json" &
feeder=$!
rc=0; nx create --bundle "$WORK/fifo" "$ID-f" 2>/tmp/memory.err || rc=$?
kill "$feeder" 2>/dev/null || true; feeder=
[ "$rc" = 0 ] || fail "create from a config.json that changed after nexcage read it exited $rc: libcrun read the file again and got what nexcage never checked: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
pid=$(nx state "$ID-f" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
[ -n "$pid" ] || fail "state $ID-f names no pid after create"
cg=$CG$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "the container from a FIFO config.json has memory.max $(cat "$cg/memory.max"), not the checked spec's 67108864"
grep -q '"limit": *67108864' "/run/crun/$ID-f/config.json" || fail "libcrun kept a config other than the one nexcage checked: $(head -c 300 "/run/crun/$ID-f/config.json")"
nx delete --force "$ID-f" >/dev/null 2>&1 || fail "delete --force $ID-f"
echo "ok: create hands libcrun the spec it checked, and libcrun does not read the bundle's file again"

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
rc=0; printf '%s' '{"memory":{"limit":67108864,"limit\u0000":-9223372036854775808,"swap":1}}' | nx update --resources - "$ID-u" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "update --resources with memory.limit INT64_MIN behind \"limit\\u0000\" exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
grep -qF 'has a NUL in the key at memory.limit\\u0000:' /tmp/memory.err || fail "the refused update does not name the key: $(tr '\n' ' ' < /tmp/memory.err)"
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "a refused update changed memory.max to $(cat "$cg/memory.max")"
rc=0; nx update --memory -1 --memory-swap 9223372036854775807 "$ID-u" 2>/tmp/memory.err || rc=$?
[ "$rc" = 2 ] || fail "update --memory -1 --memory-swap 9223372036854775807 exited $rc, not 2: $(tr '\n' ' ' < /tmp/memory.err | head -c 300)"
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "a refused update changed memory.max to $(cat "$cg/memory.max")"
echo "ok: update with values libcrun would overflow on exits 2, memory.max still 67108864"

# 3. What a create killed half way leaves: libcrun's state directory with the
# config it kept and no status file, and the default cgroup. An engine's
# delete --force removes the cgroup as well as the directory.
#
# A create killed for real first. libcrun runs a bundle's createRuntime hooks
# once the container's cgroup holds its init and before it writes the status
# file, so a hook that waits holds the create there; it writes the create's
# PID and its own, and the create is killed with SIGKILL, as the OOM killer
# would. Under the default root and under an engine's --root.
held_spec() {  # <id> <file the hook writes the PIDs to>
    sed -e "s|@ID@|$1|" -e "s|@PIDS@|$2|" > "$BUNDLE/config.json" <<'JSON'
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
  "hostname": "@ID@",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "hooks": { "createRuntime": [ { "path": "/bin/sh",
    "args": [ "sh", "-c", "echo \"$PPID $$\" > @PIDS@; exec sleep 300" ] } ] },
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ]
  }
}
JSON
}
killed_create() {  # <state root> <id> [global options]: an engine's create, killed half way
    state=$1 id=$2; shift 2
    held_spec "$id" "$WORK/held.$id"
    eng "$@" create --bundle "$BUNDLE" "$id" >"$WORK/create.out" 2>&1 &
    creating=$!
    n=0; until [ -s "$WORK/held.$id" ]; do
        n=$((n + 1))
        [ "$n" -le 300 ] || fail "the create of $id never reached its createRuntime hook: $(tr '\n' ' ' < "$WORK/create.out" | head -c 300)"
        sleep 0.1
    done
    read -r caller hook < "$WORK/held.$id"
    held="$caller $hook"
    kill -9 "$caller" "$hook"
    wait "$creating" 2>/dev/null || true
    held=
    # The container's init loses its runtime with it and exits; until it has,
    # its cgroup cannot be removed by anyone.
    n=0; while [ -s "$CG/$id/cgroup.procs" ] && [ "$n" -lt 100 ]; do n=$((n + 1)); sleep 0.1; done
    [ -f "$state/$id/config.json" ] && [ ! -e "$state/$id/status" ] && [ -d "$CG/$id" ] || \
        fail "the create killed in its hook did not leave what this step is about (config, no status, $CG/$id): $(ls -A "$state/$id" 2>&1 | tr '\n' ' ')"
}
killed_create /run/crun "$ID-k"
rc=0; eng delete --force "$ID-k" 2>/tmp/memory.err || rc=$?
[ "$rc" = 0 ] || fail "an engine's delete --force of a killed create exited $rc: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "/run/crun/$ID-k" ] || fail "an engine's delete --force of a killed create left /run/crun/$ID-k: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "$CG/$ID-k" ] || fail "an engine's delete --force of a killed create left its cgroup $CG/$ID-k: $(tr '\n' ' ' < /tmp/memory.err)"
echo "ok: a create killed half way is removed, state and cgroup, by an engine's delete --force"
killed_create "$ROOT" "$ID-r" --root "$ROOT"
rc=0; eng --root "$ROOT" delete --force "$ID-r" 2>/tmp/memory.err || rc=$?
[ "$rc" = 0 ] || fail "an engine's delete --force under --root of a killed create exited $rc: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "$ROOT/$ID-r" ] || fail "an engine's delete --force under --root of a killed create left $ROOT/$ID-r: $(tr '\n' ' ' < /tmp/memory.err)"
[ ! -e "$CG/$ID-r" ] || fail "an engine's delete --force under --root of a killed create left its cgroup $CG/$ID-r: $(tr '\n' ' ' < /tmp/memory.err)"
echo "ok: and so under --root"

# Then the same leftovers made by hand, for the cases a kill cannot pick.
leftover() {  # <id> <linux object>: the state and cgroup of an unfinished create
    mkdir -p "/run/crun/$1" "$CG/$1"
    printf '{"ociVersion":"1.0.0","linux":%s}' "$2" > "/run/crun/$1/config.json"
}
leftover "$ID" '{"namespaces":[{"type":"pid"}]}'
rc=0; eng delete --force "$ID" 2>/tmp/memory.err || rc=$?
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
rc=0; eng delete --force "$ID-b" 2>/tmp/memory.err || rc=$?
[ "$rc" = 0 ] || fail "delete --force exited $rc: $(tr '\n' ' ' < /tmp/memory.err)"
[ -d "$CG/$ID-b" ] || fail "delete --force removed a cgroup that had a process in it"
kill -0 "$busy" 2>/dev/null || fail "delete --force killed a process in a cgroup it could not prove its own"
grep -q "left in place" /tmp/memory.err || fail "the cgroup left in place is not named: $(tr '\n' ' ' < /tmp/memory.err)"
echo "$busy" > "$CG/init/cgroup.procs" 2>/dev/null || echo "$busy" > "$CG/cgroup.procs"
kill "$busy"; busy=
echo "ok: a leftover cgroup with a process in it is left, and named"

# ... nor one the kept config does not point at.
leftover "$ID-p" '{"cgroupsPath":"/elsewhere"}'
eng delete --force "$ID-p" >/dev/null 2>&1 || fail "delete --force of an unfinished create with a cgroupsPath"
[ -d "$CG/$ID-p" ] || fail "delete --force removed $CG/$ID-p, which the container's cgroupsPath does not name"
echo "ok: with a cgroupsPath in the kept config, $CG/<id> is not touched"

# ... nor under --systemd-cgroup, which an engine sends with every command:
# libcrun then puts a container in a systemd scope and makes nothing at the
# root, so $CG/<id> cannot be what the create left.
leftover "$ID-s" '{}'
eng delete --force --systemd-cgroup "$ID-s" >/dev/null 2>&1 || fail "delete --force --systemd-cgroup of an unfinished create"
[ ! -e "/run/crun/$ID-s" ] || fail "delete --force --systemd-cgroup left /run/crun/$ID-s"
[ -d "$CG/$ID-s" ] || fail "delete --force --systemd-cgroup removed $CG/$ID-s, which a create under systemd does not make"
echo "ok: under --systemd-cgroup, $CG/<id> is not touched"

# ... and so with the flag before the command, where go-runc and conmon put
# it: dropped there, it left delete on the cgroupfs branch.
leftover "$ID-g" '{}'
eng --systemd-cgroup delete --force "$ID-g" >/dev/null 2>&1 || fail "--systemd-cgroup delete --force of an unfinished create"
[ ! -e "/run/crun/$ID-g" ] || fail "--systemd-cgroup delete --force left /run/crun/$ID-g"
[ -d "$CG/$ID-g" ] || fail "--systemd-cgroup before delete --force removed $CG/$ID-g, which a create under systemd does not make"
echo "ok: with --systemd-cgroup before the command, $CG/<id> is not touched either"

echo "PASS: memory values are checked before libcrun, and an unfinished create is cleaned up"
