# nexcage 0.13.0

`update` — the last runtime-spec verb that was missing — vendored crun moves
from 1.24 to 1.30.1, and two things are removed: the runc backend, which
nothing ever built or ran, and `crun_name_patterns`.

## Read this first if you install the `-crun` binary

**It needs `libjson-c5` now, not `libyajl2`.** crun 1.28 replaced YAJL with
json-c, libocispec included, and the vendored crun is 1.30.1 in this release.

```bash
apt install libjson-c5 libseccomp2 libcap2
```

A Proxmox VE 9 host has all three already — it never had `libyajl2`, so this
is one library fewer to install than before. On a host without it the binary
does not start: `error while loading shared libraries: libjson-c.so.5`. The
plain binary needs none of this, as before.

## update

```
$ nexcage update --memory 768M --cpu-quota 50000 --cpu-period 100000 web-1
$ pct config 100 | grep -E '^(memory|cpulimit):'
cpulimit: 0.5
memory: 768
$ cat /sys/fs/cgroup/lxc/100/memory.max
805306368
```

A running container's resource limits, as `runc update` and `crun update` do,
with their flag names: `--memory`, `--memory-swap`, `--cpu-quota`,
`--cpu-period`, `--cpu-share`, `--pids-limit` and the rest. `--resources
<file>` takes a runtime-spec `linux.resources` document, and `-` reads it from
stdin — **which is how containerd sends an in-place pod resize**
(`update --resources=- <id>`). The CRI test asks for one now and reads the
container's cgroup afterwards.

On the crun backend everything reaches libcrun. On Proxmox LXC the settings
are said to `pct set` in its own terms:

| runc's words | pct's |
|---|---|
| `--memory <bytes>` | `--memory <MiB>`, rounded up |
| `--memory-swap <bytes>`, memory plus swap | `--swap <MiB>`, the difference |
| `--cpu-quota` / `--cpu-period` | `--cpulimit <cores>`; `-1` lifts it |
| `--cpu-share <shares>` | `--cpuunits <weight>`, converted as runc converts v1 shares to a v2 weight — 1024 → 39 |
| pids, cpusets, reservations, kernel memory | **refused, naming the setting** |

That last row is deliberate: a limit asked for and silently not applied is the
worst answer an update can give. A container on another node is updated
through its node's API. Proxmox keeps the change in the config, so it survives
a restart — a runtime's cgroup write does not.

## The runc backend is gone

It shelled out to a `runc` binary, no workflow ever built it, and it had never
been run; the crun backend answers the same OCI interface through libcrun and
is what every engine was verified against. Two things a configuration might
still say:

- a routing rule with `"runtime": "runc"` **routes to crun** — the container
  it describes is an OCI container either way — and the log says the file
  should say so;
- `--runtime runc` on the command line is refused with the replacement
  named: `use --runtime crun`. Exit 2.

`container_config.crun_name_patterns` is removed as well. It routed names
matching a glob to crun before `runtime.routing` existed; a glob under
`routing` is the same matcher, so each entry is one rule:

```json
{ "runtime": { "routing": [ { "pattern": "kube-ovn-*", "runtime": "crun" } ] } }
```

A file that still carries the old key gets a warning naming the replacement,
because a container it used to send to crun now goes to the default backend,
and that should not happen without a word.

## Fixed

`create` from a registry image called the pull endpoint **every time** and then
guessed the volid from the reference — a guess about how Proxmox normalises a
file name — onto `local` whatever was asked. It now reuses an image that is
already on the storage, what a container engine does, and otherwise pulls the
way `pull` does, reading the volid back from the storage. `create --storage`
and `run --storage` say which storage. On the real host the evidence is
Proxmox's own task record: a second `create` from the same reference adds no
`ociregistrypull` task.

## ADR-001 says what ships

The architecture decision from 2024 chose crun as the primary runtime with
runc as an automatic fallback, and assumed nexcage would call a runtime
binary. It now records the reality: Proxmox LXC is the default backend, crun
is libcrun linked in and what an engine's host routes to, there is no fallback
between backends, and there is no runc. `docs/architecture/BACKENDS.md` had two
rows wrong too (`kill` via `pct exec`; name lookup via `pct list` only), and
says what the code does.

## Vendored crun 1.30.1

The pin was a fork commit on 1.24 carrying a revert of two `intelrdt` commits;
it is now upstream 1.30.1 plus the `.upstream_tag` marker the header script
reads, at [CageForge/crun](https://github.com/CageForge/crun). The revert was
not needed to build. The features ABI check passes against the new header
unchanged. How to do the next bump is written down in
`docs/DEVELOPMENT_WORKFLOW.md`.

## Upgrading from 0.12.0

- Plain binary and `.deb`: install and carry on.
- `-crun` binary: `libjson-c5` instead of `libyajl2` — see the top.
- A config naming `runc` or carrying `crun_name_patterns` keeps working with
  a warning; change it at your convenience.

## Still missing

`events`, a metrics stream — nothing has asked for it. The kubelet test on a
node (`tests/k8s/pod_on_node.sh`) is still run by hand.
