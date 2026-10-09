# NexCage

[![CI](https://github.com/CageForge/nexcage/actions/workflows/ci.yml/badge.svg)](https://github.com/CageForge/nexcage/actions/workflows/ci.yml)
[![crun backend build](https://github.com/CageForge/nexcage/actions/workflows/crun_build.yml/badge.svg)](https://github.com/CageForge/nexcage/actions/workflows/crun_build.yml)
[![Proxmox E2E](https://github.com/CageForge/nexcage/actions/workflows/proxmox_e2e.yml/badge.svg)](https://github.com/CageForge/nexcage/actions/workflows/proxmox_e2e.yml)
[![Release](https://img.shields.io/github/v/release/CageForge/nexcage?sort=semver)](https://github.com/CageForge/nexcage/releases)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

**An OCI runtime for Proxmox VE.** nexcage wears two faces, and they share one
binary:

- **A command line for LXC containers on a Proxmox VE cluster.** It creates,
  starts, stops, deletes and inspects them through `pct` and the Proxmox API,
  from templates, OCI bundles, or OCI registry images.
- **An OCI runtime that a container engine drives**, the way runc and crun are
  driven. podman, `ctr`, containerd's CRI and CRI-O all run containers on it,
  and Kubernetes schedules pods onto it with a `RuntimeClass`.

## Status

As of **0.17.0**, on amd64, running on the Proxmox VE host as root:

| | |
|---|---|
| **Proxmox LXC** | `create`, `start`, `stop`, `delete`, `list`, `state`, `kill`, `exec` — on any node of the cluster, except `kill` and `exec`, which work on the host the container is on. `create --node` places a container on a chosen one; `run` (create, then start) always creates on this host |
| **Templates** | `images`, `pull`, `rmi` for what a container is created from |
| **Freezing, resizing** | `pause` and `resume`, the cgroup freezer, on both backends — on Proxmox LXC only on the host the container is on; `state` reports `paused`, which `pct status` cannot, for a container on this host (one frozen on another node shows as `running`). `update` changes a running container's limits — through libcrun, or `pct set` in its own terms |
| **As an OCI runtime** | the runtime-spec command line — `create --bundle`, `start`, `state`, `kill`, `delete`, `exec`, `ps`, `features`, `update`, with `--root`, `--console-socket`, `--pid-file`, `--log`. Verified against podman, `ctr`, containerd's CRI, CRI-O and a kubelet |
| **In Kubernetes** | a pod with `runtimeClassName: nexcage` runs on a node, with an address from the cluster's CNI, `kubectl logs` and `kubectl exec`; installed from the files a release ships ([INSTALL.md](docs/INSTALL.md#a-kubernetes-node-on-proxmox-ve-since-0160)) |
| **Isolation profiles** | Named in the configuration file by the node's administrator. A profile can require a user namespace or seccomp, drop capabilities, and lower memory and pids limits. A `RuntimeClass` picks one by the handler's program name, `nexcage@<profile>`. A profile names the crun backend ([CLI_REFERENCE.md](docs/CLI_REFERENCE.md#isolation-profiles), [INSTALL.md](docs/INSTALL.md#an-isolation-profile-per-runtimeclass-since-0170)) |
| **Conformance** | runtime-spec validation 33 of 58 and critest 110 of 142, in CI; every failure also fails with crun run directly ([release notes](docs/releases/NOTES_v0.16.0.md#conformance-on-record)) |
| **Registries** | Images are pulled through Proxmox. A private registry takes a `skopeo login --authfile /root/.config/containers/auth.json` on each node that pulls ([INSTALL.md](docs/INSTALL.md#images-from-a-private-registry)) |
| **Not there** | `events` — no engine has asked for it |

Proxmox VE 9.x. Pulling from a registry needs 9.1 or later. Proxmox VE 8.x is
not supported: earlier releases ran on it, but the E2E suite never did, and
Proxmox ended its own support for 8.x in August 2026.

## System Requirements & Prerequisites

`nexcage` runs directly on the Proxmox VE host as `root`.

### Host Environment
* **OS:** Proxmox VE 9.x (amd64 architecture).
* **Privileges:** `root` access on the host.
* **Base Proxmox Tooling:** `pct`, `pvesh`, and `pveversion` (included by default with Proxmox VE).

### System Dependencies

The release's binary links the crun backend's libraries dynamically and does
not start without them. The `.deb` pulls them through its `Depends`; for the
bare binary:

```bash
apt install libjson-c5 libseccomp2 libcap2 libsystemd0
```

### Build Dependencies (Source builds only)
* **Zig Compiler:** Version `0.15.1` exactly: `build.zig.zon` and CI pin it.
* **Packaging Utilities:** `dpkg-deb`, `objdump`, `gzip`, `du`, `cut`, `tr` (for building `.deb` packages via `scripts/build_deb_local.sh`).
* **Docker:** builds the binary with the crun backend, through the Dockerfile. `scripts/build_deb_local.sh` needs it unless given a built binary as `NEXCAGE_BIN`.

## Install

```bash
VERSION=0.17.0
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/nexcage-$VERSION-amd64.deb
wget https://github.com/CageForge/nexcage/releases/download/v$VERSION/checksums.txt
sha256sum --ignore-missing -c checksums.txt
apt install ./nexcage-$VERSION-amd64.deb
```

**One binary, both backends** (since 0.17.0). The binary manages LXC
containers on Proxmox VE, and it is the OCI runtime that containerd, CRI-O,
podman and a kubelet drive, with the crun backend built in. The `.deb` pulls
the libraries that backend links: `libjson-c5`, `libseccomp2`, `libcap2` and
`libsystemd0`. Releases 0.11.2 to 0.16.0 carried it in a separate `-crun`
binary.

Details, the bare binary and source builds: [docs/INSTALL.md](docs/INSTALL.md).

## Use it as a Proxmox command line

```bash
nexcage images                      # templates the cluster can create from
nexcage pull docker.io/library/redis:7 --storage shared-rdma

nexcage create --name web-1 local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst
nexcage start web-1
nexcage state web-1                 # OCI state JSON on stdout
nexcage exec web-1 -- sh -c 'echo $HOSTNAME'
nexcage snapshot web-1 before-upgrade   # through pct, on zfs or lvm-thin
nexcage list                        # every node of the cluster
nexcage delete web-1

nexcage create --name web-2 --node titan shared-rdma:vztmpl/redis_7.tar
```

Containers are addressed by name, which becomes the hostname and must be unique
across the cluster; `state` also accepts a VMID. `exec`, `kill`, `pause`,
`resume` and the `pid` in `state` work on the host the container is on, and
say so for one elsewhere.
Exit status is `0` for success, `1` when the operation failed, `2` for invalid
usage — except `exec`, which exits with the status of the command it ran.

Every command, option and exit code: [docs/CLI_REFERENCE.md](docs/CLI_REFERENCE.md).

## Use it as an OCI runtime

A container engine never passes `--runtime`, so the configuration has to route
to the OCI backend:

```json
{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
```

Then name it wherever the engine names a runtime:

```toml
# containerd
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage]
  runtime_type = "io.containerd.runc.v2"
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage.options]
    BinaryName = "/usr/bin/nexcage"
```

```bash
podman --runtime /usr/bin/nexcage run --rm docker.io/library/alpine:3 echo hi
kubectl apply -f pod.yaml     # runtimeClassName: nexcage
```

A Kubernetes node on Proxmox VE, step by step, from the files a release
ships (routing, k3s, containerd and CRI-O examples, the `RuntimeClass`):
[docs/INSTALL.md](docs/INSTALL.md#a-kubernetes-node-on-proxmox-ve-since-0160).
How it was verified, engine by engine, and what Kubernetes asks a runtime:
[docs/KUBERNETES_INTEGRATION.md](docs/KUBERNETES_INTEGRATION.md).

## Configure

For standard Proxmox LXC management:
```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.json /etc/nexcage/config.json
```
For a container engine (containerd, CRI-O, a kubelet):
```bash
mkdir -p /etc/nexcage
cp /usr/share/doc/nexcage/examples/config.oci.example.json /etc/nexcage/config.json
```
On a host that already has a configuration, add the example's `runtime.routing`
and `profiles` to that file instead of replacing it.

nexcage reads the file given with `--config <path>`, or else the first of
`./config.json`, `/etc/nexcage/config.json` and `/etc/nexcage/nexcage.json`
that exists. A file that does not parse is an error; a file declaring
`ociVersion` is skipped in that search, and refused when named with
`--config`, because that is an OCI runtime spec and not a configuration.

The table below is every key there is. **Since 0.17.0 anything else refuses the
file**: a key nexcage does not read, a value of the wrong type, a runtime or
log level it does not know. The message names the file and the key, and
nothing runs.

```json
{
  "network": { "bridge": "vmbr0" },
  "proxmox": {
    "storage": "local-lvm",
    "rootfs_size_gb": 8,
    "unprivileged": true
  }
}
```

| Key | Default | Effect |
|---|---|---|
| `network.bridge` | `vmbr0` | Bridge for `eth0`, which gets its address by DHCP |
| `proxmox.storage` | unset: pct uses `local` | Storage for the root filesystem. Set it — stock LVM installs refuse containers on `local` |
| `proxmox.rootfs_size_gb` | `8` | Root filesystem size, used when `storage` is set |
| `proxmox.unprivileged` | `true` | Create unprivileged containers, as the Proxmox VE web UI does. Images from a registry always run unprivileged |
| `proxmox.ostype` | detected by pct | `--ostype` for new containers |
| `runtime.routing` | Proxmox LXC | Which backend a container goes to. A pattern is a regular expression only when it starts with `^` or ends with `$`, so `".*"` matches nothing — use `"*"` |
| `profiles` | none | Isolation profiles `create` applies on the crun backend, named by `nexcage@<profile>` or `--profile`; see [CLI_REFERENCE.md](docs/CLI_REFERENCE.md#isolation-profiles) |
| `runtime.log_level` (or top-level `log_level`, which wins) | `info` | `debug`, `info`, `warn` or `error`; since 0.17.0 any other value refuses the file (it used to mean `info`). `debug` also turns on the lines `--debug` writes to stderr. `NEXCAGE_LOG_LEVEL`, then `--log-level`, override it, `info` included |
| `runtime.log_path` (or top-level `log_file`, which wins) | unset | The same as `--log-file`: the startup line, each command's start line and, when the command succeeds, its completion lines go to this file as well as to stderr. The command's own log lines do not, and this is not the runtime log a container engine passes with `--log` |

## Documentation

| | |
|---|---|
| [Install](docs/INSTALL.md) | Releases, source builds, what each binary needs |
| [CLI reference](docs/CLI_REFERENCE.md) | Every command, option and exit code |
| [Kubernetes integration](docs/KUBERNETES_INTEGRATION.md) | The runtime-spec command line, the engines, and a pod on a node |
| [Architecture](docs/architecture/OVERVIEW.md) | How the backends and the router fit together |
| [Troubleshooting](docs/TROUBLESHOOTING_GUIDE.md) | When something does not work |
| [Release notes](docs/releases/) | What changed, release by release |

Rendered at [nexcage.cageforge.com](https://nexcage.cageforge.com).

## Development

```bash
zig build test --summary all       # Zig 0.15.1
zig build && bash tests/sim/run.sh # the Proxmox command line, against fakes
```

The simulator runs nexcage against fake `pct`, `pvesh` and `pveversion` in a
user namespace, so the Proxmox paths can be exercised on a laptop. The crun
backend links vendored libcrun and is built through the Dockerfile:

```bash
docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:crun .
```

CI builds and tests on GitHub-hosted runners, builds the crun backend and runs a
pod on it through containerd's CRI, and runs the container lifecycle on a
self-hosted Proxmox VE node.

Guides: [docs/DEV_QUICKSTART.md](docs/DEV_QUICKSTART.md),
[TESTING.md](TESTING.md), [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md),
[docs/DEVELOPMENT_WORKFLOW.md](docs/DEVELOPMENT_WORKFLOW.md).

## Contributing

Issues and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md); questions and bug reports belong in
[GitHub Issues](https://github.com/CageForge/nexcage/issues).

Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please report vulnerabilities as [SECURITY.md](SECURITY.md) describes, rather
than in a public issue.

## Project

- Maintainers: [MAINTAINERS.md](MAINTAINERS.md)
- Governance: [GOVERNANCE.md](GOVERNANCE.md)
- Changes: [CHANGELOG.md](CHANGELOG.md)
- Roadmap: [ROADMAP.md](ROADMAP.md)
- Open-source compliance: [docs/COMPLIANCE_CNCF_CHECKLIST.md](docs/COMPLIANCE_CNCF_CHECKLIST.md)

## License

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Built with `-Denable-backend-crun=true`, nexcage compiles and links the
`src/libcrun` sources of a vendored [crun](https://github.com/containers/crun),
whose file headers state LGPL-2.1-or-later, and the `src` sources of crun's
libocispec submodule (the OCI spec parsers, most of them generated at build
time), which carries its own license in `libocispec/COPYING` (GPL-3.0 for the
generator, with a special exception for its generated parser files). crun's
repository as a whole is GPL-2.0 for its own command-line tool, which nexcage
does not build. Every released binary since 0.17.0, and the `.deb`, is that
build. A plain `zig build` links none of it.
