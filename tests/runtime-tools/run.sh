#!/bin/sh
# Runs the runtime-spec validation suite inside tests/runtime-tools/Dockerfile's
# image (privileged, private cgroup namespace), against nexcage routed to the
# crun backend, and against the image's own crun for reference. The result is
# checked against known-failures: a failure not on the list is a regression,
# and a listed test that passes means the list is out of date. Either is exit 1.
set -eu
T=$(dirname "$0")
cd /runtime-tools

# Controllers the containers' cgroups need, delegated into this container's
# own, as tests/cri/pod_on_nexcage.sh does: the cgroup holding our processes
# cannot enable them for its children.
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init
    for p in $(cat /sys/fs/cgroup/cgroup.procs); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    for c in cpu cpuset memory pids io hugetlb; do
        echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
    done
fi

# The harness makes its bundles under /tmp, and two tests make a character
# device 0:0 in one. That is overlayfs's whiteout, which overlayfs refuses to
# create (EPERM), and /tmp in a container image is overlayfs.
mount -t tmpfs tmpfs /tmp

mkdir -p /etc/nexcage
printf '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' \
    > /etc/nexcage/config.json

echo "=== nexcage $(nexcage --version | head -1), routed to crun"
RUNTIME=$(command -v nexcage) python3 -I "$T/validate.py" run /tmp/nexcage.json validation/*/*.t
echo "=== $(crun --version | head -1), for reference"
RUNTIME=$(command -v crun) python3 -I "$T/validate.py" run /tmp/crun.json validation/*/*.t
python3 -I "$T/validate.py" check /tmp/nexcage.json /tmp/crun.json "$T/known-failures"
