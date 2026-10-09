#!/bin/sh
# A kubelet's own interface, against nexcage: a pod sandbox and a container in
# it, created through containerd's CRI with nexcage as the runtime handler.
#
# Why this exists. Three engine-facing defects in a row were invisible to every
# test here, because no test ran an engine: `--log` taken for a command name,
# a bundle the runtime never entered, and `--root=<dir>` read as a command.
# `nexcage version` cannot see any of that. A pod can.
#
# tests/cri/containerd.sh sets up the engine; this checks what nexcage does
# for it.
set -eu

# registry.k8s.io, not Docker Hub: no pull limit to be rate-limited by.
#
# The container's image must NOT be the sandbox's. The first version of this
# test used pause for both and passed on a binary with the bundle defect,
# because /pause exists in the sandbox's rootfs as well: the container started
# from the wrong rootfs and nothing could tell. busybox's /bin/sh does not
# exist there, so the assertion below has something to fail on.
SANDBOX_IMAGE=${SANDBOX_IMAGE:-registry.k8s.io/pause:3.10.1}
CTR_IMAGE=${CTR_IMAGE:-registry.k8s.io/e2e-test-images/busybox:1.29-4}

. "$(dirname "$0")/containerd.sh"
cleanup() {
    [ -n "${POD:-}" ] && crictl rmp -f "$POD" >/dev/null 2>&1
    kill "$CONTAINERD_PID" 2>/dev/null || true
}
trap cleanup EXIT

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

# What `kubectl exec` and an exec probe come down to. The engine sends this as
# `exec --process <file>` with an OCI process spec, not as a command line.
exec_out=$(crictl exec "$CTR" /bin/echo NEXCAGE_EXEC_OK 2>/tmp/exec.err) || {
    grep -oE 'desc = .*' /tmp/exec.err >&2 || cat /tmp/exec.err >&2
    fail "crictl exec did not run"
}
case "$exec_out" in
    *NEXCAGE_EXEC_OK*) echo "ok: crictl exec ran a command in the container" ;;
    *) fail "crictl exec printed '$exec_out'" ;;
esac

# And the status comes back, which is what an exec probe reads.
if crictl exec "$CTR" /bin/false >/dev/null 2>&1; then
    fail "crictl exec of /bin/false reported success"
fi
echo "ok: a failing exec reports its status"

# An in-place resize. The kubelet's UpdateContainerResources reaches the
# runtime as `update --resources=- <id>` with a linux.resources document on
# stdin; crictl update is that call by hand. The kernel's word on the result
# is the container's cgroup, which is under this test's own cgroup namespace.
crictl update --memory 67108864 "$CTR" >/tmp/update.err 2>&1 \
    || fail "crictl update failed: $(cat /tmp/update.err)"
grep -qE "(^| )update .*--resources[= ]-( |$)" "$TRACE" \
    || fail "the engine did not send 'update --resources=- <id>'; it was asked: $(sed 's/[0-9a-f]\{64\}/<id>/g' "$TRACE" | tr '\n' '|')"
mem_max=$(find /sys/fs/cgroup -name memory.max -path "*${CTR}*" 2>/dev/null | head -1)
[ -n "$mem_max" ] || fail "no memory.max for container $CTR under /sys/fs/cgroup"
got=$(cat "$mem_max")
[ "$got" = 67108864 ] || fail "after update --memory 67108864, $mem_max holds '$got'"
echo "ok: crictl update resized the container, and its cgroup says memory.max=$got"

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
for verb in create start exec update delete; do
    grep -qE "(^| )$verb( |$)" "$TRACE" || {
        echo "what nexcage was asked:" >&2
        sed 's/[0-9a-f]\{64\}/<id>/g' "$TRACE" >&2
        fail "the engine never sent '$verb'"
    }
done
echo "ok: nexcage was asked create, start, exec, update and delete"

echo "PASS: a pod runs on nexcage through containerd's CRI"
