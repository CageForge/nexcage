# Installing nexcage

nexcage runs on the Proxmox VE host (9.x, amd64) as root. It needs
`pct`, `pvesh` and `pveversion`, which Proxmox VE provides.

Proxmox VE 8.x is not supported. Releases before 0.14.0 ran on it, but no
test ever did — the E2E suite runs on 9.x — and Proxmox ended support for 8.x
in August 2026, with Debian 12. nexcage does not refuse an 8.x host; it no
longer promises anything there.

## From a release

Each GitHub release carries one binary, `nexcage-<version>-amd64`, the package
`nexcage-<version>-amd64.deb` that installs it, SBOMs, `provenance.json` and
`checksums.txt`.

**Since 0.17.0 the binary has both backends** (#380). It manages LXC
containers on Proxmox VE, and it is the OCI runtime a container engine drives,
with the crun backend built in. Releases 0.11.2 to 0.16.0 carried that backend
in a second binary, `nexcage-<version>-amd64-crun`, and the `.deb` held the
binary without it. There is no `-crun` asset any more.

### .deb

```bash
VERSION=0.17.0
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64.deb
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
apt install ./nexcage-$VERSION-amd64.deb
```

The package installs:
- `/usr/bin/nexcage`;
- a man page and bash completion;
- two example configurations in `/usr/share/doc/nexcage/examples/`:
  `config.json` for the command line, and `config.oci.example.json` for a
  container engine.

Its `Depends` brings in the libraries the crun backend links: `libjson-c5`,
`libseccomp2`, `libcap2` and `libsystemd0`.

### Binary

```bash
VERSION=0.17.0
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
apt install libjson-c5 libseccomp2 libcap2 libsystemd0
install -m 0755 nexcage-$VERSION-amd64 /usr/local/bin/nexcage
```

The binary links libcrun's dependencies dynamically. Without one of them it
does not start at all, with `error while loading shared libraries:
libjson-c.so.5`. That is why the `apt install` line is there.

### For a container engine

A container engine never passes `--runtime`, so the configuration has to send
the containers it creates to the crun backend. `config.oci.example.json` does
that, and defines two isolation profiles:

```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.oci.example.json /etc/nexcage/config.json
```

If the host already has a configuration for its LXC containers, add the
example's `runtime.routing` and `profiles` to that file instead of replacing
it. Routing decides only where `create` and `run` put a new container, so a
`create` typed by hand then makes a crun container too. Give it
`--runtime lxc` for an LXC one.

A routing pattern is a regular expression only when it starts with `^` or ends
with `$`; `".*"` is read as a wildcard and matches nothing. Use `"*"`.

## A Kubernetes node on Proxmox VE (since 0.16.0)

A node whose kubelet runs pods on nexcage needs four things:

1. nexcage, from the `.deb` (above), at `/usr/bin/nexcage`;
2. the routing configuration;
3. nexcage as a runtime of the node's container engine;
4. a `RuntimeClass` in the cluster, which a pod names.

The files for 2 to 4 are in the release's tag. The engine's configuration is
yours: they are examples, and nothing installs them for you. A pod runs on
nexcage only when it names the class; the node's default runtime is unchanged.
`k8s_e2e.yml` builds a node this way on every release tag, from these same
files, and runs a pod on it.

```bash
VERSION=0.17.0
SRC=https://raw.githubusercontent.com/CageForge/nexcage/v$VERSION
```

**Routing.** The routing and the profiles from the `.deb`'s example, as
under *For a container engine* above:

```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.oci.example.json /etc/nexcage/config.json
```

**The engine.** One of:

```bash
# k3s, whose containerd is 2.x: it writes containerd's configuration from this
# template when it starts, so put it in place before installing k3s, or
# restart k3s after.
mkdir -p /var/lib/rancher/k3s/agent/etc/containerd
curl -fsSLo /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl \
  "$SRC/deploy/kubernetes/node/k3s-config-v3.toml.tmpl"
systemctl restart k3s

# containerd 2.x: merge this into /etc/containerd/config.toml, then
curl -fsSL "$SRC/deploy/kubernetes/node/containerd.toml"
systemctl restart containerd

# CRI-O
curl -fsSLo /etc/crio/crio.conf.d/10-nexcage.conf "$SRC/deploy/kubernetes/node/crio.conf"
systemctl restart crio
```

**The RuntimeClass**, once per cluster (on k3s, `kubectl` reads
`/etc/rancher/k3s/k3s.yaml`):

```bash
kubectl apply -f "$SRC/deploy/kubernetes/node/runtimeclass.yaml"
```

**A pod on it:**

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: nexcage-hello }
spec:
  runtimeClassName: nexcage
  restartPolicy: Never
  containers:
  - name: hello
    image: registry.k8s.io/e2e-test-images/busybox:1.29-4
    command: ["/bin/sh", "-c", "echo hello from nexcage; sleep 3600"]
