#!/bin/sh
# Kubernetes schedules a pod onto nexcage, on a real node.
#
# Everything before this ran a container engine directly: podman, `ctr`,
# `crictl`, and a standalone kubelet. This adds the two things only a cluster
# has — an API server and a RuntimeClass — so the pod arrives the way a user's
# pod arrives: `kubectl apply` with `runtimeClassName: nexcage`, scheduled, and
# run by a kubelet that was never told about nexcage by anything but its
# containerd configuration.
#
# It installs k3s when there is none, and removes it again unless KEEP=1. k3s
# is one binary carrying an API server, a kubelet, containerd and CNI, which is
# why it is here rather than kubeadm: less of the node changes, and the change
# is reversible with the uninstall script it ships.
#
# The nexcage binary must already be on the node, with the crun backend built
# in -- a container engine's containers go to that backend, and the default
# build has only Proxmox LXC. Build it with
#   docker build --build-arg BUILD_FLAGS="-Denable-backend-crun=true -Dcpu=baseline" .
# and copy it over; -Dcpu=baseline matters on an older host, where a
# native-tuned build dies with SIGILL.
#
# Usage: pod_on_node.sh [--keep]     (run as root on the node)
set -eu

NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
POD_IMAGE=${POD_IMAGE:-registry.k8s.io/e2e-test-images/busybox:1.29-4}
KEEP=${KEEP:-0}
[ "${1:-}" = "--keep" ] && KEEP=1
K3S_VERSION=${K3S_VERSION:-}
TRACE=/tmp/nexcage-node-trace.log

fail() { echo "FAIL: $*" >&2; exit 1; }
k() { /usr/local/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml "$@"; }

[ "$(id -u)" = 0 ] || fail "run this as root on the node"
[ -x "$NEXCAGE" ] || fail "no nexcage at $NEXCAGE: copy a crun-enabled build over first"

# The binary has to run here at all. A build tuned for a newer CPU dies with
# SIGILL on this one, and the failure looks like a runtime bug from every
# other angle.
"$NEXCAGE" --version >/dev/null 2>&1 || fail "$NEXCAGE does not run on this host (a native-tuned build? try -Dcpu=baseline)"
"$NEXCAGE" --runtime crun features >/dev/null 2>&1 \
    || fail "$NEXCAGE has no crun backend: rebuild with -Denable-backend-crun=true"
echo "ok: nexcage runs here, with the crun backend"

# An engine never passes --runtime, so the configuration must route to crun.
mkdir -p /etc/nexcage
if [ ! -f /etc/nexcage/config.json ]; then
    printf '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' \
        > /etc/nexcage/config.json
    echo "ok: wrote /etc/nexcage/config.json routing to crun"
else
    grep -q '"crun"' /etc/nexcage/config.json \
        || fail "/etc/nexcage/config.json exists and does not route to crun"
    echo "ok: /etc/nexcage/config.json already routes to crun"
fi

# What the kubelet's containerd asks the runtime, recorded. `exec` so that
# conmon-style supervision sees one process.
cat > /nexcage-traced <<EOT
#!/bin/sh
echo "\$*" >> $TRACE
exec $NEXCAGE "\$@"
EOT
chmod +x /nexcage-traced
: > "$TRACE"

installed_here=no
if ! command -v k3s >/dev/null 2>&1; then
    echo "installing k3s (it was not here)"
    # The extras a runtime test has no use for stay off, so less of the node
    # changes: no ingress controller, no load balancer, no metrics server.
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644" \
        sh - >/tmp/k3s-install.log 2>&1 || {
            tail -20 /tmp/k3s-install.log >&2
            fail "k3s would not install"
        }
    installed_here=yes
else
    echo "k3s is already here; leaving the installation alone"
fi

cleanup() {
    k delete pod nexcage-pod --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if [ "$KEEP" = 1 ]; then
        echo "KEEP=1: k3s and the RuntimeClass are left in place"
        return
    fi
    if [ "$installed_here" = yes ] && [ -x /usr/local/bin/k3s-uninstall.sh ]; then
        echo "removing the k3s this script installed"
        /usr/local/bin/k3s-uninstall.sh >/tmp/k3s-uninstall.log 2>&1 || true
        rm -f /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl 2>/dev/null || true
    fi
    rm -f /nexcage-traced 2>/dev/null || true
}
trap cleanup EXIT

