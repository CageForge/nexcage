# NexCage

Command-line lifecycle for LXC containers on a Proxmox VE host. nexcage
creates, starts, stops, deletes and inspects containers through `pct` and
`pvesh`, from Proxmox templates, OCI bundles, or — on Proxmox VE 9.1 and later
— OCI registry images.

## Status

Version 0.8.0 is the MVP scope:

| | |
|---|---|
| **Supported** | `create`, `start`, `stop`, `delete`, `list`, `state`, `kill`, `run` for LXC containers on one Proxmox VE 8.x / 9.x host |
| **Images** | `<storage>:vztmpl/…` templates, OCI bundle directories, OCI registry references (Proxmox VE 9.1+) |
| **Not yet** | containerd / CRI integration, containers on other cluster nodes |
| **Opt-in, experimental** | crun and runc backends, Proxmox VM backend |

- Architecture: amd64 (x86_64)
- Runs on the Proxmox VE host itself, as root

## Build

The default build needs only Zig 0.15.1. The first build may download the
pinned `oci-specs-zig` package declared in `build.zig.zon`.

```bash
zig build -Doptimize=ReleaseSafe
sudo install -m 0755 zig-out/bin/nexcage /usr/local/bin/nexcage
nexcage version
```

Release binaries and a `.deb` are attached to GitHub releases; see
[docs/INSTALL.md](docs/INSTALL.md).

## Configure

nexcage reads the file given with `--config <path>`, or else the first of
`./config.json`, `/etc/nexcage/config.json` and `/etc/nexcage/nexcage.json`
that exists. A file that does not parse is an error. Without any file the
defaults below apply.

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

## Use

```bash
# From a Proxmox template
nexcage create --name web-1 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
nexcage start web-1
nexcage state web-1          # OCI state JSON on stdout
nexcage list
nexcage stop web-1           # clean shutdown, forced after 60 seconds
nexcage delete web-1

# From an OCI registry (Proxmox VE 9.1+); pulled to storage "local", then started
nexcage run --name cache-1 docker.io/library/redis:7

# Signals go to the container's init, from the host
nexcage kill web-1 SIGKILL
```

- Containers are addressed by name, which becomes the hostname and must be
  unique. `state` also accepts a VMID.
- VMIDs come from `pvesh get /cluster/nextid`.
- Logs go to stderr. `--debug`, `--log-level <level>`, `--log-file <path>` and
  `--config <path>` go before or after the command.
- Exit status: `0` success, `1` the operation failed, `2` invalid usage.

Full reference: [docs/CLI_REFERENCE.md](docs/CLI_REFERENCE.md).

## crun backend (optional)

The crun backend links vendored libcrun and needs the `deps/crun` submodules
plus generated headers. The Dockerfile prepares all of that from a clean clone:

```bash
docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:crun .
```

## Development

```bash
zig build test --summary all
```

- Every `.zig` file under `tests/` and `src/` that declares a test is its own
  test step; a file that fails to compile fails by name.
- CI (`.github/workflows/ci.yml`) builds, tests and smoke-tests on
  GitHub-hosted runners. The Proxmox E2E job runs the container lifecycle
  through nexcage on a self-hosted Proxmox VE runner.

Guides: [docs/DEV_QUICKSTART.md](docs/DEV_QUICKSTART.md),
[TESTING.md](TESTING.md), [docs/CI_CD_SETUP.md](docs/CI_CD_SETUP.md),
[docs/architecture/OVERVIEW.md](docs/architecture/OVERVIEW.md).

## Security and policies

- Security policy: [SECURITY.md](SECURITY.md)
- Maintainers and governance: [MAINTAINERS.md](MAINTAINERS.md), [GOVERNANCE.md](GOVERNANCE.md)
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
