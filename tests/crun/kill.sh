#!/bin/sh
# `kill` on the crun backend sends the signal nexcage validated, and nothing
# else. libcrun parses a signal's text again, with rules of its own: names in
# upper case only, numbers with strtol, which stops at the first non-digit.
# nexcage used to check the text one way and hand libcrun the text itself, so
# `kill <id> usr1` -- a name in any case, as the help says -- failed with
# libcrun's "unknown signal", `1_5` passed as 15 and sent SIGHUP, and `0_9`
# passed as SIGKILL and sent nothing at all.
#
# The container's init records each signal it catches in a file in its root,
# which is the check: what arrived, not what nexcage said.
#
# Usage: kill.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
ID=kill-check-$$
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
SIG=$BUNDLE/rootfs/kill-check.sig

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
fi

# The init is PID 1 of its namespace, so a signal without a handler is
# dropped: each one the check sends has a trap that writes its name down.
cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sh", "-c", "for s in HUP TERM USR1 USR2; do trap \"echo \$s >> /kill-check.sig\" \$s; done; echo ready >> /kill-check.sig; while :; do sleep 1; done" ],
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
cleanup() { cd /; nx delete --force "$ID" >/dev/null 2>&1 || true; rm -f "$SIG"; }
trap cleanup EXIT

# Waits for the init to have written $1 as its last line, up to five seconds:
# a trap runs once the `sleep 1` in front of it returns.
caught() {
    i=0
    while [ $i -lt 50 ]; do
        [ "$(tail -n 1 "$SIG" 2>/dev/null)" = "$1" ] && return 0
        sleep 0.1; i=$((i + 1))
    done
    return 1
}

cd /
# The init runs as root with no capability at all (the spec names none), so
# it can write only what root owns: on a CI runner the rootfs directory
# belongs to the runner's user, and the init could not create the file there.
# The file is made here, by root, before the init starts.
rm -f "$SIG"; : > "$SIG"
nx create --bundle "$BUNDLE" "$ID" >/dev/null 2>&1 || fail "create"
nx start "$ID" >/dev/null 2>&1 || fail "start"
caught ready || fail "the init never got as far as setting its traps"
echo "ok: $ID runs, its traps are set"

# A name in lower case: the help promises any case.
rc=0; nx kill "$ID" usr1 2>/tmp/kill.err || rc=$?
[ "$rc" = 0 ] || fail "kill $ID usr1 exited $rc: $(tail -1 /tmp/kill.err)"
caught USR1 || fail "kill $ID usr1 exited 0 and the init caught nothing (last line: $(tail -n 1 "$SIG"))"
echo "ok: kill usr1 delivers SIGUSR1"

# Not numbers, whatever a lenient parser makes of them: refused before
# anything is sent, with the usage exit status.
for bad in 1_5 0_9 12x; do
    : > "$SIG"
    rc=0; nx kill "$ID" "$bad" 2>/tmp/kill.err || rc=$?
    [ "$rc" = 2 ] || fail "kill $ID $bad exited $rc, not 2 ($(tail -1 /tmp/kill.err))"
    sleep 1.5
    [ ! -s "$SIG" ] || fail "kill $ID $bad was refused, and the init still caught $(cat "$SIG")"
    [ "$(nx state "$ID" 2>/dev/null | sed -n 's/.*"status": *"\([a-z]*\)".*/\1/p')" = running ] || fail "the container is not running after kill $bad"
    echo "ok: kill $bad is refused with exit 2 and sends nothing"
done

# The forms an engine and a person use, delivered as themselves.
for sig in 12:USR2 SIGHUP:HUP TERM:TERM; do
    rc=0; nx kill "$ID" "${sig%%:*}" 2>/tmp/kill.err || rc=$?
    [ "$rc" = 0 ] || fail "kill $ID ${sig%%:*} exited $rc: $(tail -1 /tmp/kill.err)"
    caught "${sig#*:}" || fail "kill $ID ${sig%%:*} did not deliver SIG${sig#*:} (last line: $(tail -n 1 "$SIG"))"
    echo "ok: kill ${sig%%:*} delivers SIG${sig#*:}"
done

echo "PASS: kill sends the signal nexcage validated"
