#!/bin/sh
# --systemd-cgroup reaches libcrun from where every engine puts it: before the
# command.
#
# An engine sends it as a global option, the way runc's command line has it:
# containerd's shim (go-runc) after --root, --log and --log-format, for a
# handler with SystemdCgroup = true, and conmon, for CRI-O and podman, first of
# all. nexcage used to step over it there, so libcrun stayed on its cgroupfs
# manager. That manager takes the engine's systemd-form cgroupsPath
# ("<slice>:<prefix>:<id>") for a directory name and makes it at the root of
# the hierarchy: outside the pod's cgroup, its QoS class and kubepods.slice,
# and every limit the kubelet sets on them.
#
# This container has no systemd, so libcrun's systemd manager cannot reach
# D-Bus and create fails naming sd-bus, as `crun --systemd-cgroup create` does
# here: that failure is the evidence the flag arrived. What is checked is the
# cgroup hierarchy itself, which must hold no directory of cgroupfs's making. A
# create without the flag is the control: it does make one, and the
# container's init is in it, so the check can tell the two apart.
#
# The routing is /etc/nexcage/config.json, as on a node, so that the command
# lines are the engines' own, word for word. Run it in a throwaway container.
#
# Usage: systemd_cgroup.sh [bundle-dir]   (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
ROOT=/run/nexcage-sd
OUT=/run/nexcage-sd-check
CG=/sys/fs/cgroup
SLICE=test.slice

fail() { echo "FAIL: $*" >&2; exit 1; }
failed=0
miss() { echo "FAIL: $*" >&2; failed=$((failed + 1)); }

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || \
    fail "no rootfs in $BUNDLE: put one there first"
[ -f $CG/cgroup.controllers ] || fail "this reads cgroup v2, and the host is not on cgroup v2"
# With systemd here a create with the flag would succeed under a slice, and
# the failure this check reads as evidence would never come.
for s in /run/systemd/private /run/dbus/system_bus_socket; do
    [ ! -e "$s" ] || fail "$s exists: this check needs a container without systemd"
done
[ ! -e /etc/nexcage/config.json ] || fail "/etc/nexcage/config.json exists: run this in a throwaway container"

if [ -w $CG/cgroup.subtree_control ]; then
    mkdir -p $CG/init 2>/dev/null || true
    for p in $(cat $CG/cgroup.procs 2>/dev/null); do
        echo "$p" > $CG/init/cgroup.procs 2>/dev/null || true
    done
    echo "+cpu +memory +pids" > $CG/cgroup.subtree_control 2>/dev/null || true
fi

mkdir -p /etc/nexcage "$OUT"
echo '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' > /etc/nexcage/config.json

IDS="sd-runc sd-conmon sd-after sd-none"
cleanup() {
    cd /
    for id in $IDS; do "$NEXCAGE" --root "$ROOT" delete --force "$id" >/dev/null 2>&1 || true; done
    for id in $IDS; do rmdir "$CG/$SLICE:cri-containerd:$id" 2>/dev/null || true; done
    rm -f /etc/nexcage/config.json
}
trap cleanup EXIT

# The bundle as a kubelet's engine writes it on a systemd node: the cgroup
# named slice:prefix:id.
spec() {  # spec <id>
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
  "hostname": "$1",
  "mounts": [ { "destination": "/proc", "type": "proc", "source": "proc" } ],
  "linux": {
    "cgroupsPath": "$SLICE:cri-containerd:$1",
    "namespaces": [ { "type": "pid" }, { "type": "ipc" }, { "type": "uts" }, { "type": "mount" } ]
  }
}
JSON
}

# libcrun took its systemd manager: create failed reaching systemd, said so
# where the engine reads it, and made no cgroup at the root of the hierarchy.
asked_systemd() {  # asked_systemd <id> <whose order> <create's status> <where its error went>
    stray=$CG/$SLICE:cri-containerd:$1
    if [ "$3" = 0 ]; then
        miss "$2: create succeeded, so --systemd-cgroup never reached libcrun: its cgroupfs manager made $(ls -d "$stray" 2>/dev/null || echo 'a cgroup elsewhere'), at the root of the hierarchy"
        return 0
    fi
    grep -q 'sd-bus' "$4" || { miss "$2: create failed, and not for want of systemd: $(cat "$4")"; return 0; }
    [ ! -e "$stray" ] || { miss "$2: create failed, and still left $stray at the root"; return 0; }
    echo "ok: $2: libcrun asked systemd for the cgroup ($(grep -o 'cannot open sd-bus[^"]*' "$4" | head -1)); nothing made at the root"
}

# go-runc's order, which containerd's shim sends. The error is read from --log,
# where containerd reads it.
spec sd-runc
rc=0
"$NEXCAGE" --root "$ROOT" --log "$OUT/runc.log" --log-format json --systemd-cgroup \
    create --bundle "$BUNDLE" --pid-file "$OUT/runc.pid" sd-runc 2>/dev/null || rc=$?
asked_systemd sd-runc "go-runc's order" "$rc" "$OUT/runc.log"

# conmon's order, for CRI-O (whose cgroup_manager is systemd by default) and
# podman: the flag first, then CRI-O's runtime_root. conmon reads stderr.
spec sd-conmon
rc=0
"$NEXCAGE" --systemd-cgroup --root="$ROOT" \
    create --bundle "$BUNDLE" --pid-file "$OUT/conmon.pid" sd-conmon 2>"$OUT/conmon.err" || rc=$?
asked_systemd sd-conmon "conmon's order" "$rc" "$OUT/conmon.err"

# After the command, which no engine sends, but which nexcage has taken all
# along.
spec sd-after
rc=0
"$NEXCAGE" --root "$ROOT" create --systemd-cgroup --bundle "$BUNDLE" sd-after 2>"$OUT/after.err" || rc=$?
asked_systemd sd-after "after the command" "$rc" "$OUT/after.err"

# The control: without the flag, cgroupfs makes the slice-form path a
# directory at the root, and the container's init is in it.
spec sd-none
"$NEXCAGE" --root "$ROOT" --log "$OUT/none.log" --log-format json \
    create --bundle "$BUNDLE" --pid-file "$OUT/none.pid" sd-none \
    || fail "control: create without --systemd-cgroup failed: $(cat "$OUT/none.log")"
[ -d "$CG/$SLICE:cri-containerd:sd-none" ] || fail "control: cgroupfs made no $CG/$SLICE:cri-containerd:sd-none"
pid=$(cat "$OUT/none.pid")
grep -qx "0::/$SLICE:cri-containerd:sd-none" "/proc/$pid/cgroup" \
    || fail "control: init $pid is in $(cat "/proc/$pid/cgroup"), not the cgroup cgroupfs made"
echo "ok: control: without the flag, cgroupfs made $CG/$SLICE:cri-containerd:sd-none at the root, and init $pid is in it"

[ "$failed" = 0 ] || exit 1
echo "PASS: --systemd-cgroup before the command reaches libcrun, in go-runc's order and in conmon's"
