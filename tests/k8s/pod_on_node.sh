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
# It installs what docs/INSTALL.md tells an administrator to install, from the
# same files: packaging/config/config.oci.example.json, and the k3s template and
# RuntimeClass in deploy/kubernetes/node/. Run it from a checkout, so that a
# run checks those files and not a copy of them.
#
# Then the same for isolation profiles (#315, ADR-005): two more runtime
# handlers, nexcage-hardened and nexcage-small, whose BinaryName is
# nexcage@<profile>, a RuntimeClass for each, and one pod under each. What each
# pod got is read from inside it -- its uid_map, its seccomp mode and
# capabilities, its cgroup's limits -- not from nexcage's log. The profiles are
# the two in config.oci.example.json.
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
REPO=$(cd "$(dirname "$0")/../.." && pwd)
NODE_FILES=$REPO/deploy/kubernetes/node

fail() { echo "FAIL: $*" >&2; exit 1; }
k() { /usr/local/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml "$@"; }

[ "$(id -u)" = 0 ] || fail "run this as root on the node"
[ -f "$NODE_FILES/runtimeclass.yaml" ] || fail "no $NODE_FILES: run this from a checkout"
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
wrote_config=no
if [ ! -f /etc/nexcage/config.json ]; then
    cp "$REPO/packaging/config/config.oci.example.json" /etc/nexcage/config.json
    wrote_config=yes
    echo "ok: wrote /etc/nexcage/config.json routing to crun"
else
    grep -q '"crun"' /etc/nexcage/config.json \
        || fail "/etc/nexcage/config.json exists and does not route to crun"
    echo "ok: /etc/nexcage/config.json already routes to crun"
fi
for p in hardened small; do
    grep -q "\"$p\"" /etc/nexcage/config.json \
        || fail "/etc/nexcage/config.json has no profile '$p'; config.oci.example.json has it"
done

# What the kubelet's containerd asks the runtime, recorded, each line under
# the handler it came through. `exec` so that conmon-style supervision sees
# one process. A profile's handler runs nexcage by a nexcage@<profile> name,
# which is all that names the profile.
LINKS=/run/nexcage-k8s-e2e
mkdir -p "$LINKS"
traced() {  # traced <wrapper> <program it runs>
    cat > "/$1" <<EOT
#!/bin/sh
echo "$1 \$*" >> $TRACE
exec $2 "\$@"
EOT
    chmod +x "/$1"
}
traced nexcage-traced "$NEXCAGE"
for p in hardened small; do
    ln -sfn "$NEXCAGE" "$LINKS/nexcage@$p"
    traced "nexcage-traced@$p" "$LINKS/nexcage@$p"
done
: > "$TRACE"

# Set before anything is installed, so that an install that fails halfway is
# removed as well: the uninstall script is there as soon as k3s's installer has
# got that far.
installed_here=no
cleanup() {
    k delete pod nexcage-pod nexcage-hardened nexcage-small nexcage-refused --ignore-not-found --wait=false >/dev/null 2>&1 || true
    if [ "$KEEP" = 1 ]; then
        echo "KEEP=1: k3s and the RuntimeClass are left in place"
        return
    fi
    if [ "$installed_here" = yes ] && [ -x /usr/local/bin/k3s-uninstall.sh ]; then
        echo "removing the k3s this script installed"
        /usr/local/bin/k3s-uninstall.sh >/tmp/k3s-uninstall.log 2>&1 || true
        rm -f /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl 2>/dev/null || true
    fi
    # Routing everything to crun is wrong for any other nexcage on the node --
    # the lifecycle E2E's default build has no crun backend -- so the file goes
    # with the run that wrote it. One that was here before is left alone.
    if [ "$wrote_config" = yes ]; then
        echo "removing the /etc/nexcage/config.json this script wrote"
        rm -f /etc/nexcage/config.json
    fi
    k delete runtimeclass nexcage-hardened nexcage-small --ignore-not-found >/dev/null 2>&1 || true
    rm -rf /nexcage-traced /nexcage-traced@hardened /nexcage-traced@small "$LINKS" 2>/dev/null || true
}
trap cleanup EXIT

