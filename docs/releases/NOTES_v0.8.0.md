# nexcage 0.8.0 — MVP

nexcage 0.8.0 is the first release scoped as a minimal, working product: a
command-line lifecycle for LXC containers on a single Proxmox VE host.

## What works

- `create`, `start`, `stop`, `delete`, `list`, `state`, `kill`, `run`
- Images: Proxmox templates (`<storage>:vztmpl/…`), OCI bundle directories,
  and OCI registry references on Proxmox VE 9.1+
- Configuration of bridge, root filesystem storage and size, OS type and
  unprivileged mode (`/etc/nexcage/config.json`)
- One-line errors and meaningful exit codes (0 success, 1 failure, 2 usage)

The lifecycle is exercised by the Proxmox E2E job on a self-hosted Proxmox VE
runner, through the nexcage binary.

## Not in this release

- containerd / CRI integration: nexcage does not implement the runc-compatible
  CLI that containerd shims use
- The crun and runc backends are opt-in build options and experimental
- The `--config` flag is parsed but not honoured; configuration is read from
  `./config.json`, `/etc/nexcage/config.json` or `/etc/nexcage/nexcage.json`
- `state` reports `pid: 0`
- Commands see containers on the local node only

## Upgrading from 0.7.x

- **Build.** `zig build` no longer includes the crun backend or needs its
  submodules. Build it explicitly with `-Denable-backend-crun=true`, or through
  the Dockerfile.
- **Bridge.** The default bridge is `vmbr0`, not `vmbr50`. Set
  `"network": { "bridge": "…" }` if you relied on the old default.
- **Storage.** Set `"proxmox": { "storage": "local-lvm" }` (or your container
  storage). Without it pct uses `local`, which stock LVM installs refuse for
  container volumes.
- **VMIDs** are allocated with `pvesh get /cluster/nextid`; containers created
  by 0.7.x keep their VMIDs and are still found by name.
- **stop** is a clean shutdown with a 60 second timeout, then a forced stop.
  Use `kill <name> SIGKILL` for an immediate stop.
- **Output.** Log lines moved from stdout to stderr. Scripts that parse
  `list` or `state` output no longer see them.
- **Exit codes.** Usage errors exit with 2.
- **Privileges.** New containers are still privileged unless
  `"proxmox": { "unprivileged": true }` is set.

See `CHANGELOG.md` for the full list of changes and fixes.
