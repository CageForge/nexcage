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
| `--log-file <path>` | Also write to `<path>` (and to stderr) a startup line naming the version, a line when the command starts, and two when it succeeds; with `--debug`, system information and the command's environment (debug mode, log file, timestamp) too. The command's own log lines, including the ones that explain a failure, are not written there: they go to stderr, or to `--log` |
| `--config <path>` | Read configuration from `<path>` only. A missing or unparsable file is an error (exit 1) |
| `--log <path>` | The runtime's own log goes to `<path>` instead of stderr, as an OCI runtime's does. A container engine reads it back to report why the runtime failed |
| `--log-format <text\|json>` | `json` writes one object per line — `level`, `msg` and an RFC 3339 `time` — which is what an engine parses |
| `--systemd-cgroup` | Accepted anywhere, so that an engine sending it is not refused. Only after `create`, on the crun backend, does it reach libcrun's context; anywhere else it has no effect |
| `--root <dir>` | Keep per-container state under `<dir>` instead of `/run/nexcage`. An OCI runtime takes this from its caller: containerd gives each namespace its own directory, so two callers on one host do not see each other's containers. Must be absolute |
| `--version` | The same output as the `version` command. CRI-O asks a runtime its version this way before it will use one |

An option no command takes is refused with exit 2, naming it, and so is a
value option with nothing after it. That includes runc options nexcage does not
implement, such as `--no-pivot` or `--preserve-fds`: dropping one would run the
container differently from what was asked.

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

## Clusters

A Proxmox VE cluster has more than one node, and `pct` only ever sees the one it
runs on. nexcage asks the cluster instead — `/cluster/resources` — so a
container is found wherever it lives:

```
$ nexcage list
ID    IMAGE     COMMAND  CREATED   STATUS   BACKEND      NODE        NAMES
100   unknown   pct      unknown   running  proxmox-lxc  prox-home   web-1
200   unknown   pct      unknown   running  proxmox-lxc  titan       web-2

$ nexcage start web-2        # on titan, from here
```

`start`, `stop`, `delete` and `state` work on any node: for a container on this
host they run `pct`, and for one elsewhere they go through that node's API. The
`state` of a container on another node carries it as an annotation:

```json
  "pid": 0,
  "annotations": { "io.cageforge.nexcage.node": "titan" }
```

**Four things stay local.** `exec`, `kill`, `pause` and `resume` are refused
with the node's name rather than answered wrongly; the `pid` in `state` is 0,
and the `io.cageforge.nexcage.node` annotation names the node:

| | why |
|---|---|
| `exec` | `pct exec` attaches to a container on the host it runs on, and the API has no exec |
| `kill` | a signal goes to the container's init from the host, and the API has no call for that — `stop` and `delete` do work from here |
| `pause`, `resume` | freezing writes the container's cgroup on the host it runs on, and the API has no call for that |
| the `pid` in `state` | an init's PID belongs to its node's process table; reporting it here would name whatever holds that number on this host |

`paused` is local too, and is not refused: `state` and `list` read it from this
host's cgroup freezer, so a frozen container on another node shows as `running`.

`create --node <name>` makes the container on another node:

```bash
nexcage create --name web-2 --node titan local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst
```

The name is checked across the whole cluster first, because every other command
resolves a name and two containers sharing one would make that ambiguous. Then
the template is checked **on the target node**, before a VMID is taken: a storage
called `local` is a different directory on every node unless it is shared, so a
volid that exists here may simply not be there. The message names the node and
the storage rather than leaving the API to say "volume does not exist".

Two things `--node` will not do, and refuses rather than half-does:

| | why |
|---|---|
| an OCI bundle (`--bundle`) | its rootfs is packed into a template on **this** host's storage, which the other node cannot read unless that storage is shared |
| a registry image (`docker.io/...`) | the pull lands on this host, for the same reason |

A rootfs on a ZFS storage goes through: `proxmox.storage` reaches that node's
API as `--rootfs <storage>:<size>`, and Proxmox makes the volume there, so name
a storage the target node has.