if ! command -v k3s >/dev/null 2>&1; then
    echo "installing k3s (it was not here)"
    installed_here=yes
    # The extras a runtime test has no use for stay off, so less of the node
    # changes: no ingress controller, no load balancer, no metrics server.
    curl -sfL https://get.k3s.io | \
        INSTALL_K3S_VERSION="$K3S_VERSION" \
        INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --disable=metrics-server --write-kubeconfig-mode=644" \
        sh - >/tmp/k3s-install.log 2>&1 || {
            tail -20 /tmp/k3s-install.log >&2
            fail "k3s would not install"
        }
else
    echo "k3s is already here; leaving the installation alone"
fi
echo "ok: $(k3s --version | head -1)"

# k3s builds its containerd configuration from a template; the shipped one
# adds one runtime to whatever it would have written, rather than replacing
# it. Only the binary differs here: the trace wrapper instead of
# /usr/local/bin/nexcage.
TMPL=/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl
mkdir -p "$(dirname "$TMPL")"
sed 's|"/usr/local/bin/nexcage"|"/nexcage-traced"|' "$NODE_FILES/k3s-config-v3.toml.tmpl" > "$TMPL"
grep -q '"/nexcage-traced"' "$TMPL" \
    || fail "$NODE_FILES/k3s-config-v3.toml.tmpl no longer names /usr/local/bin/nexcage"
# One handler per profile, as docs/INSTALL.md adds them.
for p in hardened small; do
    cat >> "$TMPL" <<EOT

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-$p]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-$p.options]
  BinaryName = "/nexcage-traced@$p"
EOT
done
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
k apply -f "$NODE_FILES/runtimeclass.yaml" >/dev/null
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
    grep -E "^nexcage-traced " "$TRACE" | grep -qE " $verb( |$)" || {
        echo "what nexcage was asked:" >&2
        sed 's/[0-9a-f]\{64\}/<id>/g' "$TRACE" >&2
        fail "the kubelet's containerd never sent '$verb'"
    }
done
echo "ok: nexcage was asked create, start, exec and delete"

# --- Isolation profiles ---------------------------------------------------
# Two classes, one per profile handler. The pods differ the way the profiles
# do; every value is read from inside the pod.
k apply -f - >/dev/null <<YAML
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: nexcage-hardened }
handler: nexcage-hardened
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: nexcage-small }
handler: nexcage-small
YAML
echo "ok: RuntimeClass/nexcage-hardened and RuntimeClass/nexcage-small"

# hardened requires a user namespace and a seccomp filter, so the pod asks for
# both; its 2Gi limit is more than the profile's 1G. small requires seccomp
# only and the pod sets no limit, so the profile's 256M is the limit.
profile_pod() {  # profile_pod <name> <class> <extra spec line>
    cat <<YAML
apiVersion: v1
kind: Pod
metadata: { name: $1 }
spec:
  runtimeClassName: $2
  restartPolicy: Never
  $3
  securityContext: { seccompProfile: { type: RuntimeDefault } }
  containers:
  - name: app
    image: $POD_IMAGE
    command: ["/bin/sh", "-c", "sleep 600"]
YAML
}
{ profile_pod nexcage-hardened nexcage-hardened "hostUsers: false"
  echo "    resources: { limits: { memory: 2Gi } }"; } | k apply -f - >/dev/null
profile_pod nexcage-small nexcage-small "" | k apply -f - >/dev/null
for pod in nexcage-hardened nexcage-small; do
    if ! k wait --for=condition=Ready "pod/$pod" --timeout=180s >/dev/null 2>&1; then
        k describe pod "$pod" 2>&1 | tail -25 >&2
        fail "pod $pod never became Ready"
    fi
done
echo "ok: a pod under each profile is Ready"

in_pod() { k exec "pod/$1" -- sh -c "$2"; }
status_field() { in_pod "$1" "sed -n 's/^$2:[[:space:]]*//p' /proc/$3/status"; }
bit() { echo $(( (0x$1 >> $2) & 1 )); }
# expect <pod> <what> <got> <want>
expect() { [ "$3" = "$4" ] || fail "$1: $2 is '$3', not '$4'"; }

