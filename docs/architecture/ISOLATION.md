# Isolation by execution mode

nexcage runs a container in one of four ways, and what keeps the container
from the host, and from other containers, differs between them. For each way
this page says what nexcage guarantees, with the code that enforces it and the
test that fails if it stops; what it does not guarantee; and what the operator
has to add. The threat model these belong to is
[ADR-003](ADR-003-Security-Architecture.md); profiles are
[ADR-005](ADR-005-Isolation-Profiles.md); what each backend runs is
[BACKENDS.md](BACKENDS.md).

References are to the code on the 0.17.x hardening stack. `path:line` is a
line in this repository; `container.c:N`, `linux.c:N` and
`seccomp_notify.c:N` are lines of `deps/crun/src/libcrun/` at the pinned
commit 7d6f6955 (crun 1.30.1, unchanged). Simulator checks are named as
`tests/sim/run.sh:<line>`, the line the check is on.

## Which mode a container is in

| Mode | How it is made | Who can make it |
|---|---|---|
| Proxmox LXC from a template or a registry image | `create --name <n> <storage>:vztmpl/<file>`, `create --name <n> <registry ref>`, `run` | A person or a script, as root. A container engine cannot: it always passes `--pid-file`, which LXC `create` and `run` refuse (`src/cli/router.zig:259-287`; `tests/sim/run.sh:1510` for `create`, `:700`-`:705` for `run`) |
| Proxmox LXC from an OCI bundle | `create <id> --bundle <dir>` routed to LXC, without `--pid-file` | The same: a person or a script |
| crun, with the engine's bundle as it is | `create <id> --bundle <dir>` routed to crun (`--runtime crun`, a routing rule in `/etc/nexcage/config.json`, or `container_config.default_runtime: "crun"` there) | A container engine, or root at the command line |
| crun under an isolation profile | the same, with the program name `nexcage@<profile>` or `--profile <profile>` | The same; an engine picks it through the handler's `BinaryName` / `runtime_path` |
| Proxmox LXC under an isolation profile | `create --profile <p>` or `run --profile <p>` with a template or a registry image, where `<p>` has `"runtime": "lxc"` (#394) | A person or a script, as root. An engine handed such a profile is refused at `create`, by the profile's name (`src/cli/router.zig:214-224`; `tests/sim/run.sh:1434`) |

`create` picks the backend: a profile first, then `--runtime`, then the
routing rules, then the configuration's `container_config.default_runtime`,
which is Proxmox LXC unless the file sets it (`src/cli/router.zig:113-114`;
`getRoutedRuntime`, `src/core/config.zig:1106-1113`, the default at `:1097`,
read at `:719`). Every later
command goes to the backend whose record of the container is on disk
(`findBackend`, `src/cli/router.zig:489-501`), so a container stays in the
mode it was made in.

## Proxmox LXC from a template or a registry image

The container is a Proxmox VE system container. nexcage turns the command
into `pct create` (or the node's API with `--node`) and adds nothing to
Proxmox's confinement and takes nothing away.

**Guaranteed**

| What | Enforced by | Test |
|---|---|---|
| Unprivileged unless the configuration says `proxmox.unprivileged: false` | `src/backends/proxmox-lxc/driver.zig:384-396` | `tests/sim/run.sh:262` "no config file -> default bridge, unprivileged, no --rootfs"; `:259` |
| A registry image's template is always unprivileged: `--unprivileged 0` is never sent for one, and the setting is named in a warning | `src/backends/proxmox-lxc/driver.zig:385-396` | `tests/sim/run.sh:202` |
| No Proxmox feature (`nesting`, `keyctl`, ...) and no raw `lxc.*` key is set by nexcage; the `pct create` argument vector is built from the name, the template, the configuration's bridge, storage, size and OS type, and the operator's own options | `src/backends/proxmox-lxc/driver.zig:319-421` | `tests/sim/run.sh:109` "pct create argv: vmid, template, hostname, bridge, rootfs from config" |
| A registry reference is pulled under a file name derived from the whole reference, and only that exact file is used; a template whose name merely contains the image's, or one another writer adds during the pull, is never taken | `findTemplate`, `pullTemplate`, `pullVolid`, `src/backends/proxmox-lxc/pve.zig:286-396`; `pulledTemplateName`, `:1991-2013` | `pve.zig` test "a pulled template is named for the whole reference, and two references never share a name"; `tests/sim/run.sh:209`, `:215`, `:220`, `:229`, `:233` |
| The name is a hostname (RFC 1123), and no container the cluster's listing names has it at `create`; a cluster that cannot be asked refuses the create (the check holds no lock: see "A unique name" below) | `src/backends/proxmox-lxc/driver.zig:111-153`, `src/core/validation.zig:25-57` | `validation.zig` test "a hostname is RFC 1123's ..."; `tests/sim/run.sh:121`-`:124`, `:313`, `:1981` |
| A create that fails after `pct create` destroys the CT and its record | `src/backends/proxmox-lxc/driver.zig:453-457`, `undoCreate` `:527-555` | `tests/sim/run.sh:1065`, `:1070`, `:1081` |

**Not guaranteed**

- **Privileged containers.** With `proxmox.unprivileged: false` the container
  is privileged: its root is host root. That is the configuration's choice,
  and the configuration is root's (`src/core/config.zig:509-556`).
- **A unique name.** The cluster's listing is read at `create`, and nothing
  holds the name from then until `pct create` has made the container. Two
  overlapping creates of one name can both succeed, on one node or on two;
  so can a create while the container that has the name is on a node down
  long enough for the cluster to list its containers without names
  (`src/backends/proxmox-lxc/driver.zig:116-126`). Every later command then
  refuses the name, naming both containers, and touches neither
  (`tests/sim/run.sh:2026`). The audit's
  [residual item 8](../audits/2026-10-hardening-audit.md#residual-risks-and-open-items)
  proposes a lock.
- **The operator's options.** `--mp`, `--tags` and the other `pct` options
  of `create` reach pct as written (`src/backends/proxmox-lxc/driver.zig:415-421`;
  `tests/sim/run.sh:287`), but for `--ip`, `--gw` and `--vlan`, which are
  checked first (`src/cli/create.zig:129-152`). `--mp /,mp=/host` binds the
  host's root directory. Whoever runs nexcage is root already.
- **The template's contents.** nexcage checks a template's name, not what is
  in it. Anyone with `Datastore.AllocateTemplate` on the storage can upload a
  file under the name nexcage derives for a reference, and `create` then uses
  it without pulling: `findTemplate` compares the name alone
  (`src/backends/proxmox-lxc/pve.zig:275-292`). No image digest is recorded
  or checked, and a mutable tag such as `:latest` is reused, not refreshed.
- **Proxmox's confinement itself.** The AppArmor profile, capability drops,
  seccomp filter and device rules are pve-container's and LXC's. nexcage does
  not check that they are in force on the host.

**The operator adds:** `proxmox.unprivileged` left at its default;
`Datastore.AllocateTemplate` on template storages only for those trusted to
choose what every container runs; images from registries they trust (Proxmox's
pull takes no digest, see [CLI_REFERENCE.md](../CLI_REFERENCE.md#pull)).

## Proxmox LXC from an OCI bundle

The bundle's `rootfs/` is packed into an archive that `pct create` unpacks
into a system container. From `config.json` the backend takes the bind
mounts, `memory.limit` and `cpu.shares`, and nothing else
([BACKENDS.md](BACKENDS.md#a-container-from-an-oci-bundle)).

**Guaranteed**

| What | Enforced by | Test |
|---|---|---|
| A `config.json` with a value of the wrong type in the parts that are type-checked is refused before anything is packed or created: `mounts` (a list), each mount (an object) and its `source`, `destination`, `type` and `options`; `linux`, `linux.resources` and its `memory` and `cpu` (objects) and their `limit` and `shares` (integers); `linux.memoryPolicy`, `linux.intelRdt` and `linux.netDevices`; and each entry of `process.args` and `process.env` (strings). Elsewhere a wrong type is passed over with no error: a `root` or `process` that is not an object, a `hostname` that is not a string, `args` or `env` that is not a list, a `linux.seccomp` that is not an object, and a namespace entry that is not an object or has no string `type`, which is read as `pid`. The backend applies none of those | Refused: `deps/oci-spec-zig/src/runtime/bundle.zig:207-237`, `:240-466`, `:632-677` (`InvalidConfigFormat`); passed over: `:162-200`, `:473-516`; `src/backends/proxmox-lxc/driver.zig:262-273` | `oci.zig` tests "a config.json with a mount, arg or env entry of the wrong type is refused, not crashed on" and "mounts, linux, resources, memory or cpu of the wrong kind are refused, not skipped"; `tests/sim/run.sh:865`, `:871`, `:878` |
| Only bind mounts become mount points. A source and a destination have to be absolute, normalised paths with no control character (C0, DEL, C1), no U+2028/U+2029, no `,` and no `=`; a destination of `/`, a source under `/dev/`, more than 256 bind mounts, and a mount of any other type are refused, before anything is packed; the kernel filesystems a runtime-spec bundle mounts at their usual places (`/proc`, `/sys`, `/dev`, ...) are left to LXC | `bundleMountPoints`, `mountPathProblem`, `src/backends/proxmox-lxc/oci.zig:358-405`, `:566-584` | `oci.zig` tests "a mount path goes into a pct property string only when absolute, normalised and free of separators", "a mount pct cannot take as a bind mount is refused, and nothing leaks", "more bind mounts than a container has mount points are refused, and nothing leaks"; `tests/sim/run.sh:1110`, `:1118`, `:1122` |
| A bind mount's `ro`, `nosuid`, `nodev`, `noexec` and `noatime`, and each one's recursive `r` form, reach the mount point (`ro=1`, `mountoptions=`). `bind`, `rbind`, `rw`, `rrw`, `private`, `rprivate`, `slave` and `rslave` are accepted and change nothing (see *Mount semantics* below). Any other option is refused, not dropped | `mountPointSpec`, `bindOption`, `src/backends/proxmox-lxc/oci.zig:418-446`, `:532`, `:541-550` | `oci.zig` tests "a bind mount's ro, nosuid, nodev and noexec reach its mount point" and "a bind mount option Proxmox has nothing for is refused, not dropped"; `tests/sim/run.sh:1047` |
| The mount points are given to `pct set --mpN` once the CT exists, so Proxmox parses each property string; nothing is written to `/etc/pve/lxc/<vmid>.conf` by nexcage | `applyMountPoints`, `src/backends/proxmox-lxc/oci.zig:459-486` | `tests/sim/run.sh:1039` |
| The bundle's namespaces turn on no Proxmox feature (`nesting`, `keyctl`) | `src/backends/proxmox-lxc/driver.zig:459-466` (no `pct set --features` anywhere in `src/`) | `tests/sim/run.sh:897`, `:972` |
| These confinement fields of a bundle, which this backend does not apply, are named in one warning on stderr and in the log (neither under `--log-level error`): `process.capabilities`, `noNewPrivileges`, `apparmorProfile`, `selinuxLabel`, `rlimits`, `root.readonly`, `linux.seccomp`, `maskedPaths`, `readonlyPaths`, `devices`, `resources.devices`, and the options of mounts left to LXC. A user namespace under `proxmox.unprivileged: false` is not among them: see *Namespaces* below | `warnUnappliedConfinement`, `src/backends/proxmox-lxc/oci.zig:325-337`; `Confinement`, `deps/oci-spec-zig/src/runtime/bundle.zig:803-815` | `oci.zig` test "the confinement a bundle asks for is named, and a bundle that asks for none gets no list"; `tests/sim/run.sh:985`, `:992`, `:1019` |
| So are the `linux.resources` it does not apply | `warnUnappliedResources`, `src/backends/proxmox-lxc/oci.zig:303-313` | `tests/sim/run.sh:1164`, `:1168` |
| `memory.limit` and `cpu.shares` are checked before they reach pct: a negative limit other than -1, one below Proxmox's 16 MiB, and shares past the kernel's 262144 are refused | `bundleResources`, `src/backends/proxmox-lxc/oci.zig:267-295` | `oci.zig` tests "memory.limit -1 is no limit ...", "a memory.limit below the 16 MiB ...", "cpu.shares past the kernel's maximum is refused, not cast"; `tests/sim/run.sh:1134`-`:1156` |
| The packed rootfs is a 0600 file in a fresh 0700 directory under a `$TMPDIR` (or `/var/tmp`) that only root or nexcage's user owns and that is sticky if others can write it; it is removed after `pct create`, on failure, and on SIGINT, SIGTERM and SIGHUP, which share one handler (`src/backends/proxmox-lxc/oci.zig:51-52`; the simulator sends SIGTERM) | `createTemplateFromBundle`, `archiveBase`, `interrupt_cleanup`, `src/backends/proxmox-lxc/oci.zig:47-233` | `tests/sim/run.sh:886`, `:890`, `:893`, `:901`, `:907`, `:914`, `:931`, `:939`, `:967` |
| `--mp` together with a bundle is refused | `src/backends/proxmox-lxc/driver.zig:255-260` | `tests/sim/run.sh:1025` |
| Unprivileged by default, a failed create undone, the name a hostname no listed container has at `create`: as for a template, above | | |

**Not guaranteed**

- **The bundle's own hardening.** Everything the warning above names is not
  applied: the container gets Proxmox's confinement instead, neither looser
  nor tighter. A bundle cannot drop a capability or add a seccomp rule on this
  backend. Use the crun backend for that.
- **Namespaces.** LXC makes the container's namespaces. A bundle's request to
  share a host namespace (an absent entry) or to join one by `path` is not
  honoured, and its uid and gid mappings are not read
  (`deps/oci-spec-zig/src/runtime/bundle.zig:484-514` parses the list; nothing
  in `src/backends/proxmox-lxc/` reads it). Whether the container has a user
  namespace is the configuration's `proxmox.unprivileged` alone: a bundle with
  a user namespace under `unprivileged: false` is created privileged, and
  nothing says so.
- **Host bind mounts.** Any host directory can be a mount source; there is no
  list of paths a bundle may not mount (decided in fixing F001, 1e19a8b0;
  runc and crun have none either). Through the mount the container has the
  rights of the host ids it runs as. In an unprivileged container those are
  Proxmox's default map, container ids 0 to 65535 as host ids 100000 to
  165535; nexcage sets no other map (no raw `lxc.*` key,
  `src/backends/proxmox-lxc/driver.zig:319-421`), so every unprivileged
  container on the node has the same ids. The container reads and writes
  what any user may, world-writable files and directories that root owns
  included, and has an owner's rights over every file those ids own: a
  mount of another unprivileged container's volume (a ZFS storage's
  `subvol-<vmid>-disk-<n>`, for example) gives it that container's files,
  its root's included. In a privileged container it is host root on
  whatever the mount shows
  ([BACKENDS.md](BACKENDS.md#a-container-from-an-oci-bundle)).
- **Mount semantics.** `rbind` is Proxmox's non-recursive bind, so the
  container sees less than asked, never more. `private` and `rprivate` are
  accepted, but LXC makes the container's mounts slaves of the host's, so a
  mount made later under the source on the host appears in the container. A
  file as a source passes `create` and fails at `pct start`.
- **The rootfs as packed.** `tar -p --numeric-owner` keeps modes, owners and
  setuid bits (`src/backends/proxmox-lxc/oci.zig:152`). What may run as root
  in the container is decided by the user namespace, not by nexcage.
- **The rest of `config.json`.** `process.user`, `args`, `env` and `cwd` (the
  rootfs's init is booted), `hostname` (the container's name is), hooks,
  annotations, `sysctl`, `cgroupsPath` and every resource but the two above
  are not applied.

**The operator adds:** the bundle is root's to vet. Read its mounts before
creating a container from it: a host path, another container's volume, and
a world-writable directory are all reachable. Keep `proxmox.unprivileged` at
its default.

## Proxmox LXC under an isolation profile

A profile with `"runtime": "lxc"` is a named set of the `proxmox` and
`network` settings for the containers `create --profile` and `run --profile`
make under it: storage, root filesystem size, bridge, OS type, cores and
memory (#394; [ADR-005](ADR-005-Isolation-Profiles.md)). It is for the
command line. Everything said above for a template or a registry image holds
as well; a profile chooses among the settings an administrator wrote, and
adds no confinement of its own.

**Guaranteed, in addition**

| What | Enforced by | Test |
|---|---|---|
| `pct create` gets the profile's storage, size, bridge, cores and memory; what the profile leaves out comes from the file's `proxmox` and `network` sections | `src/cli/router.zig:234-245` | `tests/sim/run.sh:1387`, `:1397` |
| A profile cannot make a container privileged: `unprivileged` takes only `true`, and `false` refuses the whole file | `src/core/config.zig:848`, `:944-947` | `tests/sim/run.sh:1441` |
| `--cores` and `--memory` may ask for less than the profile's values; more, or `--memory -1`, exits 2 naming the profile, and nothing is made | `withinProfile`, `src/cli/router.zig:187-203` | `tests/sim/run.sh:1403`, `:1406`, `:1409`, `:1424` |
| A bundle's memory and CPU shares above the profile's are lowered to it, and a bundle's "no limit" gets the profile's memory | `src/backends/proxmox-lxc/driver.zig:340-345` | `tests/sim/run.sh:1413`, `:1417`, `:1421`, `:1428` |
| `state` names the profile the container was made under, from the record `create` writes; `start` and `stop` carry it forward | `writeOciState`, `persistedProfile`, `src/backends/proxmox-lxc/driver.zig:1015-1040`, `:976` | `tests/sim/run.sh:1390`, `:1394`, `:1401` |
| A profile's section must be its own backend's: `crun` parameters under `"runtime": "lxc"`, which would do nothing, refuse the file | `src/core/config.zig:924` | `tests/sim/run.sh:1445`; `config.zig` test "a profile that is misspelt, mis-named or names what it cannot do refuses the file" |

**Not guaranteed**

- **An unprivileged container, unless the profile says so.** A profile that
  leaves `unprivileged` out takes the file's `proxmox.unprivileged`, which
  may be `false` (`src/cli/router.zig:241`).
- **Anything a bundle asks for beyond its limits.** The bundle's own
  hardening is not applied, as in the previous section.
- **An engine.** A container engine cannot use such a profile; its handler
  has to name a profile on crun ([ADR-006](ADR-006-LXC-Driven-By-An-Engine.md)).

## crun, with the engine's bundle as it is

libcrun makes the container from the engine's `config.json`, in the nexcage
process. Isolation is what the bundle says, and libcrun honours almost all of
it. Under Kubernetes the bundle is what the engine built from the pod spec,
after admission; Pod Security Admission decides what is in it, not nexcage.

**Guaranteed**

| What | Enforced by | Test |
|---|---|---|
| The container id is 1 to 64 of `[A-Za-z0-9_-]`, on every driver entry, and one path component in every state lookup | `validateContainerId`, `src/core/validation.zig:8-22`, called at `src/backends/crun/libcrun_driver.zig:202`, `:315`, `:352`, `:394`, `:478`, `:636`, `:781`, `:808`, `:853`; `src/core/state_root.zig:103-106` | None for the id's characters; the lookups' refusal of `..` and `/` by `router.zig` test "under --root the Proxmox LXC records are in their own directory" |
| The bundle path is absolute and resolved | `validateBundlePath`, `src/core/validation.zig:83-89`, called at `src/backends/crun/libcrun_driver.zig:217` | None on crun. `tests/sim/run.sh:859` refuses a relative path through the Proxmox LXC backend's call of the same function (`src/backends/proxmox-lxc/driver.zig:248`) |
| libcrun is given the bytes nexcage read and checked, never the bundle's `config.json` to read again | `src/backends/crun/libcrun_driver.zig:242-274` (`libcrun_container_load_from_memory`) | `tests/crun/memory_values.sh`: "create hands libcrun the spec it checked, and libcrun does not read the bundle's file again" |
| A key or a string with a NUL, or nesting deeper than 64 levels, is refused in the spec, an update's resources document and the stored config, with or without a profile: libcrun's parser would read another document than the one checked | `parse`, `checkDocument`, `src/core/profile.zig:441-509`; `checkUnclaimed` `:153-157`; `checkMemoryJson`, `src/backends/crun/libcrun_driver.zig:756-778` | `profile.zig` tests "a key or a string with a NUL in it is refused ..." and "a NUL in a key or a string, or nesting past any runtime spec, is refused in every document read"; `tests/crun/memory_values.sh` |
| A bundle cannot carry `io.cageforge.nexcage.profile` or an annotation under it | `refuseClaim`, `src/core/profile.zig:456-463` | `profile.zig` test "without a profile, a bundle may not claim one, nor hide a claim in a duplicate key" |
| Memory values libcrun's int64 arithmetic would overflow on (UBSan traps in the release build) are refused on create and update | `checkMemory`, `src/backends/crun/libcrun_driver.zig:728-748`; `build.zig:154-162` | `libcrun_driver.zig` test "memory values libcrun would overflow on are refused before it sees them"; `tests/crun/memory_values.sh` |
| `create` and `exec` re-execute from a sealed copy of the binary first (the CVE-2019-5736 protection) | `runFromSealedCopy`, `src/backends/crun/libcrun_driver.zig:178-192`; libcrun's constructor compiled out, `build.zig:171-198` | `tests/crun/rexec.sh` |
| The process spec an `exec` writes is a new 0600 file with a random name in the container's 0700 state directory, created `O_EXCL\|O_NOFOLLOW`, and removed afterwards | `writeSpecFile`, `src/backends/crun/libcrun_driver.zig:952-997` | `libcrun_driver.zig` test "exec's process spec is a new 0600 file in the container's own state directory"; `tests/crun/exec_spec.sh` |
| `--systemd-cgroup` reaches libcrun wherever an engine puts it, before the command or after it, and the shipped handlers set `SystemdCgroup`, which has to match the kubelet's cgroup driver: a container is placed under its pod's cgroup and limits, not at the root of the hierarchy | `findCommand`, `src/main.zig:423-477`, folded in at `:253-260`; `deploy/kubernetes/node/containerd.toml:17`, `deploy/kubernetes/node/k3s-config-v3.toml.tmpl:21` | `main.zig` test "findCommand: --systemd-cgroup before the command is recorded, in each engine's order"; `tests/crun/systemd_cgroup.sh`; on a node, `in_pod_cgroup` in `tests/k8s/pod_on_node.sh:205` (`k8s_e2e.yml`) |
| A signal is validated once and libcrun gets its number | `src/backends/crun/libcrun_driver.zig:363-373`, `src/core/signals.zig:57-73` | `tests/crun/kill.sh` |
| One id is one backend's: a crun create of an id the Proxmox backend has is refused, and the reverse | `src/cli/router.zig:139-148` | `tests/crun/lxc_root.sh` |

**Not guaranteed**: libcrun honours the bundle, so a bundle can ask for, and
get:

- **Host namespaces.** An absent namespace entry shares the host's; one with
  a `path` is joined with `setns` (`linux.c:5378-5412`).
- **Privilege.** Any capability set, no seccomp filter when `linux.seccomp`
  is absent, an AppArmor profile of `unconfined`, no `noNewPrivileges`, all
  devices, `process.user` root, a writable root and no masked paths. With no
  `process.capabilities` at all the container gets none (`container.c:996-998`).
- **Host bind mounts** of any path, idmapped mounts, `sysctl`, `rlimits` and a
  `cgroupsPath` of its choosing.
- **Hooks, run as host root.** `prestart` and `createRuntime` run in the
  runtime's namespaces at create (`container.c:2659-2675`), `createContainer`
  and `startContainer` in the container's (`container.c:1074`, `:1377`),
  `poststart` (`container.c:2716`), and `poststop` at delete
  (`container.c:1501-1520`).
- **`run.oci.*` annotations**, which libcrun acts on in the root process:
  `run.oci.hooks.stdout` and `.stderr` open host paths with `O_CREAT` as root
  (`container.c:1204-1213`); `run.oci.seccomp.plugins` names shared objects
  libcrun loads with `dlopen` in nexcage's process while it waits for a
  process that has a seccomp filter (`container.c:2194`, `:1905-1932`,
  `seccomp_notify.c:119`). The release build has the code: crun's
  `./configure` on Ubuntu 26.04 (`scripts/gen_crun_headers_local.sh`,
  `Dockerfile`) writes `HAVE_DLOPEN`, `HAVE_SECCOMP` and
  `HAVE_SECCOMP_GET_NOTIF_SIZES` into `config.h`, as the builder image of
  2026-10-10 shows. `create` does not wait: libcrun makes it detached
  (`container.c:2969`), nexcage gives libcrun no notify socket
  (`src/backends/crun/libcrun_driver.zig:75`), and the wait ends before the
  plugins are loaded (`container.c:1879-1880`). An `exec` without
  `--detach` into a container with a filter does wait, and loads the
  plugins the container's stored config names (`container.c:3657-3661`,
  `:3829-3852`); `run.oci.seccomp.receiver` and
  `run.oci.pidfd_receiver` connect to sockets (`container.c:2213`,
  `linux.c:6422`); `run.oci.keep_original_groups` keeps the caller's
  supplementary groups (`linux.c:4423`); `run.oci.mount_context_type`
  (`linux.c:1456`); `run.oci.seccomp_bpf_data` installs a precompiled filter
  (`container.c:2514`). `nexcage features` lists libcrun's own
  "potentially unsafe" annotation prefixes (`src/backends/crun/libcrun_driver.zig:613-614`;
  `container.c:186-192`).
- **`exec --process`.** The engine's process spec is handed to libcrun by its
  path, as written (`src/backends/crun/libcrun_driver.zig:861-864`): its
  capabilities, user, `noNewPrivileges`, AppArmor profile and rlimits apply.
  Where it names no capabilities, label, profile or user, libcrun takes the
  container's (`container.c:3508-3511`, `:3716-3730`).
- **`exec` at the command line.** The spec nexcage writes runs the command
  as uid 0, gid 0 unless `--user` says otherwise, with `PATH` alone in its
  environment and no capabilities of its own, so the container's apply; the
  container's seccomp filter, AppArmor profile and SELinux label apply; and
  `noNewPrivileges` is false (`writeProcessSpec`,
  `src/backends/crun/libcrun_driver.zig:1001-1044`). runc's CLI exec takes
  the container's `process.user` instead; this form is for an operator who is
  root already.
- **`update`** applies what the engine sends, past the memory checks above.
- **Memory safety in libcrun's C.** The release build compiles libcrun with
  UBSan in trap mode (`build.zig:154-162`), so the undefined behaviour UBSan
  checks, such as signed overflow, a bad shift or a null pointer, stops the
  process with `SIGILL`. Memory errors are not caught: a heap overflow, a
  use after free or an uninitialised read in the code that parses a bundle
  goes on, in the root process.

**The operator adds:**

- **Kubernetes Pod Security Admission**, `baseline` at least and `restricted`
  for workloads that are not trusted. It is what keeps host namespaces,
  `privileged`, `hostPath` volumes, added capabilities and an unconfined
  profile out of the bundle.
- **No annotation allowlist for `run.oci.*`** on a nexcage handler. Pod
  annotations reach the bundle only through containerd's `pod_annotations` /
  `container_annotations` and CRI-O's `allowed_annotations`
  ([ADR-005](ADR-005-Isolation-Profiles.md#constraints)); the shipped
  handlers set none (`deploy/kubernetes/node/containerd.toml`,
  `k3s-config-v3.toml.tmpl`, `crio.conf`).
- **The same care with podman.** Whoever may run `podman --runtime nexcage`
  as root chooses everything above (`--privileged`, `-v`, `--annotation`,
  `--security-opt`).

## crun under an isolation profile

The profile is applied to the parsed bundle at `create`, and libcrun is given
the result, serialised again, so libcrun and the checks read the same
document (`narrow`, `src/core/profile.zig:161-199`). Everything in the
previous section holds as well.

**Guaranteed, in addition**

| What | Enforced by | Test |
|---|---|---|
| A profile that is named and not defined, a program name and `--profile` that disagree, and a `--runtime` the profile does not name exit 2 and create nothing; `run` with a crun profile fails, as crun has no `run`, and creates nothing; there is no fallback to no profile | `src/main.zig:280-293`; `findProfile`, `src/cli/router.zig:159-181`; crun's `run`, `src/cli/router.zig:435` | `tests/sim/run.sh:1359`, `:1368`, `:1371`, `:1373`, `:1375`, `:1377` |
| `capabilities.drop` removes those names from all five capability sets. The drop list must be the kernel's names, and so must every capability in the bundle: libcap would read `cap_net_raw`, `13` or `CAP_NET_RAW2` as `CAP_NET_RAW` past a drop that compares names | `dropCapabilities`, `checkCapabilityNames`, `src/core/profile.zig:830-839`, `:244-257`; `src/core/config.zig:952-962` | `profile.zig` tests "a profile drops capabilities from every set ...", "a capability spelt otherwise than the kernel spells it is refused ..."; `config.zig` test "a profile that is misspelt, mis-named or names what it cannot do refuses the file"; `tests/crun/profile.sh` (CapBnd from `/proc`) |
| `user_namespace: "require"`: a user namespace with uid and gid mappings, none of which maps host id 0. A namespace joined by `path` has to be on nsfs, a user namespace, not nexcage's own, and leave host uid and gid 0 out, read from inside it; one that cannot be read is refused. `run.oci.keep_original_groups` other than `"0"` is refused | `checkUserNamespace`, `checkJoined`, `refuseKeptGroups`, `src/core/profile.zig:635-749`, `:674-678` | `profile.zig` tests "a user namespace that leaves the container's root the host's is refused", "a user namespace joined by path is read from inside it ...", "a bundle that keeps nexcage's own groups ..."; `tests/crun/profile.sh` |
| `seccomp: "require"`: a filter that refuses some system call by itself, by its default action or a rule naming a call (`KILL`, `KILL_PROCESS`, `KILL_THREAD`, `TRAP`, `ERRNO`); `run.oci.seccomp_bpf_data` is refused | `checkSeccomp`, `refusePrecompiledSeccomp`, `src/core/profile.zig:580-619` | `profile.zig` tests "a seccomp filter that refuses no system call does not meet a profile that requires one", "a precompiled seccomp program does not meet ..."; `tests/crun/profile.sh` |
| `limits.memory` and `limits.pids` lower `memory.limit` and `pids.limit`, and set them when absent; `memory.swap` keeps only the swap the bundle asked for; `memory.max`, `memory.high` and `pids.max` under `linux.resources.unified` are lowered too | `lowerTo`, `lowerMemory`, `lowerUnified`, `src/core/profile.zig:859-915` | `profile.zig` tests "lowering the memory limit keeps the swap the bundle allowed, and no more", "linux.resources.unified does not undo a profile's limits"; `tests/crun/profile.sh` (cgroup files) |
| `update` cannot take memory or pids above the caps recorded at create, or to no limit | `boundUpdate`, `src/core/profile.zig:273-338`; `holdToProfile`, `src/backends/crun/libcrun_driver.zig:697-715` | `profile.zig` test "update holds a container made under a profile to the caps recorded at create"; `tests/crun/profile_update.sh` |
| `exec --process` into the container gets every capability set cut to the container's bounding set, from the config libcrun stored at create | `boundExec`, `src/core/profile.zig:208-235`; `boundProcessFile`, `src/backends/crun/libcrun_driver.zig:901-926` | `profile.zig` test "an exec into a container made under a profile gets no capability the container lacks"; `tests/crun/profile.sh`, `tests/crun/exec_spec.sh` |
| `state` reports the profile it was made under: nexcage writes the profile's name into the spec libcrun stores at create, and libcrun's `state` prints that stored config's annotations | `src/core/profile.zig:192-197`; `libcrun_container_state`, `container.c:3294-3299` | `tests/crun/profile.sh` |

**Not covered by a profile**

A profile names five things. Everything else in the bundle is as the previous
section describes:

- **Host namespaces** other than the user namespace: an absent `network`,
  `pid`, `ipc`, `uts`, `mount` or `cgroup` entry still shares the host's.
- **Devices, mounts (host bind mounts included), AppArmor and SELinux,
  `noNewPrivileges`, a read-only root, masked and read-only paths, `sysctl`,
  `rlimits`, `process.user`, `cgroupsPath` and CPU limits.**
- **Hooks**, run as host root, and every `run.oci.*` annotation but the two
  refused above.
- **Swap.** A bundle's `memory.swap` of -1 or none, and unified
  `memory.swap.max`, are left as they are (`lowerMemory`,
  `src/core/profile.zig:906-915`).
- **What a filter refuses.** One refused call by its own action is enough;
  which call, a rule's `args`, and calls the kernel lacks are not judged
  (`src/core/profile.zig:571-579`).
- **A joined user namespace after the check.** libcrun opens the path again
  after nexcage read it (`src/core/profile.zig:707-709`).
- **An `exec --process` spec without capabilities**, which libcrun reads again
  from the engine's file and gives the container's capabilities; and the
  rest of any exec spec: its user, `noNewPrivileges`, AppArmor profile,
  rlimits and environment.
- **Commands other than `create`, `update` and `exec`**, which do not consult
  the profile; and containers made by an earlier nexcage, which carry no
  recorded caps.
- **A wrapper that `exec`s nexcage without `exec -a`**: the program name, and
  with it the profile, is lost, and the container is made by routing
  ([ADR-005](ADR-005-Isolation-Profiles.md#failure-modes)).

A profile only narrows (ADR-005 decision 4): it never adds a capability,
raises a limit or loosens a requirement. So it is never a reason to relax
admission policy.

**The operator adds:**

- a `RuntimeClass` per profile, and admission policy over which pods may use
  which class and whether a pod may leave `runtimeClassName` out;
- Pod Security Admission as above, with `hostUsers: false` and
  `seccompProfile.type: RuntimeDefault` where the profile requires them;
- the `nexcage@<profile>` links and the configuration file owned by root and
  writable only by it (`src/core/config.zig:509-556` refuses any other).

## The bundle's fields, by mode

What becomes of each part of a runtime-spec bundle. "Proxmox's" means pve-container
and LXC apply their own and the bundle's is not read.

| Bundle field | Proxmox LXC from a bundle | crun, as is | crun, profile |
|---|---|---|---|
| Namespaces, host ones (an absent entry), `path` joins | LXC's own; not read | Honoured | Unchanged, except the user namespace |
| User namespace, uid/gid mappings | Not read; `proxmox.unprivileged` decides | Honoured | Required, host id 0 unmapped, a joined one checked |
| `process.capabilities` | Proxmox's; named in the warning | Honoured | Drop list removed; kernel spelling required |
| `linux.seccomp` | Proxmox's; named | Honoured | Required to refuse a call; precompiled program refused |
| AppArmor, SELinux | Proxmox's; named | Honoured | Unchanged |
| `noNewPrivileges` | Not applied; named | Honoured | Unchanged |
| Mounts | Bind mounts only, checked; options kept or refused | Honoured | Unchanged |
| Devices | Proxmox's; named | Honoured | Unchanged |
| `rlimits` | Not applied; named | Honoured | Unchanged |
| `root.readonly`, masked and read-only paths | Not applied; named | Honoured | Unchanged |
| Memory and pids | `memory.limit` as `--memory`; pids not applied, named | Honoured, overflow-checked | Lowered to the profile's, held there on `update` |
| CPU | `cpu.shares` as `--cores`; the rest named | Honoured | Unchanged |
| `sysctl`, `cgroupsPath` | Not read | Honoured | Unchanged |
| Hooks | Not read | Run as host root | Unchanged |
| `run.oci.*` annotations | Not read | Honoured by libcrun | `seccomp_bpf_data` and `keep_original_groups` refused when the profile requires seccomp or a user namespace; the rest unchanged |
| `io.cageforge.nexcage.profile*` annotations | Not read | Refused | Refused, then written by nexcage |
| `process.user`, `args`, `env`, `cwd`, `hostname` | Not applied: the rootfs's init boots under the container's name | Honoured | Unchanged |
