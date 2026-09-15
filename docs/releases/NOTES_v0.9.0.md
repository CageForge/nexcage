# nexcage 0.9.0

nexcage 0.9.0 makes the 0.8.0 commands behave as documented on a real
Proxmox VE host: `kill` follows OCI semantics, `state` reports what an OCI
caller needs, `--config` and `--runtime` do what they say, containers are
unprivileged by default, and creating from an OCI bundle works.

## What's new

- **`kill` from the host.** The signal goes to the host PID of the container's
  init with `kill(2)`, as an OCI runtime does. `SIGKILL` stops a container.
  Signal names are accepted in any case, with or without `SIG`, or as numbers.
- **`state`** reports the init's host PID while the container runs, and
  `created` for a container not yet started through nexcage.
- **`--config <path>`** reads that file instead of the default locations,
  before or after the command.
- **Unprivileged by default**, as in the Proxmox VE web UI.
- **OCI bundles** work: the bundle's `rootfs/` is packed into a temporary
  template for `pct create`.

Every command is checked in CI against fake Proxmox tools (`make sim`), and the
lifecycle, `kill`, `run --config` and OCI bundles run on a self-hosted
Proxmox VE 9.1 runner.

## Upgrading from 0.8.0

- **Privileges.** New containers are unprivileged. Set
  `"proxmox": { "unprivileged": false }` for privileged ones. Existing
  containers do not change. Bind mounts and devices in unprivileged containers
  are subject to Proxmox's UID mapping.
- **kill.** It no longer uses `pct exec`, so it works where lxc-attach cannot
  run and needs no kill binary in the image. The kernel still delivers a
  signal to a container's init only if init handles it, except `SIGKILL` and
  `SIGSTOP`: `kill <name> SIGKILL` stops a container, while `SIGTERM` depends
  on the init system. An unknown signal is now a usage error (exit 2).
- **state.** Right after `create` the status is `created`, not `stopped`.
  Scripts that wait for `stopped` after creating a container need to accept
  `created`.
- **--config.** A `--config` pointing at a missing file used to be ignored; now
  the command fails with exit 1.
- **--runtime.** It used to be ignored. `--runtime crun` or `runc` on a build
  without that backend now fails (exit 1) instead of quietly using LXC,
  `runc` no longer selects crun, and an unknown value is exit 2.
- **list** fails with pct's message (exit 1) when `pct list` fails, instead of
  printing an empty table.
- **Not implemented is an error.** The VM backend, `run` on crun and runc, and
  `state` for crun, runc and VM exit 1 instead of pretending to succeed.
- **Build options.** `-Denable-zfs`, `-Denable-bfc` and `-Denable-proxmox-api`
  are gone with the unused integrations module; `zig build` rejects them. The
  `deps/bfc` submodule is removed.

## Fixed

- Creating a container from an OCI bundle failed with "not found".
- A bundle without `config.json` or `rootfs/` crashed nexcage.
- `--log-level` and `--log-file` after the command name became the container
  name.
- `health --help` ran the checks; `version --help` printed the version.
- Memory leaks on bundle create and in `health`.
- A bundle without mounts logged "No mp entries visible in pct config".

## Not in this release

- containerd / CRI integration
- The crun and runc backends remain opt-in and experimental
- Containers on other cluster nodes
- `state` reports `bundle: null`; `kill` on a `created` container fails,
  because an LXC container has no process until it starts

See `CHANGELOG.md` for the full list.
