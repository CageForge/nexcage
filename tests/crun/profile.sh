#!/bin/sh
# Isolation profiles on the crun backend (#315, ADR-005), read back from the
# kernel rather than from nexcage's log.
#
# A profile only narrows the engine's bundle: it drops capabilities, lowers
# limits, and refuses a bundle without what it requires. An engine names one by
# the program name, nexcage@<profile>, and only create reads it; later commands
# find the container without it. cgroup v2 only.
#
# Usage: profile.sh [bundle-dir]     (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
WORK=$(mktemp -d)
CFG=$WORK/config.json
ID=profile-check-$$

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f /sys/fs/cgroup/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    for c in memory pids; do
        echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
    done
fi

cat > "$CFG" <<'JSON'
{ "profiles": {
    "hardened": { "runtime": "crun", "crun": {
        "capabilities": { "drop": ["CAP_NET_RAW", "CAP_MKNOD"] },
        "limits": { "memory": "64M", "pids": 50 } } },
    "needs-seccomp": { "runtime": "crun", "crun": { "seccomp": "require" } },
    "needs-userns": { "runtime": "crun", "crun": { "user_namespace": "require" } } } }
JSON

# What an engine would hand over: a 1 GiB limit the profile lowers, with swap
# (memory plus swap) equal to it, which is containerd's way of saying no swap,
# and the capabilities a container usually gets, NET_RAW and MKNOD among them.
spec() {
    cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ],
    "env": [ "PATH=/bin:/usr/bin" ],
    "cwd": "/",
    "capabilities": {
      "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ]
    }
  },
  "root": { "path": "rootfs", "readonly": false },
  "hostname": "profile-check",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "linux": {
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ],
    "resources": { "memory": { "limit": 1073741824, "swap": 1073741824 } }
    $1
  }
  $2
}
JSON
}

