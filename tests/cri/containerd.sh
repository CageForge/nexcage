# Sourced, not run: containerd serving the CRI with nexcage as its runtime
# handler, on a CNI bridge, for pod_on_nexcage.sh and critest.sh. Every call
# the engine makes to the runtime is recorded in $TRACE.
#
# What is nexcage's and what is not: the engine creates the sandbox's network
# namespace, runs the CNI plugins in it, writes the OCI spec and captures the
# container's output. nexcage creates, starts, reports and deletes the
# container. The tests check the second list, and use the first as the setting.
#
# Needs: containerd, crictl, CNI plugins, and a privileged container with its
# own cgroup namespace. Run it as root. Leaves CONTAINERD_PID set; the caller
# stops it.

NEXCAGE=${NEXCAGE:-/usr/local/bin/nexcage}
SUBNET=${SUBNET:-10.88.0.0/16}
GATEWAY=${GATEWAY:-10.88.0.1}
TRACE=/tmp/cri-trace.log

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p /etc/nexcage /etc/containerd /etc/cni/net.d /var/log/pods/cri-test

# An engine never passes --runtime, so the configuration has to route to the
# OCI backend. A pattern is a regex only when it starts with ^ or ends with $.
printf '{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }' \
    > /etc/nexcage/config.json
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 40\n' \
    > /etc/crictl.yaml

# Controllers a sandbox's cgroup needs, delegated into this container's own.
# The cgroup holding our processes cannot enable them for its children. On
# cgroup v1 there is nothing to delegate.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    if [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
        mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
        for p in $(cat /sys/fs/cgroup/cgroup.procs 2>/dev/null); do
            echo "$p" > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || true
        done
        # One at a time: a write naming a controller the parent did not
        # delegate fails as a whole. Rootless podman delegates only cpu,
        # memory and pids.
        for c in cpu cpuset memory pids io; do
            echo "+$c" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
        done
    fi
    case "$(cat /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null)" in
        *cpu*) : ;;
        *) fail "the cpu controller is not delegated to this cgroup; a sandbox cannot be created" ;;
    esac
fi

cat > /etc/cni/net.d/10-nexcage-test.conflist <<JSON
{
  "cniVersion": "1.0.0",
  "name": "nexcage-test",
  "plugins": [
    { "type": "bridge", "bridge": "cni-nx0", "isGateway": true, "ipMasq": true,
      "ipam": { "type": "host-local",
                "ranges": [ [ { "subnet": "$SUBNET" } ] ],
                "routes": [ { "dst": "0.0.0.0/0" } ] } },
    { "type": "portmap", "capabilities": { "portMappings": true } },
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

# crun as a second handler, when the image has it: critest.sh runs the suite
# through it as well, to tell nexcage's failures from the setting's.
CRUN_RUNTIME=""
if CRUN=$(command -v crun); then
    CRUN_RUNTIME="[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.crun]
      runtime_type = 'io.containerd.runc.v2'
      snapshotter = 'native'
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.crun.options]
        BinaryName = '$CRUN'"
fi

# In a user namespace -- rootless podman -- the kernel will not let the shim
# lower oom_score_adj and AppArmor profiles cannot be loaded, so containerd
# has to be told not to try; it warns about both at startup. Only the initial
# namespace maps all of 0..4294967294 to itself.
USERNS_CRI=""
if ! awk 'NR == 1 && $1 == 0 && $2 == 0 && $3 == 4294967295 { f = 1 } END { exit !f }' /proc/self/uid_map; then
    USERNS_CRI="restrict_oom_score_adj = true
  disable_apparmor = true"
    echo "ok: running in a user namespace, so oom_score_adj and AppArmor are left alone"
fi

cat > /etc/containerd/config.toml <<TOML
version = 3

[plugins.'io.containerd.cri.v1.images']
  # overlay on overlay is not available inside a container; native always is.
  snapshotter = 'native'
  # containerd 2.x pulls through the transfer service by default, which has no
  # unpack configuration for the native snapshotter and fails with "no unpack
  # platforms defined".
  use_local_image_pull = true

[plugins.'io.containerd.cri.v1.runtime']
  $USERNS_CRI
  [plugins.'io.containerd.cri.v1.runtime'.containerd]
    default_runtime_name = 'nexcage'
    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage]
      runtime_type = 'io.containerd.runc.v2'
      snapshotter = 'native'
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage.options]
        BinaryName = '/nexcage-traced'
    $CRUN_RUNTIME

  [plugins.'io.containerd.cri.v1.runtime'.cni]
    bin_dirs = ['/usr/lib/cni', '/opt/cni/bin']
    conf_dir = '/etc/cni/net.d'
TOML

containerd >/tmp/containerd.log 2>&1 &
CONTAINERD_PID=$!

i=0
until crictl version >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && { tail -20 /tmp/containerd.log >&2; fail "containerd did not come up"; }
    sleep 1
done
echo "ok: containerd is serving the CRI"
