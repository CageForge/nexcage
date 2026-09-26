# CLI Reference

```
nexcage [--debug] [--log-level <level>] [--log-file <path>] [--config <path>] [--root <dir>] <command> [options]
```

Every command accepts `--help`. nexcage must run as root on the Proxmox VE
host: it calls `pct`, `pvesh`, `pvesm` and `pveversion`, and writes state under
`/run/nexcage`.

## Global options

These work before or after the command, and in either spelling: `--root <dir>`
and `--root=<dir>` mean the same thing. Both are needed because an engine picks
one without asking — containerd sends the two-word form, CRI-O sends `--root=`
for `create` (through conmon) and the two-word form for everything after it.
The split stops at a bare `--`, so an argument to the command `exec` runs
inside the container keeps its `=`.

| Option | Effect |
|---|---|
| `--debug` | Log level `debug`, plus startup and system information |
| `--log-level <level>` | `trace`, `debug`, `info` (default), `warn`, `error`, `fatal` |
| `--log-file <path>` | Also write log lines to `<path>` |
| `--config <path>` | Read configuration from `<path>` only. A missing or unparsable file is an error (exit 1) |
| `--log <path>` | The runtime's own log goes to `<path>` instead of stderr, as an OCI runtime's does. A container engine reads it back to report why the runtime failed |
| `--log-format <text\|json>` | `json` writes one object per line — `level`, `msg` and an RFC 3339 `time` — which is what an engine parses |
| `--systemd-cgroup` | Accepted; cgroup management is libcrun's, and this reaches its context |
| `--root <dir>` | Keep per-container state under `<dir>` instead of `/run/nexcage`. An OCI runtime takes this from its caller: containerd gives each namespace its own directory, so two callers on one host do not see each other's containers. Must be absolute |
| `--version` | The same output as the `version` command. CRI-O asks a runtime its version this way before it will use one |

Logs go to stderr. stdout carries only command output (`list`, `state`,
help text).

Without `--config`, configuration comes from the first of `./config.json`,
`/etc/nexcage/config.json`, `/etc/nexcage/nexcage.json` that exists; see the
README for the keys.

A file that declares `ociVersion` is not one of them: an OCI bundle holds a
`config.json` that is a runtime spec, and a container engine runs the runtime
from the bundle directory, so it would otherwise replace the configuration —
routing rules included — without saying so. Such a file is skipped in the
search path, and refused when named with `--config`.

`--root` is read before any command touches state, wherever it appears on the
command line.

## Backend selection

`create`, `run`, `start`, `stop`, `delete`, `kill`, `exec` and `state` go to
the backend chosen by the routing rules in the config file, Proxmox LXC by
default.
`--runtime <lxc|crun|runc|vm>` overrides that for one command, before or after
the command name.

A routing rule's `pattern` is a **regular expression only when it starts with
`^` or ends with `$`**; anything else is matched as a shell-style wildcard. So
`^(kube-ovn-.*|cilium-.*)$` is a regex, `web-*` is a wildcard, and `.*` is
neither a catch-all nor an error — as a wildcard it means a literal dot
followed by anything, and matches nothing whose name does not begin with a
dot. Write `*` or `^.*$` for a catch-all.

A container engine never passes `--runtime`, so driving nexcage from one means
routing to the OCI backend in the configuration file:

```json
{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
```

- `crun` and `runc` work only in a binary built with
  `-Denable-backend-crun=true` or `-Denable-backend-runc=true`; otherwise the
  command fails with exit 1. They have no `run` or `state`, and neither has
  `exec`: libcrun's exec entry point has no binding in nexcage's FFI.
- The crun backend creates the container from the bundle given with
  `--bundle`, and keeps its state under `--root` when one is given, or
  `/run/crun` as crun itself does.
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

`exec` is the exception: it exits with the status of the command it ran, the
way `runc exec` does, so 1 and 2 from that command mean whatever the command
means by them.

## Commands

### create

```bash
nexcage create --name <name> <image>
nexcage create <container-id> --bundle <dir> [--console-socket <path>] [--pid-file <path>]
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

`--console-socket <path>` is where the runtime sends the master end of the
container's pty, over a Unix socket with `SCM_RIGHTS`, as the runtime-spec
requires. A bundle whose `config.json` sets `process.terminal` cannot be
created without it. `--pid-file <path>` is where the container process's pid is
written.

Both need a backend that leaves a process running after `create`, which means
`--runtime crun`. On the Proxmox LXC backend they fail with exit 1 and say so:
`pct create` starts nothing, so there is no pty to hand over and no pid to
write. They are refused rather than ignored — a caller that passes
`--console-socket` and receives no file descriptor waits for one that is never
coming.

With `--bundle <dir>` the first positional word is the **container id**, not the
image, which is the form the runtime-spec defines and a container engine sends:
`nexcage create web-1 --bundle /var/lib/nexcage/bundles/web`. Without
`--bundle` the positional word is still the image, so the older form keeps
working.

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
nexcage delete <name> [--force]
```

Destroys the container with `pct destroy` and removes its state directory.
A running container must be stopped first, unless `--force` is given: that
shuts it down and then destroys it, as `runc delete --force` does. A container
engine sends `--force` once it has given up waiting for a clean shutdown.

### kill

```bash
nexcage kill <name> [SIGNAL]
nexcage kill [-s|--signal SIGNAL] [--all] <name>
```

Sends `SIGNAL` to the container's init process from the host, as an OCI runtime
does: nexcage reads the init's host PID from `pct status <vmid> --verbose` and
calls `kill(2)`. `SIGNAL` is a name in any case, with or without `SIG` (`TERM`,
`SIGKILL`, `usr1`), or a number from 1 to 64; the default is `SIGTERM`. An
unknown signal is a usage error (exit 2); a container that is not running is an
error (exit 1).

