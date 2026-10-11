#!/bin/sh
# An isolation profile's limits hold after create: `update` cannot take a
# container made under one above the profile's memory and pids caps, or to no
# limit at all (ADR-005). Resizes within the caps work as they always did.
#
# An engine builds an update from its own copy of the spec, from before the
# profile lowered it: containerd's in-place resize sends the pod's own memory
# limit. nexcage used to hand that to libcrun as it was, and libcrun wrote it
# into the cgroup, so the first resize undid the profile while `state` still
# named it. The check reads the cgroup files, not nexcage's word. cgroup v2.
#
# Usage: profile_update.sh [bundle-dir]     (default /bundle, rootfs in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
WORK=$(mktemp -d)
CFG=$WORK/config.json
ID=profile-update-$$

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f /sys/fs/cgroup/cgroup.controllers ] || fail "this checks cgroup v2 files, and the host is not on cgroup v2"

if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    for c in cpu memory pids; do
        echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
    done
fi

cat > "$CFG" <<'JSON'
{ "profiles": { "hardened": { "runtime": "crun", "crun": { "limits": { "memory": "64M", "pids": 50 } } } } }
JSON

# A pod that asks for 1 GiB, with swap equal to it (containerd's "no swap").
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
    "resources": { "memory": { "limit": 1073741824, "swap": 1073741824 } }
  }
}
JSON

ln -s "$NEXCAGE" "$WORK/nexcage@hardened"
# Every later call goes through the program name, as an engine's would.
nx() { "$WORK/nexcage@hardened" --config "$CFG" "$@"; }
cleanup() { cd /; nx delete --force "$ID" >/dev/null 2>&1 || true; nx delete --force "$ID-p" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
cd /

nx create --bundle "$BUNDLE" "$ID" 2>"$WORK/err" || fail "create under nexcage@hardened: $(tail -1 "$WORK/err")"
nx start "$ID" 2>"$WORK/err" || fail "start: $(tail -1 "$WORK/err")"
pid=$(nx state "$ID" | sed -n 's/.*"pid": *\([0-9][0-9]*\).*/\1/p')
[ -n "$pid" ] && [ -d "/proc/$pid" ] || fail "no running process for $ID"
cg=/sys/fs/cgroup$(sed -n 's/^0:://p' "/proc/$pid/cgroup")
limits() { echo "memory.max=$(cat "$cg/memory.max") pids.max=$(cat "$cg/pids.max")"; }
[ "$(limits)" = "memory.max=67108864 pids.max=50" ] || fail "create did not apply the profile: $(limits)"
echo "ok: created under the profile: $(limits)"

# Each of these would lift a cap. Every one must be refused, say why ($says:
# which cap, unless set otherwise), and leave the cgroup as it was.
says="profile 'hardened' caps"
refused() {  # <what> <command...>
    what=$1; shift
    rc=0; "$@" >/dev/null 2>"$WORK/err" || rc=$?
    [ "$rc" != 0 ] || fail "$what was accepted: now $(limits)"
    grep -qF "$says" "$WORK/err" || fail "$what was refused without saying \"$says\": $(tr '\n' ' ' < "$WORK/err")"
    [ "$(limits)" = "memory.max=67108864 pids.max=50" ] || fail "$what was refused and still changed the cgroup: $(limits)"
    echo "ok: refused (exit $rc): $what -- $(awk -v s="$says" 'i = index($0, s) { print substr($0, i); exit }' "$WORK/err")"
}
doc() { printf '%s' "$1" > "$WORK/doc.json"; }
doc '{"memory":{"limit":1073741824,"swap":1073741824},"cpu":{"shares":512}}'
refused "containerd's resize with the pod's own 1G" nx update --resources - "$ID" < "$WORK/doc.json"
doc '{"pids":{"limit":500}}'
refused "--resources pids.limit 500" nx update --resources "$WORK/doc.json" "$ID"
doc '{"unified":{"memory.max":"max"}}'
refused "--resources unified memory.max max" nx update --resources "$WORK/doc.json" "$ID"
doc '{"unified":{"pids.max":"max"}}'
refused "--resources unified pids.max max" nx update --resources "$WORK/doc.json" "$ID"
refused "--memory -1" nx update --memory -1 "$ID"
refused "--memory 2G" nx update --memory 2G "$ID"
refused "--pids-limit -1" nx update --pids-limit -1 "$ID"
refused "--pids-limit 999" nx update --pids-limit 999 "$ID"

# A key that ends in a NUL is the key before it to libcrun's parser, which
# keeps the last of two keys that are then the same: each of these took a cap
# off past a check that read the first. Refused for the NUL, which no
# runtime spec has.
says='has a NUL in the key'
doc '{"memory":{"limit":33554432,"limit\u0000":1073741824}}'
refused "--resources memory.limit 32M, and 1G behind \"limit\\u0000\"" nx update --resources "$WORK/doc.json" "$ID"
doc '{"memory":{"limit":33554432},"memory\u0000":{"limit":-1}}'
refused "--resources memory.limit 32M, and -1 behind \"memory\\u0000\"" nx update --resources "$WORK/doc.json" "$ID"
doc '{"unified":{"memory.max\u0000":"max"}}'
refused "--resources unified \"memory.max\\u0000\" max" nx update --resources "$WORK/doc.json" "$ID"
doc '{"pids":{"limit":40,"limit\u0000":-1}}'
refused "--resources pids.limit 40, and -1 behind \"limit\\u0000\"" nx update --resources - "$ID" < "$WORK/doc.json"

# Within the caps: down, and back up to them, the engine's way and by flags.
doc '{"memory":{"limit":33554432,"swap":33554432},"pids":{"limit":40}}'
nx update --resources - "$ID" < "$WORK/doc.json" 2>"$WORK/err" || fail "a resize within the caps was refused: $(tr '\n' ' ' < "$WORK/err")"
[ "$(limits)" = "memory.max=33554432 pids.max=40" ] || fail "a resize within the caps did not apply: $(limits)"
nx update --memory 64M --memory-swap 64M --pids-limit 50 "$ID" 2>"$WORK/err" || fail "a resize back up to the caps was refused: $(tr '\n' ' ' < "$WORK/err")"
[ "$(limits)" = "memory.max=67108864 pids.max=50" ] || fail "a resize back up to the caps did not apply: $(limits)"
echo "ok: resizes within the caps apply: down to 32M/40 and back to 64M/50"

# A container made without a profile is not held to anything.
"$NEXCAGE" --runtime crun create --bundle "$BUNDLE" "$ID-p" 2>"$WORK/err" || fail "create without a profile: $(tail -1 "$WORK/err")"
"$NEXCAGE" update --memory 2G --pids-limit 999 "$ID-p" 2>"$WORK/err" || fail "update of a container without a profile: $(tr '\n' ' ' < "$WORK/err")"
echo "ok: a container made without a profile updates as before"

echo "PASS: a profile's caps hold after create"
