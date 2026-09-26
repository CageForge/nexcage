#!/bin/sh
# A kubelet's own interface, against nexcage: a pod sandbox and a container in
# it, created through containerd's CRI with nexcage as the runtime handler.
#
# Why this exists. Three engine-facing defects in a row were invisible to every
# test here, because no test ran an engine: `--log` taken for a command name,
# a bundle the runtime never entered, and `--root=<dir>` read as a command.
# `nexcage version` cannot see any of that. A pod can.
#
# What is nexcage's and what is not: the engine creates the sandbox's network
# namespace, runs the CNI plugins in it, writes the OCI spec and captures the
# container's output. nexcage creates, starts, reports and deletes the
# container. This checks the second list, and uses the first as the setting.
#
# Needs: containerd, crictl, CNI plugins, and a privileged container with its
# own cgroup namespace. Run it as root.
set -eu

NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
SUBNET=${SUBNET:-10.88.0.0/16}
GATEWAY=${GATEWAY:-10.88.0.1}
# registry.k8s.io, not Docker Hub: no pull limit to be rate-limited by.
#
# The container's image must NOT be the sandbox's. The first version of this
# test used pause for both and passed on a binary with the bundle defect,
# because /pause exists in the sandbox's rootfs as well: the container started
# from the wrong rootfs and nothing could tell. busybox's /bin/sh does not
# exist there, so the assertion below has something to fail on.
SANDBOX_IMAGE=${SANDBOX_IMAGE:-registry.k8s.io/pause:3.10.1}
CTR_IMAGE=${CTR_IMAGE:-registry.k8s.io/e2e-test-images/busybox:1.29-4}
TRACE=/tmp/cri-trace.log

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- the setting -----------------------------------------------------------

mkdir -p /etc/nexcage /etc/containerd /etc/cni/net.d /var/log/pods/cri-test

# An engine never passes --runtime, so the configuration has to route to the
# OCI backend. A pattern is a regex only when it starts with ^ or ends with $.
printf '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' \
    > /etc/nexcage/config.json
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 40\n' \
    > /etc/crictl.yaml

# Controllers a sandbox's cgroup needs, delegated into this container's own.
# The cgroup holding our processes cannot enable them for its children.
if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
    for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
        echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
    done
    echo "+cpu +cpuset +memory +pids +io" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
fi
case "$(cat /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null)" in
    *cpu*) : ;;
    *) fail "the cpu controller is not delegated to this cgroup; a sandbox cannot be created" ;;
esac

cat > /etc/cni/net.d/10-nexcage-test.conflist <<JSON
{
  "cniVersion": "1.0.0",
  "name": "nexcage-test",
  "plugins": [
    { "type": "bridge", "bridge": "cni-nx0", "isGateway": true, "ipMasq": true,
      "ipam": { "type": "host-local",
                "ranges": [ [ { "subnet": "$SUBNET" } ] ],
                "routes": [ { "dst": "0.0.0.0/0" } ] } },
    { "type": "loopback" }
  ]
}
JSON

# What the runtime was asked, recorded. `exec` keeps it to one process.
cat > /nexcage-traced <<EOT
#!/bin/sh
echo "\$*" >> $TRACE
exec $NEXCAGE "\$@"
EOT
chmod +x /nexcage-traced

cat > /etc/containerd/config.toml <<'TOML'
version = 3

[plugins.'io.containerd.cri.v1.images']
  # overlay on overlay is not available inside a container; native always is.
  snapshotter = 'native'
  # containerd 2.x pulls through the transfer service by default, which has no
  # unpack configuration for the native snapshotter and fails with "no unpack
  # platforms defined".
  use_local_image_pull = true

[plugins.'io.containerd.cri.v1.runtime']
  [plugins.'io.containerd.cri.v1.runtime'.containerd]
    default_runtime_name = 'nexcage'
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage]
      runtime_type = 'io.containerd.runc.v2'
      snapshotter = 'native'
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage.options]
        BinaryName = '/nexcage-traced'

  [plugins.'io.containerd.cri.v1.runtime'.cni]
    bin_dirs = ['/usr/lib/cni', '/opt/cni/bin']
    conf_dir = '/etc/cni/net.d'
TOML

containerd >/tmp/containerd.log 2>&1 &
CONTAINERD_PID=$!
cleanup() {
    [ -n "${POD:-}" ] && crictl rmp -f "$POD" >/dev/null 2>&1
    kill "$CONTAINERD_PID" 2>/dev/null || true
}
trap cleanup EXIT

i=0
until crictl version >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && { tail -20 /tmp/containerd.log >&2; fail "containerd did not come up"; }
    sleep 1
done
echo "ok: containerd is serving the CRI"

for img in "$SANDBOX_IMAGE" "$CTR_IMAGE"; do
    crictl pull "$img" >/dev/null 2>&1 || fail "cannot pull $img"
