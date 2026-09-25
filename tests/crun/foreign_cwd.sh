#!/bin/sh
# A container engine does not run the runtime from the bundle it names.
#
# containerd's shim serves a whole pod: it runs the runtime from the sandbox's
# directory while `--bundle` names the container's own. An OCI spec's
# root.path is normally relative ("rootfs"), so a runtime that does not enter
# the bundle resolves the rootfs against whatever directory it was started in.
# crun and runc chdir into the bundle for exactly this reason; nexcage did not,
# and the symptom was libcrun reporting the container's executable "not found"
# in a rootfs that never held it.
#
# The check: create a container from a working directory that is NOT the
# bundle. Nothing about this needs a container engine to reproduce.
#
# Usage: foreign_cwd.sh [bundle-dir]   (default /bundle, rootfs already in it)
set -eu

BUNDLE=${1:-/bundle}
ID=foreign-cwd-$$
NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}

[ -x "$BUNDLE/rootfs/bin/sh" ] || [ -L "$BUNDLE/rootfs/bin/sh" ] || {
    echo "no rootfs in $BUNDLE: put one there first" >&2
    exit 1
}

# Controllers a container's cgroup needs, delegated into this container's own.
# Best effort: outside a container this is already the case.
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    echo "+cpu +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi

# A spec as an engine writes one: the rootfs named relative to the bundle.
cat > "$BUNDLE/config.json" <<JSON
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 0, "gid": 0 },
    "args": [ "/bin/sh", "-c", "sleep 30" ],
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

# The point of the test: a working directory that is not the bundle, and one
# that holds no config.json and no rootfs of its own.
cd /

echo "cwd: $(pwd)   bundle: $BUNDLE"
if ! "$NEXCAGE" --runtime crun create --bundle "$BUNDLE" "$ID"; then
    echo "FAIL: create from a foreign working directory" >&2
    exit 1
fi
echo "ok: created"

state=$("$NEXCAGE" --runtime crun state "$ID" 2>&1) || {
    echo "FAIL: state after create" >&2; echo "$state" >&2; exit 1
}
echo "$state" | grep -q '"status"' || { echo "FAIL: state is not a state" >&2; echo "$state" >&2; exit 1; }
echo "$state" | grep -q '"created"' || { echo "FAIL: not created" >&2; echo "$state" >&2; exit 1; }
echo "ok: state reports created"

"$NEXCAGE" --runtime crun start "$ID" || { echo "FAIL: start" >&2; exit 1; }
echo "ok: started"

echo "PASS: a bundle is found from a working directory that is not it"