# The user namespace: hardened maps root to an unprivileged host range,
# small runs in the host's.
set -- $(in_pod nexcage-hardened "head -1 /proc/self/uid_map")
[ "${1:-}" = 0 ] && [ "${2:-0}" != 0 ] || fail "nexcage-hardened: uid_map '$*' maps root to the host's root"
set -- $(in_pod nexcage-small "head -1 /proc/self/uid_map")
expect nexcage-small uid_map "$*" "0 0 4294967295"
echo "ok: uid_map: nexcage-hardened in a user namespace, nexcage-small in the host's"

for pod in nexcage-hardened nexcage-small; do
    expect $pod "Seccomp of pid 1" "$(status_field $pod Seccomp 1)" 2
done
echo "ok: both run under a seccomp filter (Seccomp: 2)"

# Capabilities of the container's process and of a process kubectl exec
# starts: containerd builds the second from its own copy of the spec, from
# before the profile narrowed it, so it is checked separately.
for pid in 1 self; do
    c=$(status_field nexcage-hardened CapBnd $pid)
    for b in 13 18 27; do  # NET_RAW, SYS_CHROOT, MKNOD
        expect nexcage-hardened "bit $b of CapBnd of $pid ($c)" "$(bit "$c" $b)" 0
    done
    expect nexcage-hardened "CAP_KILL in CapBnd of $pid ($c)" "$(bit "$c" 5)" 1
    c=$(status_field nexcage-small CapBnd $pid)
    expect nexcage-small "CAP_NET_RAW in CapBnd of $pid ($c)" "$(bit "$c" 13)" 0
    expect nexcage-small "CAP_MKNOD in CapBnd of $pid ($c)" "$(bit "$c" 27)" 1
done
echo "ok: capabilities: hardened lost NET_RAW, SYS_CHROOT and MKNOD, small only NET_RAW; kubectl exec gets no more"

expect nexcage-hardened memory.max "$(in_pod nexcage-hardened 'cat /sys/fs/cgroup/memory.max')" 1073741824
expect nexcage-hardened pids.max "$(in_pod nexcage-hardened 'cat /sys/fs/cgroup/pids.max')" 1024
expect nexcage-small memory.max "$(in_pod nexcage-small 'cat /sys/fs/cgroup/memory.max')" 268435456
expect nexcage-small pids.max "$(in_pod nexcage-small 'cat /sys/fs/cgroup/pids.max')" 256
echo "ok: cgroup: hardened 1G (the pod asked 2Gi) and 1024 pids, small 256M and 256 pids"

# A pod that does not give hardened what it requires is refused, and says so
# where its author looks.
profile_pod nexcage-refused nexcage-hardened "" | k apply -f - >/dev/null
i=0
until k get events --field-selector involvedObject.name=nexcage-refused \
        -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' 2>/dev/null \
        | grep -q "requires a user namespace"; do
    i=$((i + 1))
    [ "$i" -gt 45 ] && { k describe pod nexcage-refused 2>&1 | tail -15 >&2; fail "nexcage-refused shows no 'requires a user namespace' event"; }
    sleep 2
done
[ "$(k get pod nexcage-refused -o jsonpath='{.status.phase}')" != Running ] \
    || fail "nexcage-refused is Running"
echo "ok: a pod without hostUsers: false under nexcage-hardened is refused, and its events say why"

k delete pod nexcage-hardened nexcage-small nexcage-refused --wait=true --timeout=120s >/dev/null 2>&1 \
    || fail "the profile pods would not go away"
for p in hardened small; do
    grep -qE "^nexcage-traced@$p .* create( |$)" "$TRACE" || fail "nexcage@$p was never asked create"
done
echo "ok: the profile pods were deleted; each came through its nexcage@<profile> handler"

echo
echo "what Kubernetes asked the runtime, on this node:"
sed 's/[0-9a-f]\{64\}/<id>/g; s|\(--bundle \)[^ ]*|\1<dir>|g; s|\(--pid-file \)[^ ]*|\1<file>|g; s|\(--log \)[^ ]*|\1<log>|g; s|\(--root \)[^ ]*|\1<root>|g' "$TRACE" | sort -u | head -10

echo
echo "PASS: Kubernetes scheduled a pod onto nexcage, and a pod under each of two profiles, on $(hostname)"