YAML
kubectl wait --for=condition=Ready pod/nexcage-hello --timeout=180s
kubectl logs nexcage-hello
kubectl exec nexcage-hello -- uname -r
crictl pods --name nexcage-hello      # the RUNTIME column says nexcage; k3s crictl on k3s
kubectl delete pod nexcage-hello
```

A pod that stays `ContainerCreating` says why in `kubectl describe pod`. The
two usual causes are a binary without the crun backend (`nexcage --runtime
crun features` fails) and a missing library (`nexcage version` fails).

To take it off the node: delete the `RuntimeClass` once no pod names it, remove
the template, the `containerd.toml` entry or the CRI-O drop-in, restart the
engine, and remove `/etc/nexcage/config.json` and the binary.

### An isolation profile per RuntimeClass (since 0.17.0)

A profile narrows what every pod of a class may have: it can require a user
namespace and a seccomp filter, drop capabilities, and lower memory and pids
limits. [CLI_REFERENCE.md](CLI_REFERENCE.md#isolation-profiles) describes the
keys. `config.oci.example.json` defines two:

| Profile | Requires | Drops | Memory | Pids |
|---|---|---|---|---|
| `hardened` | a user namespace and a seccomp filter | `CAP_NET_RAW`, `CAP_MKNOD`, `CAP_SYS_CHROOT` | 1G | 1024 |
| `small` | a seccomp filter | `CAP_NET_RAW` | 256M | 256 |

The engine names a profile by the program it runs, so each profile is one more
runtime handler whose binary is `nexcage@<profile>`:

```bash
ln -s /usr/bin/nexcage /usr/local/bin/nexcage@hardened

# k3s: append to the template above, then restart k3s
cat >> /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl <<'EOF'

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-hardened]
  runtime_type = "io.containerd.runc.v2"

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-hardened.options]
  BinaryName = "/usr/local/bin/nexcage@hardened"
EOF
systemctl restart k3s

kubectl apply -f - <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: nexcage-hardened }
handler: nexcage-hardened
YAML
```

containerd 2.x takes the same two tables in `/etc/containerd/config.toml`. For
CRI-O, add a `[crio.runtime.runtimes.nexcage-hardened]` table whose
`runtime_path` is `/usr/local/bin/nexcage@hardened`. `k8s_e2e.yml` checks only
the k3s way.

A pod under `hardened` has to ask for what it requires:

```yaml
spec:
  runtimeClassName: nexcage-hardened
  hostUsers: false                                          # a user namespace
  securityContext: { seccompProfile: { type: RuntimeDefault } }
```

Without them it stays `ContainerCreating`. `kubectl describe pod` gives the
reason, for example "profile 'hardened' requires a user namespace … set
hostUsers: false on the pod". A profile only takes away: a pod's 2Gi limit
under `hardened` becomes 1G, while a 512M limit stays 512M. `kubectl exec`
gets no capability the pod's container lacks.

## From source

```bash
git clone https://github.com/CageForge/nexcage.git
cd nexcage
zig build -Doptimize=ReleaseSafe          # Zig 0.15.1
install -m 0755 zig-out/bin/nexcage /usr/local/bin/nexcage
```

A plain `zig build` has the Proxmox LXC backend only; the crun backend needs
libcrun's sources and generated headers, which the Dockerfile brings:
`docker build --build-arg BUILD_FLAGS="-Denable-backend-crun=true -Dcpu=baseline" .`

To build the `.deb` yourself, run `bash scripts/build_deb_local.sh`. It needs
`dpkg-deb`, `objdump` and docker, and writes
`dist/nexcage-<version>-amd64.deb`. To pack a binary you built with the crun
backend already, pass it as `NEXCAGE_BIN=<path>`.

## Configure

Depending on how you intend to use `nexcage`, choose the appropriate base configuration:

1. **For standalone Proxmox LXC management (CLI mode):**

```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.json /etc/nexcage/config.json   # .deb install
# or: cp packaging/config/config.json /etc/nexcage/config.json            # source tree
```
2. **For a container engine (containerd, CRI-O, a kubelet):**

A container engine never passes `--runtime`, so routing has to put the
containers it creates on the crun backend. On a host that already has a
configuration, add the example's `runtime.routing` and `profiles` to it instead,
as "For a container engine" above describes.

```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.oci.example.json /etc/nexcage/config.json
```

Set at least `proxmox.storage` to a storage that holds container volumes
(`pvesm status` lists them) and `network.bridge` to your bridge. The keys are
described in the README.

You also need a container template, for example:

```bash
pveam update
pveam available --section system
pveam download local debian-12-standard_12.7-1_amd64.tar.zst
```

### Images from a private registry

`pull`, `create <reference>` and `run <reference>` have Proxmox pull the image,
and Proxmox runs `skopeo copy` with no credentials of its own. skopeo finds
them in root's auth file on the node that pulls, so log in there once:

```bash
skopeo login --authfile /root/.config/containers/auth.json registry.example.com
```

- Give `--authfile`. skopeo's default for root is `/run/containers/0/auth.json`,
  which is on tmpfs and gone after a reboot.
- Log in on every node that pulls. With `--node titan` the pull runs on titan,
  and titan's file is the one read.
- The file holds the credentials encoded, not encrypted. Use a token that can
  only read.

A refused login comes back from nexcage with the registry's reason and the
`skopeo login` line for that node. The Proxmox E2E checks on every run that a
pull reads this file (#309).

## Verify

```bash
nexcage version
nexcage list
nexcage create --name smoke-1 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
nexcage start smoke-1 && nexcage state smoke-1
nexcage stop smoke-1 && nexcage delete smoke-1
```

## Remove

```bash
apt remove nexcage              # .deb install
rm /usr/local/bin/nexcage       # binary install
rm -rf /etc/nexcage /run/nexcage
```

Containers created with nexcage are ordinary Proxmox VE containers and are not
touched when nexcage is removed.
