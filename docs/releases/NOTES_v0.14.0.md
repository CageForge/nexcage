# nexcage 0.14.0

Snapshots, `create --node` on a stock Proxmox VE host, and a project that says
true things: the Proxmox VM stub and two build options that could not work are
gone, the documentation was checked line by line against the code, and the
ownership and review rules describe what is practised.

## Read this first if your configuration names `vm` or `proxmox`

**Such a file is now refused by every command.** The Proxmox VM backend is
removed (below), and unlike runc in 0.13.0 there is no backend to send such a
container to instead: the default one would make a container where a virtual
machine was asked for. The message says what to name instead — `lxc` or
`crun`. `--runtime vm` and `--runtime qemu` exit 2, saying the backend was
removed. A configuration that names neither is unaffected.

## Snapshots

```
$ nexcage snapshot web-1 before-upgrade --description "pre 2.4"
$ nexcage snapshots web-1
NAME	CREATED	DESCRIPTION
before-upgrade	2026-10-02T10:31:07Z	pre 2.4
$ nexcage rollback web-1 before-upgrade --start
$ nexcage delsnapshot web-1 before-upgrade
```

`snapshot`, `snapshots`, `rollback` and `delsnapshot`, with pct's names, for
the Proxmox LXC backend. Proxmox takes the snapshot, so each is one `pct` call
for a container on this node and one call to its node's API for a container
elsewhere; nexcage adds the container by name on any node, a plain line when
the storage cannot snapshot, and a tab-separated list, or `--format json` with
each snapshot's parent as well. `rollback` of a
running container stops it, as Proxmox does, and `--start` starts it again.
The crun backend refuses them: libcrun has no storage of its own to snapshot.
The E2E suite exercises them on a storage that can snapshot and on one that
cannot.

## Fixed

- **`create --node` was refused on every stock Proxmox VE host** — "cannot be
  used with a ZFS rootfs" — because the guard asked whether the zfs tools were
  installed, and Proxmox VE installs them. It now asks what it meant to: whether
  nexcage would make a dataset itself, which no configuration key does. A
  rootfs on a ZFS storage goes through; Proxmox creates it on the node that owns
  the container. The simulator's fake `zfs` had answered "not installed", which
  is a host Proxmox VE does not ship.
- **`state` reports `ociVersion` 1.3.0**, the runtime-spec baseline since
  0.7.4, rather than a hand-written `1.0.0`.
- **The documentation and every command's `--help`**, checked statement by
  statement against the code. Among what was wrong: a bundle had to sit under
  two directories (any absolute path has been accepted since 0.10.0); the crun
  backend had no `state` or `exec` (it has both); `--log-file` was said to
  receive the log (it holds the start and completion lines, never an error);
  `list` was said to cover every backend (Proxmox LXC only); the man page and
  the completion lacked a dozen commands.
- `CODEOWNERS` named the organization and an account that is not the
  maintainer's, so GitHub never requested a review from anyone.
  `GOVERNANCE.md` and `MAINTAINERS.md` asked for two reviewers with one active
  maintainer; they now say how changes are reviewed today, and when the
  two-reviewer rule starts.

## Removed

- **The Proxmox VM backend** and `-Denable-backend-proxmox-vm`. It was compiled
  out by default and built by no workflow; the router answered every operation
  routed to it as not implemented, and the driver imported a module the build
  does not define. `qm` can come back with a test behind it and someone who
  needs it.
- **`-Denable-backend-proxmox-lxc`.** Setting it to false never compiled. The
  Proxmox LXC backend is always built; `zig build` rejects the option.
- `crun_vendor_sync.yml`, `crun_headers_generate.yml` and
  `scripts/sync_crun_vendor.sh`, which changed files inside the `deps/crun`
  submodule and so never had a pull request to open.

## Proxmox VE 8 is no longer claimed

Earlier releases ran on it, but no test ever did, and Proxmox ended its own
support for 8.x in August 2026. nexcage does not refuse an 8.x host; it no
longer promises anything there. Proxmox VE 9 is what the E2E suite runs on.

## For contributors

`scripts/dev.sh` (`make doctor`, `e2e`, `act`, `local-ci`, `perf`,
`dev-shell`) runs the unit tests, the simulator, the crun backend, a pod
through containerd's CRI and the GitHub-hosted CI jobs on a workstation, with
rootless podman or Docker. `tests/perf/` times every command and counts the
Proxmox tool runs each makes; `scripts/dev.sh perf --against <ref>` fails on a
regression. `ROADMAP.md` says what comes next.

## Upgrading from 0.13.0

- Plain binary, `.deb` and `-crun` binary: install and carry on.
- A configuration naming `vm` or `proxmox` as a runtime: name `lxc` or `crun`
  — see the top.
- Building from source: drop `-Denable-backend-proxmox-vm` and
  `-Denable-backend-proxmox-lxc` from your flags.

## Still missing

Flags that `run` and `exec` accept on Proxmox LXC and then drop — `exec --user`
runs the command as root — are refused in 0.14.1, the next release, with the
other bugs the documentation pass found. See `ROADMAP.md`.
