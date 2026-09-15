# CLI Reference

```
nexcage [--debug] [--log-level <level>] [--log-file <path>] [--config <path>] <command> [options]
```

Every command accepts `--help`. nexcage must run as root on the Proxmox VE
host: it calls `pct`, `pvesh`, `pvesm` and `pveversion`, and writes state under
`/run/nexcage`.

## Global options

These work before or after the command.

| Option | Effect |
|---|---|
| `--debug` | Log level `debug`, plus startup and system information |
| `--log-level <level>` | `trace`, `debug`, `info` (default), `warn`, `error`, `fatal` |
| `--log-file <path>` | Also write log lines to `<path>` |
| `--config <path>` | Read configuration from `<path>` only. A missing or unparsable file is an error (exit 1) |

Logs go to stderr. stdout carries only command output (`list`, `state`,
help text).

Without `--config`, configuration comes from the first of `./config.json`,
`/etc/nexcage/config.json`, `/etc/nexcage/nexcage.json` that exists; see the
README for the keys.

## Backend selection

`create`, `run`, `start`, `stop`, `delete`, `kill` and `state` go to the
backend chosen by the routing rules in the config file, Proxmox LXC by default.
`--runtime <lxc|crun|runc|vm>` overrides that for one command.

- `crun` and `runc` work only in a binary built with
  `-Denable-backend-crun=true` or `-Denable-backend-runc=true`; otherwise the
  command fails with exit 1. They have no `run` or `state`.
- `vm` is not integrated yet: every command fails with "not implemented".
- Any other value is a usage error (exit 2).

## Exit status

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | The operation failed: container not found, pct error, not a Proxmox VE host, invalid configuration file, backend not built or not implemented |
| `2` | Invalid usage: unknown command, missing name or image, unknown `--runtime`, unusable OCI bundle |

A failure prints one line such as `nexcage: start: not found` after the log
line that explains it.

## Commands

### create

```bash
nexcage create --name <name> <image>
```

Creates a container named `<name>`; the name becomes its hostname and must be
unique on the node. The VMID comes from `pvesh get /cluster/nextid`. `--image
<image>` is accepted in place of the positional image.

`<image>` can be:

| Form | Example | Notes |
|---|---|---|
| Proxmox template | `local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst` | Any `<storage>:vztmpl/…` volume |
| Template file name | `debian-12-standard_12.7-1_amd64.tar.zst` | Looked up as `local:vztmpl/<file>` |
| OCI registry reference | `docker.io/library/redis:7` | Proxmox VE 9.1+ only; pulled to storage `local` |
| OCI bundle directory | `/var/lib/nexcage/bundles/web` | Under `/var/lib/nexcage/bundles/` or `/tmp/nexcage-bundles/`, containing `config.json` and `rootfs/` |

The container gets `eth0` on `network.bridge` with DHCP, 512 MiB of memory and
one core unless the OCI bundle sets limits. Its root filesystem goes to
`proxmox.storage` (`<storage>:<rootfs_size_gb>`) when that is configured. It is
unprivileged unless `proxmox.unprivileged` is `false`; images from a registry
always run unprivileged.

For an OCI bundle, nexcage packs `rootfs/` with tar into
`local:vztmpl/nexcage-<name>-<time>.tar.zst`, creates the container from that
template and deletes the archive. The rootfs is used as it is, so it must boot
as a system container: an image without an init will not start. Mounts are
added as `mpX` entries, and the user namespace maps to `nesting=1,keyctl=1`.

### run

```bash
nexcage run --name <name> <image>
```

`create` followed by `start`.

### start

```bash
nexcage start <name>        # or: nexcage start --name <name>
```

### stop

```bash
nexcage stop <name>
```

A clean shutdown (`pct shutdown --timeout 60 --forceStop 1`): the container
gets 60 seconds, then it is stopped forcibly.

### delete

```bash
nexcage delete <name>
```

Destroys the container with `pct destroy` and removes `/run/nexcage/<name>`.
A running container must be stopped first.

### kill

```bash
nexcage kill <name> [SIGNAL]
nexcage kill [-s|--signal SIGNAL] <name>
```

Sends `SIGNAL` to the container's init process from the host, as an OCI runtime
does: nexcage reads the init's host PID from `pct status <vmid> --verbose` and
calls `kill(2)`. `SIGNAL` is a name in any case, with or without `SIG` (`TERM`,
`SIGKILL`, `usr1`), or a number from 1 to 64; the default is `SIGTERM`. An
unknown signal is a usage error (exit 2); a container that is not running is an
error (exit 1).

The kernel delivers a signal from the host to a container's init only if init
handles it, except `SIGKILL` and `SIGSTOP`. `SIGKILL` always stops the
container; what `SIGTERM` does depends on the init system. Use `stop` for a
clean shutdown.

### list

```bash
nexcage list
```

Tab-separated columns `ID IMAGE COMMAND CREATED STATUS BACKEND NAMES`, from
`pct list`. `ID` is the VMID and `NAMES` the container name. When `pct list`
fails, `list` fails too (exit 1) instead of printing an empty table.

### state

```bash
nexcage state <name|vmid>
```

Prints OCI runtime state JSON:

```json
{
  "ociVersion": "1.0.0",
  "id": "web-1",
  "status": "running",
  "pid": 48213,
  "bundle": null,
  "annotations": {}
}
```

`status` is `created` for a container not yet started through nexcage, or
`running`, `stopped` or `paused` as pct reports it. `pid` is the host PID of the
container's init while it runs, and 0 otherwise. A container that does not
exist is an error (exit 1).

### version, help

```bash
nexcage version
nexcage --help
```