`--node` naming the host nexcage is running on is not "another node": it takes
the ordinary local path, `pct` and all.

On a host that is not in a cluster, or where `pvesh` cannot be reached, nexcage
falls back to `pct` and behaves exactly as it did: this host's containers, and
no others.

**The cluster's listing is a cache**, refreshed by `pvestatd` every few seconds,
and nexcage is built around that in two places. A container created a moment ago
is not in it yet, so a name missing there means "keep looking on this host"
rather than "no such container" — otherwise `create` followed straight away by
`start` fails. And for a container on this host, `pct` is the current answer
while the cluster's copy can be seconds stale, so `list` and `state` take the
status from `pct` and keep from the cluster the one thing only it knows: which
node a container elsewhere is on.

## Backend selection

`create`, `run`, `start`, `stop`, `delete`, `kill`, `exec`, `state`, `pause`,
`resume`, `update`, `ps`, `features` and the snapshot commands go to the
backend chosen by the routing rules in the config file, Proxmox LXC by
default.
`--runtime <lxc|crun>` overrides that for one command, before or after
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

- `crun` works only in a binary built with `-Denable-backend-crun=true`;
  otherwise the command fails with exit 1. It has no `run`, and refuses the
  snapshot commands, which are Proxmox's (exit 1 for both).
- The crun backend creates the container from the bundle given with
  `--bundle`, and keeps its state under `--root` when one is given, or
  `/run/crun` as crun itself does.
- `vm` and `qemu` named the Proxmox VM backend, removed in 0.14.0, and exit 2
  saying so. A routing rule naming `vm`, or `proxmox`, which meant the same,
  makes the configuration file an error (exit 1) for every command: no
  backend is left to run what it describes, and the default one would make
  a container where a VM was asked for.
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
nexcage create --name <name> [--storage <name>] [pct options] <image>
nexcage create <container-id> --bundle <dir> [--console-socket <path>] [--pid-file <path>]
```

Creates a container named `<name>`; the name becomes its hostname and must be
unique in the cluster. The VMID comes from `pvesh get /cluster/nextid`. `--image
<image>` is accepted in place of the positional image.

`<image>` can be:

| Form | Example | Notes |
|---|---|---|
| Proxmox template | `local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst` | Any `<storage>:vztmpl/…` volume |
| Template file name | `debian-12-standard_12.7-1_amd64.tar.zst` | Looked up as `local:vztmpl/<file>` |
| OCI registry reference | `docker.io/library/redis:7` | Proxmox VE 9.1+ only. Found on `--storage` (default `local`) if already pulled, else pulled there through `oci-registry-pull`; the volid is read back from the storage, never guessed from the reference |
| OCI bundle directory | `/var/lib/nexcage/bundles/web` | Any absolute path, containing `config.json` and `rootfs/`; a relative path is a usage error (exit 2) |

`--console-socket <path>` is where the runtime sends the master end of the
container's pty, over a Unix socket with `SCM_RIGHTS`, as the runtime-spec
requires. On the crun backend, a bundle whose `config.json` sets
`process.terminal` cannot be created without it. `--pid-file <path>` is where
the container process's pid is written.

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
one core unless the options below or the OCI bundle set them. Its root filesystem goes to
`proxmox.storage` (`<storage>:<rootfs_size_gb>`) when that is configured. It is
unprivileged unless `proxmox.unprivileged` is `false`; images from a registry
always run unprivileged.

For an OCI bundle, nexcage packs `rootfs/` with tar into
`local:vztmpl/nexcage-<name>-<time>.tar.zst`, creates the container from that
template and deletes the archive. The rootfs is used as it is, so it must boot
as a system container: an image without an init will not start. Mounts are
added as `mpX` entries, and the user namespace maps to `nesting=1,keyctl=1`.

#### pct options

What `pct create` is usually given, on the Proxmox LXC backend. Each maps onto
one pct option, through `pct create` here and the node's API with `--node`, so
`pct config <vmid>` shows it afterwards. Nothing given means pct's default (or
nexcage's, for memory, cores and the network).

| Option | pct | Notes |
|---|---|---|
| `--memory <size>` | `memory` | As for `update`: bytes, or with K, M or G. MiB, rounded up |
| `--memory-swap <size>` | `swap` | As for `update`, runc's meaning: memory plus swap. pct's `swap` is the difference, so it cannot be less than the memory |
| `--cpu-quota <us>`, `--cpu-period <us>` | `cpulimit` | Quota over period, in cores; the period defaults to 100000 |
| `--cpu-share <n>` | `cpuunits` | cgroup v1 shares converted to the v2 weight, as runc converts them |
| `--cores <n>` | `cores` | The cores the container sees |
| `--ip <cidr>` | `net0` `ip=` | `dhcp` by default; `manual` leaves it unset |
| `--gw <address>` | `net0` `gw=` | |
| `--vlan <tag>` | `net0` `tag=` | 1 to 4094 |
| `--firewall` | `net0` `firewall=1` | |
| `--onboot` | `onboot 1` | |
| `--tags <a;b>` | `tags` | |
| `--mp <spec>` | `mp0`, `mp1`, ... | pct's own syntax, e.g. `local-lvm:8,mp=/data` (a new 8 GiB volume) or `/srv/data,mp=/data` (a bind mount). Each `--mp` takes the next index |

A limit Proxmox has no setting for (`--pids-limit`, `--cpuset-cpus`, ...) is
refused by name, as `update` refuses it. `--ip` and `--gw` cannot contain `,` or
`=`, which would add a `net0` key nobody asked for (exit 2). `--mp` with an OCI
bundle is refused: the bundle's mounts take the `mp` entries. On the crun
backend every one of these is refused; it takes the limits, network and mounts
from the bundle's `config.json`.

```bash
nexcage create --name web-1 --memory 2G --cores 2 --ip 10.0.0.5/24 --gw 10.0.0.1 \
  --vlan 20 --onboot --tags 'web;prod' --mp local-lvm:8,mp=/srv/data \
  local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst
```

### run

```bash
nexcage run --name <name> <image>
```

`create` followed by `start`, on this host. `--node` is refused (exit 1): to
make the container on another node, `create --node`, then `start`.
`--console-socket` and `--pid-file` are refused as `create` refuses them, since
`pct start` runs the container's init itself; and the crun backend does not
implement `run` (exit 1). `<image>`, `--bundle` and `--storage` work as for
`create`.

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
| `--user <uid[:gid]>` | Identity to run as. On the crun backend an unparsable value is an error rather than a silent root |
| `--console-socket <path>`, `--pid-file <path>` | Where to send the master end of the pty and where to write the pid; crun backend only |

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

`--process`, `--detach`, `--user`, `--cwd`, `--console-socket` and
`--pid-file` are refused there rather than ignored (exit 1): `pct exec` takes a
command, runs it as root in a directory nexcage does not choose, and returns
when it ends, so there is no identity or directory to apply, nothing to detach
from and no pty or pid to hand back. Same rule as `--console-socket` on
`create`. `--tty` is honoured when nexcage runs on a terminal: `pct exec` runs
`lxc-attach`, which gives the command a terminal whenever one of its standard
descriptors is one. With none, `--tty` is refused. With `--process` even crun
takes the terminal, working directory and user from the file, not from
`--tty`, `--cwd` and `--user`.

On the crun backend both forms go to `libcrun_container_exec_process_file`,
which takes the path of a file holding the process spec. `--process` hands the
caller's file over untouched; a command typed on the command line is written to
a temporary spec, which nexcage removes afterwards. That spec carries a default
`PATH`, because a process with no `PATH` cannot find `ls` and nothing would say
why. It carries no other environment: nexcage has no `--env`.

### list

```bash
nexcage list
```

Tab-separated columns `ID IMAGE COMMAND CREATED STATUS BACKEND NODE NAMES`.
`ID` is the VMID, `NODE` the cluster node the container is on, and `NAMES` the
container name. Only Proxmox LXC containers are listed; the crun backend's are
not.
Containers on the other nodes of the cluster are listed too, which `pct list`
on one host cannot do.

`STATUS` is what `pct` says, except that a frozen container is `paused` — the
same answer [`state`](#state) gives, read from the same cgroup freezer.

When the listing cannot be read at all, `list` fails (exit 1) instead of
printing an empty table.

### state

```bash
nexcage state <name|vmid>
```

Prints OCI runtime state JSON:

```json
{
  "ociVersion": "1.3.0",
  "id": "web-1",
  "status": "running",
  "pid": 48213,
  "bundle": "/var/lib/nexcage/bundles/web",
  "annotations": {
    "io.cageforge.nexcage.node": "prox-home"
  }
}
```

On `--runtime crun` the state comes from libcrun, which writes it itself, so
the output is what `crun state` gives for the same container — the same fields
in the same order, including `rootfs`, `created`, `systemd-scope` and `owner`,
which the Proxmox LXC backend has no way to report. A container libcrun does
not know is an error (exit 1) carrying libcrun's own message.

On the Proxmox LXC backend nexcage composes the state itself, because `pct` has
no such call:

`status` is `created` for a container not yet started through nexcage, and
otherwise `running` or `stopped` as pct reports it — or `paused`, which pct
cannot report: that one is read from the container's cgroup freezer. `pid` is the host PID of the
container's init while it runs or is paused on this host, and 0 otherwise;
`annotations` names the node it is on as `io.cageforge.nexcage.node`, and is
`{}` when the node is not known. `bundle` is the directory the
container was created from, and `null` for one created from a template or a
registry image; `start` and `stop` keep it. A container that does not exist is
an error (exit 1).

### images

```bash
nexcage images [--node <name>]
```

The container templates the cluster can create from, with the node and storage
each one is on:

```
NODE        STORAGE      SHARED  SIZE   TEMPLATE
prox-home   local        no      129M   local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
prox-home   shared-rdma  yes     31M    shared-rdma:vztmpl/redis_7.tar
titan       local        no      98M    local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz
```

A template has to be readable by the node the container is created on, which is
what `create --node` checks, so this is where to look before placing a container
elsewhere. **A storage marked `SHARED` carries the same files on every node** and
is listed once rather than once per node — counting a template twice is worse
than not showing it.

Proxmox LXC only: the crun backend is handed a bundle whose rootfs is already
there, so it has nothing to list.

### pull

```bash
nexcage pull <image-reference> [--node <name>] [--storage <name>] [--filename <name>]
```

Fetches an OCI image from a registry into a Proxmox storage, where it becomes a
container template, and prints the volid — which is what `create` takes:

```bash
$ nexcage pull docker.io/library/redis:7 --storage shared-rdma
shared-rdma:vztmpl/redis_7.tar
$ nexcage create --name r1 --node titan shared-rdma:vztmpl/redis_7.tar
```

That pair is the point. `create` pulls too when given a registry reference, but
only on this host, onto `local` unless `--storage` names another, and `create
--node` refuses a registry reference whatever `--storage` says. Pulling onto a
shared storage with `pull`, then creating from the volid it prints, is how
`create --node` gets a registry image.

The volid is read back from the storage rather than composed from the reference:
the endpoint normalises the file name, and only the storage knows what it
settled on.

Needs **Proxmox VE 9.1 or later** on the target node, which is where
`oci-registry-pull` arrived. nexcage checks the version of the host it runs on,
not of the `--node` it pulls on: an older host is told which version it needs
rather than left with an API error. The endpoint takes **no credentials**, so a
private registry cannot be authenticated through it.

### rmi

```bash
nexcage rmi <template> [--node <name>]
```

Removes a container template from the storage it is on, named the way `images`
lists it and `pull` prints it:

```bash
$ nexcage rmi local:vztmpl/redis_7.tar
local:vztmpl/redis_7.tar removed from prox-home

