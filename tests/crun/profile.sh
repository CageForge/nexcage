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

# What an engine would hand over: a 1 GiB limit the profile lowers, and the
# capabilities a container usually gets, NET_RAW and MKNOD among them.
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
    "resources": { "memory": { "limit": 1073741824 } }
    $1
  }
  $2
}
JSON
}

# The program name names the profile, as an engine's BinaryName does.
ln -s "$NEXCAGE" "$WORK/nexcage@hardened"
nx() { "$NEXCAGE" --config "$CFG" "$@"; }
cleanup() { cd /; for id in "$ID" "$ID-s" "$ID-u" "$ID-a"; do nx delete --force "$id" >/dev/null 2>&1 || true; done; rm -rf "$WORK"; }
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

cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
[ "$(cat "$cg/memory.max")" = 67108864 ] || fail "memory.max is $(cat "$cg/memory.max"), not the profile's 64M"
[ "$(cat "$cg/pids.max")" = 50 ] || fail "pids.max is $(cat "$cg/pids.max"), not the profile's 50"
echo "ok: memory.max 67108864 (the bundle asked 1G), pids.max 50 (the bundle set none)"

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
