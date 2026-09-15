# CLI Reference

```
nexcage [--debug] [--log-level <level>] [--log-file <path>] <command> [options]
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

Logs go to stderr. stdout carries only command output (`list`, `state`,
help text).

`--config <path>` is accepted but not honoured yet. Configuration comes from
the first of `./config.json`, `/etc/nexcage/config.json`,
`/etc/nexcage/nexcage.json` that exists; see the README for the keys.

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
`proxmox.storage` (`<storage>:<rootfs_size_gb>`) when that is configured.

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

Sends `SIGNAL` (default `SIGTERM`; a name like `SIGKILL` or a number) to PID 1
inside the container through `pct exec`.

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
  "pid": 0,
  "bundle": null,
  "annotations": {}
}
```

`status` is `created`, `running`, `stopped`, `paused` or `unknown`. `pid` is
not reported yet. A container that does not exist is an error (exit 1).

### version, help

```bash
nexcage version
nexcage --help
```