`--all` means every process in the container, not only its init. On
`--runtime crun` it goes to `libcrun_container_killall`, which walks the
container's cgroup — it needs one it can read, and fails with
`read from file 'cgroup.procs': Operation not supported` where the cgroup is
not delegated. On the Proxmox LXC backend nexcage can only signal the init from
the host, and says so when `--all` is given rather than implying it did more.

The kernel delivers a signal from the host to a container's init only if init
handles it, except `SIGKILL` and `SIGSTOP`. `SIGKILL` always stops the
container; what `SIGTERM` does depends on the init system. Use `stop` for a
clean shutdown.

### exec

```bash
nexcage exec <name> <command> [args...]
nexcage exec <name> -- <command> [args...]
nexcage exec --process <file> <name>
```

| Option | Effect |
|---|---|
| `--process <file>` | An OCI process spec: the args, the user, the environment, whether there is a terminal. This is how a container engine sends an exec — containerd and CRI-O write the file and name it — and it takes no command of its own |
| `-t`, `--tty` | The command gets a terminal |
| `-d`, `--detach` | Return once the command is started, rather than waiting for it |
| `--cwd <dir>` | Working directory inside the container (`--workdir` is the same flag) |
| `--user <uid[:gid]>` | Identity to run as; an unparsable value is an error rather than a silent root |
| `--console-socket <path>`, `--pid-file <path>` | As with `create` |

Runs `<command>` inside a running container and exits with its status: `nexcage
exec web-1 false` exits 1, and `nexcage exec web-1 sh -c 'exit 7'` exits 7. A
caller that watches the status — containerd, a readiness probe — reads the
command's result rather than "the runtime succeeded", which is why this command
does not follow the exit table above.

`--` separates the command from nexcage's own options, and is needed when the
command itself starts with a dash. Everything after it is passed through
untouched.

stdin, stdout and stderr are connected straight to the process in the
container; nexcage does not buffer the output.

On the Proxmox LXC backend this runs `pct exec <vmid> -- <command>`, so the
command has to exist in the container's image — an image without a shell has no
`sh` for `exec` to call. A container that is not running is an error (exit 1),
as is one that does not exist; `exec` without a command is a usage error
(exit 2).

`--process` and `--detach` are refused there rather than ignored: `pct exec`
takes a command and returns when it ends, so there is no identity to apply from
a spec and nothing to detach from. Same rule as `--console-socket` on `create`.

On the crun backend both forms go to `libcrun_container_exec_process_file`,
which takes the path of a file holding the process spec. `--process` hands the
caller's file over untouched; a command typed on the command line is written to
a temporary spec, which nexcage removes afterwards. That spec carries a default
`PATH` when `--env` gives none, because a process with no `PATH` cannot find
`ls` and nothing would say why.

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
  "bundle": "/var/lib/nexcage/bundles/web",
  "annotations": {}
}
```

On `--runtime crun` the state comes from libcrun, which writes it itself, so
the output is what `crun state` gives for the same container — the same fields
in the same order, including `rootfs`, `created`, `systemd-scope` and `owner`,
which the Proxmox LXC backend has no way to report. A container libcrun does
not know is an error (exit 1) carrying libcrun's own message.

On the Proxmox LXC backend nexcage composes the state itself, because `pct` has
no such call:

`status` is `created` for a container not yet started through nexcage, or
`running`, `stopped` or `paused` as pct reports it. `pid` is the host PID of the
container's init while it runs, and 0 otherwise. `bundle` is the directory the
container was created from, and `null` for one created from a template or a
registry image; `start` and `stop` keep it. A container that does not exist is
an error (exit 1).

### features

```bash
nexcage --runtime crun features
```

Prints the OCI runtime-spec features document: the spec versions this build
accepts, the hooks it runs, the mount options and namespaces it knows, and
whether seccomp, AppArmor, SELinux and idmapped mounts are compiled in.
containerd's CRI asks for it once at startup.

Every value comes from `libcrun_container_get_features`, the same call behind
`crun features`, so the answer is this build's own configuration rather than a
document maintained here that could promise what the binary does not do. The
field order and shapes follow crun's output too, down to the checkpoint
annotations being strings rather than booleans.

```json
{
  "ociVersionMin": "1.0.0",
  "ociVersionMax": "1.1.0+dev",
  "hooks": ["prestart", "createRuntime", "createContainer", "startContainer", "poststart", "poststop"],
  "mountOptions": ["rw", "rro", "bind", "idmap", "…"],
  "linux": {
    "namespaces": ["cgroup", "ipc", "mount", "network", "pid", "user", "uts"],
    "cgroup": { "v1": true, "v2": true, "systemd": true, "systemdUser": true },
    "seccomp": { "enabled": true, "actions": ["…"], "operators": ["…"] },
    "mountExtensions": { "idmap": { "enabled": true } }
  },
  "annotations": {
    "run.oci.crun.version": "1.24",
    "io.cageforge.nexcage.version": "0.9.1",
    "io.cageforge.nexcage.backend": "crun"
  }
}
```

The command takes no container id, so there is no routing key: an explicit
`--runtime` wins, otherwise the routing rules are asked about an empty id,
which for the catch-all an engine needs (`"*"`) is crun.

Answered by the crun backend only. On the Proxmox LXC backend it exits 1 and
says where the answer lives: a features document is a claim about how a runtime
implements the spec — which hooks it runs, whether it applies seccomp,
AppArmor, capabilities, an idmapped mount — and `pct` creates the container
there, so any document would be an assertion about `pct` dressed as this
runtime's. Same reason `--console-socket` is refused there.

### version, help

```bash
nexcage version
nexcage --help
```
