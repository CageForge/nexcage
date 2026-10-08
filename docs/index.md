# NexCage Documentation

nexcage is an OCI runtime for Proxmox VE, and it wears two faces from one
binary.

**A command line for LXC containers on a Proxmox VE cluster.** It creates,
starts, stops, deletes and inspects them through `pct` and the Proxmox API, on
any node of the cluster, from templates, OCI bundles or — on Proxmox VE 9.1 and
later — OCI registry images.

**An OCI runtime a container engine drives**, the way runc and crun are driven.
podman, `ctr`, containerd's CRI and CRI-O all run containers on it, and
Kubernetes schedules pods onto it with a `RuntimeClass`.

## Start here

- [Install](INSTALL.md) — releases, source builds, and which of the two
  published binaries you want
- [CLI Reference](CLI_REFERENCE.md) — every command, option and exit code
- [Kubernetes integration](KUBERNETES_INTEGRATION.md) — the runtime-spec command
  line, the engines it was verified against, and a pod on a real node

## Going further

- [Architecture](architecture/OVERVIEW.md) — the backends and the router
- [Troubleshooting](TROUBLESHOOTING_GUIDE.md) — when something does not work
- [Dev Quickstart](DEV_QUICKSTART.md) — build and test from source
- [CI/CD](CI_CD_SETUP.md) — the workflows and the self-hosted Proxmox runner
- [Release notes](releases/NOTES_v0.16.0.md) — what changed, release by release
