#!/bin/sh
# critest, the CRI validation suite from kubernetes-sigs/cri-tools: what
# Kubernetes checks of a container runtime, against containerd with nexcage as
# its runtime handler (#311). tests/cri/containerd.sh sets up the engine.
#
# The result is checked against critest-known-failures: a failure the list
# does not name is a regression, and a listed spec that does not fail means
# the list is out of date. Either is exit 1.
set -eu
T=$(dirname "$0")

. "$T/containerd.sh"
trap 'kill "$CONTAINERD_PID" 2>/dev/null || true' EXIT

# critest's own exit status says only that something failed; the check below
# says what, against the list.
critest --runtime-endpoint unix:///run/containerd/containerd.sock \
    --image-endpoint unix:///run/containerd/containerd.sock \
    --ginkgo.no-color --ginkgo.timeout=30m \
    --ginkgo.json-report=/tmp/critest.json || true
[ -s /tmp/critest.json ] || fail "critest wrote no report"

# Without this the suite would pass just as well with runc behind the handler.
[ -s "$TRACE" ] || fail "nexcage was never called: the handler did not reach it"

python3 -I "$T/critest_check.py" /tmp/critest.json "$T/critest-known-failures"