# The program name names the profile, as an engine's BinaryName does.
ln -s "$NEXCAGE" "$WORK/nexcage@hardened"
nx() { "$NEXCAGE" --config "$CFG" "$@"; }
cleanup() { cd /; for id in "$ID" "$ID-s" "$ID-u" "$ID-a" "$ID-z" "$ID-c"; do nx delete --force "$id" >/dev/null 2>&1 || true; done; rm -rf "$WORK"; }
# The pid of a started container, from its state.
pid_of() { nx state "$1" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p'; }
trap cleanup EXIT
cd /

spec "" ""
"$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID" 2>"$WORK/err" || fail "create under nexcage@hardened: $(tail -1 "$WORK/err")"
nx start "$ID" 2>"$WORK/err" || fail "start: $(tail -1 "$WORK/err")"
# Without the profile and without --runtime: the container is found where it is.
state=$(nx state "$ID")
pid=$(echo "$state" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
[ -n "$pid" ] && [ -d "/proc/$pid" ] || fail "no running process for $ID (state: $state)"
echo "$state" | grep -q '"io.cageforge.nexcage.profile": *"hardened"' || fail "state does not report the profile: $state"
echo "ok: created under nexcage@hardened; state, called without it, reports the profile"

capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$pid/status")
bit() { echo $(( (0x$capbnd >> $1) & 1 )); }
[ "$(bit 13)" = 0 ] || fail "CAP_NET_RAW is still in the bounding set ($capbnd)"
[ "$(bit 27)" = 0 ] || fail "CAP_MKNOD is still in the bounding set ($capbnd)"
[ "$(bit 5)" = 1 ] || fail "CAP_KILL, which the profile does not drop, is gone ($capbnd)"
echo "ok: CapBnd $capbnd: NET_RAW and MKNOD dropped, KILL kept"

# An engine's exec carries the capabilities of the engine's own copy of the
# spec, from before the profile narrowed it: kubectl exec through containerd
# does. The process gets none the container was made without.
cat > "$WORK/process.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ],
  "args": [ "/bin/sh", "-c", "sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status" ],
  "capabilities": {
    "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }
JSON
capbnd=$(nx exec "$ID" --process "$WORK/process.json" 2>"$WORK/err") || fail "exec --process: $(tail -1 "$WORK/err")"
[ -n "$capbnd" ] || fail "exec --process printed no CapBnd"
[ "$(bit 13)" = 0 ] || fail "an exec'd process got CAP_NET_RAW back ($capbnd)"
[ "$(bit 27)" = 0 ] || fail "an exec'd process got CAP_MKNOD back ($capbnd)"
[ "$(bit 5)" = 1 ] || fail "an exec'd process lost CAP_KILL, which the container has ($capbnd)"
echo "ok: exec --process asking for NET_RAW and MKNOD gets CapBnd $capbnd"

# libcrun's parser ends a key at a NUL, and of two keys that are then the
# same it keeps the last. "capabilities\u0000" is what it applies, and the
# process spec had no "capabilities" for nexcage to cut.
cat > "$WORK/process-nul.json" <<'JSON'
{ "terminal": false, "user": { "uid": 0, "gid": 0 }, "cwd": "/",
  "env": [ "PATH=/bin:/usr/bin" ],
  "args": [ "/bin/sh", "-c", "sed -n 's/^CapBnd:[[:space:]]*//p' /proc/self/status" ],
  "capabilities\u0000": {
    "bounding": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "effective": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
    "permitted": [ "CAP_CHOWN", "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }
JSON
rc=0; capbnd=$(nx exec "$ID" --process "$WORK/process-nul.json" 2>"$WORK/err") || rc=$?
if [ "$rc" = 0 ]; then
    [ "$(bit 13)" = 0 ] || fail "an exec'd process got CAP_NET_RAW back through \"capabilities\\u0000\" (CapBnd $capbnd)"
    fail "exec --process with a NUL in a key ran (CapBnd $capbnd)"
fi
grep -q 'the process spec has a NUL in the key at capabilities\\u0000' "$WORK/err" || fail "the NUL refusal does not say where: $(tail -1 "$WORK/err")"
echo "ok: exec --process with \"capabilities\\u0000\" is refused"

cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "memory.max is $(cat "$cg/memory.max"), not the profile's 64M"
[ "$(cat "$cg/pids.max")" = 50 ] || fail "pids.max is $(cat "$cg/pids.max"), not the profile's 50"
echo "ok: memory.max 67108864 (the bundle asked 1G), pids.max 50 (the bundle set none)"
# Lowering the limit alone would have made the other 960M swap.
if [ -f "$cg/memory.swap.max" ]; then
    [ "$(cat "$cg/memory.swap.max")" = 0 ] || fail "memory.swap.max is $(cat "$cg/memory.swap.max"), and the bundle allowed no swap"
    echo "ok: memory.swap.max 0: no swap, as the bundle asked"
else
    echo "skipped: no memory.swap.max here (no swap accounting), so swap is not checked"
fi

# A second "process" behind a NUL: the profile checked the first, and
# libcrun, which reads "process\u0000" as "process" and keeps the last, would
# apply this one, NET_RAW and MKNOD included.
spec "" ', "process\u0000": { "terminal": false, "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sleep", "300" ], "env": [ "PATH=/bin:/usr/bin" ], "cwd": "/",
    "capabilities": { "bounding": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "effective": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ],
      "permitted": [ "CAP_KILL", "CAP_NET_RAW", "CAP_MKNOD" ] } }'
rc=0; "$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID-z" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-z" 2>"$WORK/err" || fail "a bundle with a NUL in a key was created, and start failed: $(tail -1 "$WORK/err")"
    capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$(pid_of "$ID-z")/status")
    [ "$(bit 13)" = 0 ] && [ "$(bit 27)" = 0 ] || fail "the second \"process\" behind a NUL was applied: CapBnd $capbnd holds NET_RAW or MKNOD, which the profile drops"
    fail "a bundle with a NUL in a key was created (CapBnd $capbnd)"
fi
grep -q 'has a NUL in the key at process\\u0000' "$WORK/err" || fail "the NUL refusal does not say where: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-z" ] || fail "a refused create left state behind"
echo "ok: a second \"process\" behind a NUL is refused, and nothing is created"

# libcrun reads capability names with libcap, which takes "cap_net_raw" and
# "27" for CAP_NET_RAW and CAP_MKNOD; the profile compares names.
spec "" ""
sed -i 's/"CAP_NET_RAW"/"cap_net_raw"/g; s/"CAP_MKNOD"/"27"/g' "$BUNDLE/config.json"
rc=0; "$WORK/nexcage@hardened" --config "$CFG" create --bundle "$BUNDLE" "$ID-c" 2>"$WORK/err" || rc=$?
if [ "$rc" = 0 ]; then
    nx start "$ID-c" 2>"$WORK/err" || fail "a bundle spelling capabilities as libcap does was created, and start failed: $(tail -1 "$WORK/err")"
    capbnd=$(sed -n 's/^CapBnd:[[:space:]]*//p' "/proc/$(pid_of "$ID-c")/status")
    [ "$(bit 13)" = 0 ] && [ "$(bit 27)" = 0 ] || fail "cap_net_raw and 27 got past the drop: CapBnd $capbnd holds NET_RAW or MKNOD"
    fail "a bundle spelling capabilities as libcap does was created (CapBnd $capbnd)"
fi
grep -q 'lists "cap_net_raw", which is not a capability name as the kernel spells it' "$WORK/err" || fail "the refusal does not name the spelling: $(tail -1 "$WORK/err")"
echo "ok: \"cap_net_raw\" and \"27\" are refused, not let past the drop"
spec "" ""

# A requirement refuses a bundle without it, and leaves nothing behind.
nx --profile needs-seccomp create --bundle "$BUNDLE" "$ID-s" 2>"$WORK/err" && fail "a bundle without seccomp passed a profile that requires it"
grep -q "seccompProfile.type: RuntimeDefault" "$WORK/err" || fail "the seccomp refusal does not say how to fix it: $(tail -1 "$WORK/err")"
[ ! -e "/run/crun/$ID-s" ] || fail "a refused create left state behind"
echo "ok: a profile requiring seccomp refuses a bundle without it"
nx --profile needs-userns create --bundle "$BUNDLE" "$ID-u" 2>"$WORK/err" && fail "a bundle without a user namespace passed a profile that requires one"
grep -q "hostUsers: false" "$WORK/err" || fail "the user namespace refusal does not say how to fix it: $(tail -1 "$WORK/err")"
echo "ok: a profile requiring a user namespace refuses a bundle without one"

# A profile that is not defined is an error, not the plain handler.
rc=0; nx --profile nope create --bundle "$BUNDLE" "$ID-n" 2>"$WORK/err" || rc=$?
[ "$rc" = 2 ] || fail "an undefined profile exited $rc, not 2"
grep -q "profile 'nope' is not defined" "$WORK/err" || fail "the undefined profile is not named: $(tail -1 "$WORK/err")"
echo "ok: an undefined profile exits 2"

# The bundle cannot claim a profile for itself, under one or under none:
# `state` would report a profile nothing applied.
spec "" ', "annotations": { "io.cageforge.nexcage.profile": "hardened" }'
nx --profile hardened create --bundle "$BUNDLE" "$ID-a" 2>"$WORK/err" && fail "a bundle carrying the profile annotation was accepted"
grep -q "which nexcage writes itself" "$WORK/err" || fail "the annotation refusal does not say why: $(tail -1 "$WORK/err")"
nx --runtime crun create --bundle "$BUNDLE" "$ID-a" 2>"$WORK/err" && fail "a bundle claiming a profile was accepted without one"
grep -q "which nexcage writes itself" "$WORK/err" || fail "the annotation refusal without a profile does not say why: $(tail -1 "$WORK/err")"
echo "ok: a bundle carrying io.cageforge.nexcage.profile is refused, with a profile or without"

echo "PASS: a profile narrows the bundle, and the kernel shows it"