done
echo "ok: $SANDBOX_IMAGE and $CTR_IMAGE pulled"

cat > /tmp/sandbox.json <<'JSON'
{ "metadata": { "name": "nexcage-test-pod", "namespace": "default",
                "uid": "nexcage-test-uid", "attempt": 1 },
  "log_directory": "/var/log/pods/cri-test",
  "linux": {} }
JSON
cat > /tmp/container.json <<JSON
{ "metadata": { "name": "nexcage-test-ctr" },
  "image": { "image": "$CTR_IMAGE" },
  "command": [ "/bin/sh", "-c", "echo NEXCAGE_CRI_OK; sleep 30" ],
  "log_path": "nexcage-test-ctr.0.log",
  "linux": {} }
JSON

# --- what is being checked -------------------------------------------------

POD=$(crictl runp --runtime nexcage /tmp/sandbox.json 2>/tmp/runp.err) || {
    grep -oE 'desc = .*' /tmp/runp.err >&2 || cat /tmp/runp.err >&2
    fail "the sandbox was not created"
}
case "$POD" in
    [0-9a-f]*) [ ${#POD} -eq 64 ] || fail "runp did not answer with an id: $POD" ;;
    *) fail "runp did not answer with an id: $POD" ;;
esac
echo "ok: pod sandbox $POD"

crictl pods --quiet 2>/dev/null | grep -q "$POD" || fail "the sandbox is not listed"
crictl inspectp "$POD" 2>/dev/null | tr -d ' \n' | grep -q '"state":"SANDBOX_READY"' \
    || fail "the sandbox is not ready"
echo "ok: the sandbox is ready"

# The engine's CNI, joined by the runtime: the address has to come from the
# range above, not from the node.
ip=$(crictl inspectp "$POD" 2>/dev/null | tr -d ' \n' | grep -oE '"ip":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+' || true)
prefix=$(echo "$GATEWAY" | cut -d. -f1-3).
case "${ip:-}" in
    "$prefix"*) echo "ok: pod address $ip, from the test's CNI range" ;;
    *) fail "the pod has no address from $SUBNET (got '${ip:-none}')" ;;
esac

CTR=$(crictl create "$POD" /tmp/container.json /tmp/sandbox.json 2>/tmp/create.err) || {
    grep -oE 'desc = .*' /tmp/create.err >&2 || cat /tmp/create.err >&2
    fail "the container was not created"
}
echo "ok: container $CTR created"

crictl start "$CTR" >/dev/null 2>/tmp/start.err || {
    grep -oE 'desc = .*' /tmp/start.err >&2 || cat /tmp/start.err >&2
    fail "the container did not start"
}

i=0
until crictl inspect "$CTR" 2>/dev/null | tr -d ' \n' | grep -q '"state":"CONTAINER_RUNNING"'; do
    i=$((i + 1))
    [ "$i" -gt 20 ] && {
        crictl inspect "$CTR" 2>/dev/null | tr -d ' \n' | grep -oE '"state":"[A-Z_]+"' >&2
        fail "the container never reached running"
    }
    sleep 1
done
echo "ok: the container is running"

# It ran from its own rootfs, which is the part a bundle defect breaks: /bin/sh
# lives in busybox's rootfs and not in the sandbox's, so this line cannot
# appear if the runtime resolved the rootfs against the wrong directory.
i=0
until crictl logs "$CTR" 2>/dev/null | grep -q NEXCAGE_CRI_OK; do
    i=$((i + 1))
    [ "$i" -gt 15 ] && {
        echo "the container's output was:" >&2
        crictl logs "$CTR" 2>&1 | head -5 >&2
        fail "the container did not run its own rootfs"
    }
    sleep 1
done
echo "ok: the container ran /bin/sh from its own rootfs"

crictl stopp "$POD" >/dev/null 2>&1 || fail "the pod would not stop"
crictl rmp -f "$POD" >/dev/null 2>&1 || fail "the pod would not be removed"
POD=""
echo "ok: the pod stopped and was removed"

# --- and that it went through nexcage at all -------------------------------
#
# Without this the checks above would pass just as well with runc behind the
# handler, which is the mistake that makes a test look like it covers
# something.
# `state` is deliberately not in this list: containerd's shim keeps track of the
# container itself and never asks, while CRI-O asks constantly. Requiring it
# would fail on correct behaviour.
[ -s "$TRACE" ] || fail "nexcage was never called: the handler did not reach it"
for verb in create start delete; do
    grep -qE "(^| )$verb( |$)" "$TRACE" || {
        echo "what nexcage was asked:" >&2
        sed 's/[0-9a-f]\{64\}/<id>/g' "$TRACE" >&2
        fail "the engine never sent '$verb'"
    }
done
echo "ok: nexcage was asked create, start and delete"

echo "PASS: a pod runs on nexcage through containerd's CRI"
