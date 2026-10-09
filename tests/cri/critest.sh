#!/bin/sh
# critest, the CRI validation suite from kubernetes-sigs/cri-tools: what
# Kubernetes checks of a container runtime, against containerd with nexcage as
# its runtime handler (#311). tests/cri/containerd.sh sets up the engine.
#
# The suite runs again through the image's own crun, for reference: a spec
# that fails on both is the setting's or the suite's, not nexcage's. The
# result is checked against critest-known-failures: a failure the list does
# not name is a regression, and a listed spec that does not fail means the
# list is out of date. Either is exit 1.
set -eu
T=$(dirname "$0")

. "$T/containerd.sh"
trap 'kill "$CONTAINERD_PID" 2>/dev/null || true' EXIT

# critest's own exit status says only that something failed; the check below
# says what, against the list.
critest_through() {
    critest --runtime-endpoint unix:///run/containerd/containerd.sock \
        --image-endpoint unix:///run/containerd/containerd.sock \
        --runtime-handler "$1" --ginkgo.no-color --ginkgo.timeout=30m \
        --ginkgo.json-report="$2" || true
}

echo "=== $(critest --version | head -1); $(containerd --version | cut -d' ' -f1-3); $("$NEXCAGE" --version | head -1)"
critest_through nexcage /tmp/critest.json
[ -s /tmp/critest.json ] || fail "critest wrote no report"

# Without this the suite would pass just as well with runc behind the handler.
[ -s "$TRACE" ] || fail "nexcage was never called: the handler did not reach it"

REFERENCE=""
if [ -n "$CRUN_RUNTIME" ]; then
    echo "=== the same suite through $(crun --version | head -1), for reference"
    critest_through crun /tmp/critest-crun.json > /tmp/critest-crun.log 2>&1
    tail -4 /tmp/critest-crun.log
    [ -s /tmp/critest-crun.json ] || fail "critest through crun wrote no report"
    REFERENCE=/tmp/critest-crun.json
fi

python3 -I "$T/critest_check.py" /tmp/critest.json "$T/critest-known-failures" $REFERENCE || {
    echo "=== containerd's errors, the last 40"
    grep 'level=error' /tmp/containerd.log | cut -c1-400 | tail -40
    exit 1
}
