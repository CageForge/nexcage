# nexcage 0.9.1

A packaging fix. Every command behaves exactly as in 0.9.0 — nothing was added
to the CLI and nothing changed about what it does.

**If you installed 0.9.0 on a Proxmox VE host, reinstall.** The 0.9.0 binary
and `.deb` were built for the CPU of the machine that built them, so on an
older host `nexcage version` answers:

```
Illegal instruction
```

Anything without AVX2 is affected — a Xeon E5 v2 is ordinary hardware for a
Proxmox node. The 0.9.1 artifacts are built with `-Dcpu=baseline` and run on
any x86_64 host.

## Fixed

- **The published binary and `.deb` are portable.** `build.zig` takes the
  target from `standardTargetOptions`, whose default is the native CPU, and
  both release paths — `release.yml` and `scripts/build_deb_local.sh` — called
  a bare `zig build -Doptimize=ReleaseSafe`. They now pass `-Dcpu=baseline`.
- **`make lint` and `make check` work on a clean clone.** `zig fmt --check`
  failed on 21 files; the tree is formatted, and CI checks it now, which is why
  it had drifted.
- **The Proxmox E2E suite picks a template that can boot.** It took the first
  `vztmpl` volume, and on Proxmox VE 9.1+ that list also holds OCI images —
  `nexcage run docker.io/…` puts one there itself. Detection matches a system
  template by distribution name, and the suite frees the images it pulls.

## Added, around the runtime rather than in it

None of this changes the binary.

- **[Kubernetes integration](../KUBERNETES_INTEGRATION.md)** — what nexcage
  still lacks before Kubernetes can schedule onto it (`exec`, the OCI
  runtime-spec command line, logs, CNI, sandboxes, an image service, a remote
  surface), measured against this binary rather than guessed at, and the stages
  from an in-cluster build job to CRI.
- **`deploy/kubernetes/tenant-nexcage/`** — the Cozystack tenant nexcage is
  developed in: a `Job` that builds it and runs the unit tests inside the
  cluster, and a kubemox `VirtualMachine` that declares the Proxmox VE node the
  E2E suite runs on. `pve-template/` builds that node's template from the
  Debian 13 cloud image.
- **The E2E suite covers the OCI registry path.** `nexcage run --name …
  docker.io/library/redis:7` has to pull through `oci-registry-pull`, reach
  `running` with a real init PID and be unprivileged. Proxmox VE before 9.1
  cannot pull from a registry, so the step says so and skips; the node it runs
  on is 9.2, which is the first host where this could be exercised at all.
- **A self-hosted build agent** builds the `.deb` on Debian 13, the
  distribution Proxmox VE itself is built on, and runs the simulation suite
  there.

## Upgrading from 0.9.0

Replace the binary or reinstall the package. No configuration changes, no
behaviour changes, no migration.

```bash
sudo dpkg -i nexcage-0.9.1-amd64.deb
nexcage version
```
