# nexcage 0.9.1

The first release since 0.8.0. 0.9.0 was prepared but never tagged, so
everything in [its notes](NOTES_v0.9.0.md) ships here too — if you are coming
from 0.8.0, read those as well, because that is where the behaviour changes
are.

**Reinstall if you are on 0.8.0.** The published 0.8.0 binary and `.deb` were
built for the CPU of the machine that built them. On a host without AVX2:

```
$ nexcage-0.8.0-amd64 version
Illegal instruction
```

That is the release asset from GitHub, run on a Xeon E5-2697 v2 — ordinary
hardware for a Proxmox node. Anything older than Haswell is affected. The
0.9.1 artifacts are built with `-Dcpu=baseline` and were checked on that same
host before tagging.

## What 0.9.1 fixes

- **The published binary and `.deb` run on any x86_64 host.** `build.zig` takes
  its target from `standardTargetOptions`, whose default is the native CPU, and
  both release paths — `release.yml` and `scripts/build_deb_local.sh` — called
  a bare `zig build -Doptimize=ReleaseSafe`. They now pass `-Dcpu=baseline`.
- **`make lint` and `make check` work on a clean clone.** `zig fmt --check`
  failed on 21 files; the tree is formatted, and CI checks it now, which is why
  it had drifted.
- **The Proxmox E2E suite picks a template that can boot.** It took the first
  `vztmpl` volume, and on Proxmox VE 9.1+ that list also holds OCI images —
  `nexcage run docker.io/…` puts one there itself. Detection matches a system
  template by distribution name, and the suite frees the images it pulls.

## What comes from 0.9.0

Summarised; [NOTES_v0.9.0.md](NOTES_v0.9.0.md) has the detail and the upgrade
notes, which matter if you run 0.8.0 today.

- `kill` signals the container's init from the host with `kill(2)`, as an OCI
  runtime does. On 0.8.0 it went through `pct exec` and did nothing.
- `state` reports the init's host PID while the container runs, and `created`
  for a container not yet started through nexcage.
- `--config <path>` and `--runtime <lxc|crun|runc|vm>` do what they say. Both
  were parsed and ignored.
- **New containers are unprivileged by default**, as in the Proxmox VE web UI.
  They used to be privileged — the one change here that can affect an existing
  workflow.
- Creating from an OCI bundle works.
- `make sim` runs every command against fake Proxmox tools; CI runs it on every
  pull request.

## Added around the runtime, not in it

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
  on is 9.2, the first host where this could be exercised at all.
- **A self-hosted build agent** builds the `.deb` on Debian 13, the
  distribution Proxmox VE is built on, and runs the simulation suite there.

## Upgrading

From 0.8.0, read [NOTES_v0.9.0.md](NOTES_v0.9.0.md) first — the unprivileged
default is the change to plan for. Then replace the binary or reinstall the
package; there is no state to migrate.

```bash
sudo dpkg -i nexcage-0.9.1-amd64.deb
nexcage version
```