$ nexcage rmi shared-rdma:vztmpl/redis_7.tar --node titan
shared-rdma:vztmpl/redis_7.tar removed from the shared storage; it is gone from every node
```

The node matters, because `local` is a different directory on every node. On a
**shared** storage the file is gone from every node at once, whichever node was
named, and the output says so rather than leaving someone to discover it.

A template that is not there is an error (exit 1), not a no-op: a mistyped volid
should not look like a successful removal. A malformed name is a usage error
(exit 2).

Removing a template does not affect containers created from it — a template is
copied when a container is made, not referenced.

### pause, resume

```bash
nexcage pause <name>
nexcage resume <name>
```

The cgroup freezer, which is what the runtime-spec means by paused: every process
in the container stops where it is and stays in memory. Nothing is written to
disk.

```bash
$ nexcage pause web-1
$ nexcage state web-1 | grep status
  "status": "paused",
$ pct status 100
status: running
```

**That last line is not a mistake.** Proxmox has no notion of a frozen container,
so `pct status` keeps saying `running`; `nexcage state` reads the freezer itself,
which is the only thing that knows.

This is **not** `pct suspend`. On a container that runs `lxc-checkpoint -s`,
which dumps the processes through CRIU and takes the container down — a
different operation, and on a stock Proxmox VE 9.2 host it simply fails.
nexcage never calls it.

Freezing happens on the host the container is on: for one on another node it is
refused, naming the node, because the cgroup filesystem there is not this host's
to write. On the crun backend both go to libcrun, which does the same thing for
the containers it owns.

A container that is not running has no cgroup to freeze, and that is an error
(exit 1) rather than silence.

### update

```bash
nexcage update [--memory <size>] [--memory-swap <size>] [--cpu-quota <us>] [--cpu-period <us>] [--cpu-share <n>] [...] <name>
nexcage update --resources <file|-> <name>
```

Changes a running container's resource limits, as `runc update` and `crun
update` do, with their flag names: `--memory`, `--memory-swap`,
`--memory-reservation`, `--cpu-quota`, `--cpu-period`, `--cpu-share` (or
`--cpu-shares`, the same setting),
`--cpuset-cpus`, `--cpuset-mems`, `--pids-limit`, `--blkio-weight`,
`--cpu-rt-period`, `--cpu-rt-runtime`, `--kernel-memory`,
`--kernel-memory-tcp`. Memory sizes take a binary suffix (`512M`, `2G`) or
`-1` for no limit; `--cpuset-cpus` and `--cpuset-mems` take a list (`0-1`);
everything else is a number.

`--resources <file>` is a runtime-spec `linux.resources` object, and `-` reads
it from stdin. **That is how containerd sends an in-place resize**:
`update --resources=- <id>` with the document on stdin. It cannot be combined
with the value flags.

On the crun backend everything reaches libcrun. On the Proxmox LXC backend the
settings are said to `pct set`, in its terms:

| runc's words | pct's |
|---|---|
| `--memory <bytes>` | `--memory <MiB>`, rounded up |
| `--memory-swap <bytes>` (memory plus swap) | `--swap <MiB>`, the difference from the memory limit — this call's, or the config's |
| `--cpu-quota` / `--cpu-period` | `--cpulimit <cores>`, quota over period; a quota of `-1` is `0`, no limit |
| `--cpu-share <shares>` | `--cpuunits <weight>`, converted the way runc converts cgroup v1 shares to a v2 weight (1024 → 39) |
| anything else | refused, naming the setting, because a limit asked for and silently not applied is the worst answer |

A container on another node is updated through that node's API
(`pvesh set /nodes/<node>/lxc/<vmid>/config`), which takes the same options.
Proxmox applies the change to the running container and keeps it in the
config, so it survives a restart — unlike a runtime's cgroup write.

```bash
$ nexcage update --memory 768M --cpu-quota 50000 --cpu-period 100000 web-1
$ pct config 100 | grep -E '^(memory|cpulimit):'
cpulimit: 0.5
memory: 768
$ cat /sys/fs/cgroup/lxc/100/memory.max
805306368
```

### snapshot, snapshots, rollback, delsnapshot

```bash
nexcage snapshot <name> <snapshot> [--description <text>]
nexcage snapshots [--format json|table] <name>
nexcage rollback <name> <snapshot> [--start]
nexcage delsnapshot <name> <snapshot>
```

Snapshots of a container's volumes, through Proxmox, with pct's verbs. Proxmox
holds the volumes and knows how to snapshot each kind of storage, so `snapshot`,
`rollback` and `delsnapshot` are each one `pct` call for a container on this
host and one call to the node's API for a container elsewhere; what nexcage
adds is the container by name, found on any node of the cluster.

The storage has to be one that can snapshot: zfs, lvm-thin, or a directory
storage holding qcow2. A raw volume on a directory storage cannot, and the
answer is then pct's refusal plus one line saying which storages can. The
snapshot's name is Proxmox's: letters, digits, `-` and `_`, not `current`, and
not one already used.

`rollback` of a running container stops it first: Proxmox kills it, as `pct
rollback` does, and it stays stopped unless `--start`, which brings it up
again as pct's own flag does. nexcage's `state` says `stopped` afterwards, as
it does after `stop`. Everything written since the snapshot is gone.

`snapshots` reads the node's API, for a container here as for one elsewhere,
because the API gives the times as numbers; they are printed as UTC. The
`current` entry Proxmox lists to mark the present state is not a snapshot and
is left out. The table is tab-separated; `--format json` is an array of
`{name, created, description, parent}`.

```bash
$ nexcage snapshot web-1 before-upgrade --description 'before 1.2'
$ nexcage snapshots web-1
NAME            CREATED                 DESCRIPTION
before-upgrade  2026-10-02T08:00:00Z    before 1.2
$ nexcage rollback web-1 before-upgrade --start
$ nexcage delsnapshot web-1 before-upgrade
```

These are Proxmox verbs, not runtime-spec ones: `--runtime crun` refuses them,
because libcrun has no storage of its own to snapshot. Exit status is `1` for
a refusal from Proxmox or a container that does not exist, `2` for a usage
error, as elsewhere.

### ps

```bash
nexcage --runtime crun ps [--format json|table] <name>
```

The host PIDs of the processes in the container's cgroup, children included.
Kubernetes asks for this: the kubelet's containerd sends `ps --format json <id>`
to list a task's processes, and before this existed nexcage answered `unknown
command 'ps'` — which containerd swallows without a word in its journal, so the
pod ran and nothing said the question had been asked.

```
$ nexcage --runtime crun ps --format json abc123
[
  11,
  14,
  15
]
```

`--format table` prints a `PID` header and one number per line. Neither form is
runc's table, which runs the host's `ps -ef` and filters it by those PIDs; crun
prints the numbers, and the values come from `libcrun_container_read_pids`, so
the answer is the one `crun ps` gives for the same container.

Answered by the crun backend only. On Proxmox LXC it is refused rather than
answered with something else: `pct exec <id> ps` reports the PIDs the container
sees in its own namespace, which is a different set of numbers for a different
question.

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
    "run.oci.crun.version": "1.30.1",
    "io.cageforge.nexcage.version": "0.15.0",
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

### health

```bash
nexcage health
```

Checks the host and prints a report on stderr, one PASS, WARN or FAIL line per
check. It exits 1 if any check failed and 0 otherwise; warnings do not fail.

These are failures: `pct version` missing or failing; any of
`/var/lib/nexcage`, `/var/cache/nexcage`, `/tmp/nexcage` and `/etc/pve/lxc` not
existing (fixed paths, not read from the configuration, and nexcage creates
none of them). These are only warnings: the Proxmox API line, which always warns
because that check is not implemented; `zpool status`; `ip link show`; no
config file; `pgrep nexcage`; and `df -h /`. It resolves no names and asks no
host outside this one.

It reports the config file the other commands read: the one `--config` names,
else the first of `./config.json`, `/etc/nexcage/config.json` and
`/etc/nexcage/nexcage.json` that exists. Like every command, `health` loads
that file first, and one that is not valid stops it there with exit 1, before
any check runs.

`nexcage health --help` prints help and runs no checks.

### version, help

```bash
nexcage version
nexcage --help
```
