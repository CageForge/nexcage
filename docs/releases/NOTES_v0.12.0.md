# nexcage 0.12.0

**If you run nexcage on a Proxmox cluster, upgrade.** Cluster support shipped in
0.11.0 and never worked on a real host: the query it makes was rejected by the
Proxmox API on every call. 0.11.0, 0.11.1 and 0.11.2 all carry the defect.

Also new: `pause` and `resume`.

## The cluster lookup asked for something that does not exist

```
$ nexcage start web-2          # web-2 is on titan
ERROR container 'web-2' not found
```

Under that answer, on every 0.11.x:

```
$ pvesh get /cluster/resources --type lxc
400 Parameter verification failed.
type: value 'lxc' does not have a value in the enumeration 'vm, storage, node, sdn'
```

The API has no `lxc` resource type. Containers come back under `vm`, carrying
their own `type` field:

```json
[ { "vmid": 200, "type": "lxc", "node": "titan", "status": "running" },
  { "vmid": 300, "type": "qemu", "node": "titan", "status": "running" } ]
```

So the cluster query failed every time and nexcage fell back to `pct list`,
which is correct for a container on this host and answers "not found" for one
anywhere else — the exact thing cluster support was added for. `list` showed
only local containers, `start`/`stop`/`delete`/`state` on a container elsewhere
said it did not exist, and `--node` on `images`/`rmi` had no cluster to check
against.

**The simulator's fake `pvesh` accepted `--type lxc`**, so 208 checks agreed
with the mistake. It now refuses it with Proxmox's own message, which is how the
fix is tested rather than merely asserted.

## Two more things a real cluster showed

**`/cluster/resources` is a cache.** `pvestatd` refreshes it every few seconds,
so this failed:

```bash
nexcage create --name c1 local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst
nexcage start c1        # ERROR container 'c1' not found
```

The container existed; the cache had not caught up. A miss in the cluster now
means "keep looking on this host", and only both sources coming up empty is a
container that does not exist.

**And the cache was preferred over `pct`.** For a container on this host the
cached status overrode the live one, so `state` reported `stopped` for several
seconds after a successful `start` — while `list` said `running`, from the same
binary. For a container here `pct` is the current answer now; the cluster keeps
the one thing only it knows, which node a container elsewhere is on.

All three are in code that 0.11.0, 0.11.1 and 0.11.2 shipped.

## pause and resume

```
$ nexcage pause web-1
$ nexcage state web-1 | jq -r .status
paused
$ nexcage resume web-1
```

The cgroup freezer: every process in the container stops where it is and stays
in memory. On the crun backend through libcrun; on Proxmox LXC by writing
`/sys/fs/cgroup/lxc/<vmid>/cgroup.freeze` directly.

`state` reads the freezer itself, because **`pct status` cannot answer this** —
it keeps saying `running`, as Proxmox has no notion of a frozen container. That
is worth knowing if you pause one and then look for it with Proxmox's own tools.

This is deliberately **not** `pct suspend`. That runs `lxc-checkpoint -s`, which
dumps the processes through CRIU and takes the container down — a different
operation, and on the Proxmox VE 9.2 host this was measured on it simply failed.
The freezer is what the OCI runtime-spec describes, and nexcage never calls
`pct suspend`.

`list` says `paused` for the same container. It read `pct`'s answer only while
this was being written, so the same binary called one container `running` and
`paused` depending on which command you asked — the same fault as the stale
status above, and caught the same way.

Pausing a container on another node is refused, naming it: the cgroup filesystem
there is not this host's to write.

The E2E suite runs all of this on a real Proxmox host, and takes the kernel's
word rather than its own: `cgroup.events` has to say `frozen 1`, not just
`cgroup.freeze` holding what nexcage wrote, and a command sent into the
container while it is frozen has to be held there — and to run once it is
thawed. Every defect fixed in this release was in code the
simulator's fakes were perfectly happy with.

## Upgrading from 0.11.x

Install and carry on — no configuration or command-line changes. A container
that was running stays running.

One behaviour change to be aware of if you script against it: `state` for a
container on this host now reports what `pct` says at that moment rather than
what the cluster cache last recorded. If something in your scripts was
accidentally relying on the stale answer, it will now see the current one.

## Still missing

- **`update` and `events`.** `update` is next: libcrun exposes it, and the LXC
  side maps onto `pct set`. Nothing has asked for `events` in a single run
  against podman, `ctr`, containerd, CRI-O or a kubelet.
- The kubelet test on a node (`tests/k8s/pod_on_node.sh`) is still run by hand.
  Making it a CI check needs the crun build as a *workflow* artifact; a release
  carries it as an asset since 0.11.2, which is not the same thing.