# k3s builds its containerd configuration from a template; this adds one
# runtime to whatever it would have written, rather than replacing it.
mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
cat > /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl <<'TOML'
{{ template "base" . }}

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage.options]
  BinaryName = "/nexcage-traced"
TOML
systemctl restart k3s
echo "ok: k3s restarted with a nexcage runtime in its containerd"

i=0
until k get --raw /readyz >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && { journalctl -u k3s --no-pager -n 30 >&2; fail "the API server did not come up"; }
    sleep 2
done
i=0
until [ "$(k get nodes --no-headers 2>/dev/null | grep -c ' Ready ')" -ge 1 ]; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && { k get nodes >&2 || true; fail "the node never became Ready"; }
    sleep 2
done
echo "ok: the API server is up and the node is Ready"

# A pod needs the namespace's default ServiceAccount, which the controller
# manager creates a moment after the API server answers. Applying before it
# exists is refused with "serviceaccount \"default\" not found", and that is a
# race in the test rather than anything about the runtime.
i=0
until k get serviceaccount default >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 60 ] && fail "the default ServiceAccount never appeared"
    sleep 2
done
echo "ok: the default ServiceAccount exists"

# The runtime handler, named the way a cluster names one.
k apply -f - >/dev/null <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nexcage
handler: nexcage
YAML
echo "ok: RuntimeClass/nexcage"

k delete pod nexcage-pod --ignore-not-found --wait=true >/dev/null 2>&1 || true
k apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: nexcage-pod
  labels: { app: nexcage-pod }
spec:
  runtimeClassName: nexcage
  restartPolicy: Never
  containers:
  - name: app
    image: $POD_IMAGE
    command: ["/bin/sh", "-c", "echo HELLO_FROM_KUBERNETES; sleep 600"]
YAML
echo "ok: the pod was accepted with runtimeClassName: nexcage"

if ! k wait --for=condition=Ready pod/nexcage-pod --timeout=180s >/dev/null 2>&1; then
    k describe pod nexcage-pod 2>&1 | tail -25 >&2
    fail "the pod never became Ready"
fi
echo "ok: the pod is Ready"

node_ip=$(k get pod nexcage-pod -o jsonpath='{.status.podIP}' 2>/dev/null || true)
echo "ok: pod IP ${node_ip:-none}, from the cluster's CNI"

logs=$(k logs pod/nexcage-pod 2>/dev/null || true)
case "$logs" in
    *HELLO_FROM_KUBERNETES*) echo "ok: kubectl logs returns the container's output" ;;
    *) fail "kubectl logs gave '$logs'" ;;
esac

exec_out=$(k exec pod/nexcage-pod -- /bin/echo EXEC_THROUGH_KUBECTL 2>/dev/null || true)
case "$exec_out" in
    *EXEC_THROUGH_KUBECTL*) echo "ok: kubectl exec runs a command in the pod" ;;
    *) fail "kubectl exec gave '$exec_out'" ;;
esac

# Taking the pod away is part of the lifecycle, and it is also the only way
# `delete` reaches the runtime: the first version of this check asked the trace
# for `delete` while the pod was still running, and failed on a pod that was
# working perfectly.
k delete pod nexcage-pod --wait=true --timeout=120s >/dev/null 2>&1 \
    || fail "the pod would not go away"
echo "ok: the pod was deleted"

# The scheduler placed it, the kubelet ran it -- and it went through nexcage
# rather than through k3s's own runc, which is the part a green pod alone does
# not tell you.
[ -s "$TRACE" ] || fail "nexcage was never called: the RuntimeClass did not reach it"
for verb in create start exec delete; do
    grep -qE "(^| )$verb( |$)" "$TRACE" || {
        echo "what nexcage was asked:" >&2
        sed 's/[0-9a-f]\{64\}/<id>/g' "$TRACE" >&2
        fail "the kubelet's containerd never sent '$verb'"
    }
done
echo "ok: nexcage was asked create, start, exec and delete"

echo
echo "what Kubernetes asked the runtime, on this node:"
sed 's/[0-9a-f]\{64\}/<id>/g; s|\(--bundle \)[^ ]*|\1<dir>|g; s|\(--pid-file \)[^ ]*|\1<file>|g; s|\(--log \)[^ ]*|\1<log>|g; s|\(--root \)[^ ]*|\1<root>|g' "$TRACE" | sort -u | head -10

echo
echo "PASS: Kubernetes scheduled a pod onto nexcage on $(hostname)"
