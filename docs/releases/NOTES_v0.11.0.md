# nexcage 0.11.0

**A Proxmox VE cluster is more than one node, and nexcage now sees all of them.**

```
$ nexcage list
ID    IMAGE     COMMAND  CREATED   STATUS   BACKEND      NODE        NAMES
100   unknown   pct      unknown   running  proxmox-lxc  prox-home   web-1
200   unknown   pct      unknown   running  proxmox-lxc  titan       web-2

$ nexcage start web-2        # on titan, from here
```

`pct` only ever answers for the host it runs on. Until now that meant `list`
showed a fraction of what was there **without saying so**, and every other
command answered "not found" for a container on another node — the same answer it
gives for a name that does not exist anywhere.

## Read this if you parse `list`

`list` has a **`NODE` column between `BACKEND` and `NAMES`**. A script taking the
container name from the seventh tab-separated field wants the eighth now:

```bash
# before
nexcage list | awk -F'\t' '{print $7}'
# now
nexcage list | awk -F'\t' '{print $8}'
```

That is the only incompatibility in this release.

## What works across the cluster

`list`, `state`, `start`, `stop` and `delete` find a container wherever it lives.
A container on this host still goes through `pct`; one elsewhere goes through the
owning node's API.

`state` for a container on another node carries where it is:

```json
  "pid": 0,
  "annotations": { "io.cageforge.nexcage.node": "titan" }
```

**Three things stay local**, and are refused with the node's name rather than
answered wrongly:

| | why |
|---|---|
| `exec` | `pct exec` attaches on the host it runs on, and the API has no exec |
| `kill` | a signal goes to the container's init from the host; the API has no call for that — `stop` and `delete` do work from here |
| the `pid` in `state` | an init's PID belongs to its node's process table. Reporting it here would name whatever holds that number on this host |

## Creating on another node

```bash
nexcage create --name web-2 --node titan local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst
```

The template is checked **on that node, before a VMID is taken**. This is the
trap the check exists for: a storage called `local` is a *different directory on
every node* unless it is shared, so a volid that exists here may simply not be
there.

Three things `--node` refuses rather than half-does, each because something in
the path is local by construction: an OCI bundle (its rootfs is packed into a
template on this host's storage), a registry image (the pull lands here), and a
ZFS rootfs (the dataset would be created in this host's pool).

`--node` naming the host nexcage runs on is not "another node" — it takes the
ordinary local path.

## Templates

```bash
$ nexcage images
NODE        STORAGE      SHARED  SIZE   TEMPLATE
prox-home   local        no      129M   local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst
prox-home   shared-rdma  yes     31M    shared-rdma:vztmpl/redis_7.tar
titan       local        no      98M    local:vztmpl/alpine-3.22-default_20250617_amd64.tar.xz

$ nexcage pull docker.io/library/redis:7 --storage shared-rdma
shared-rdma:vztmpl/redis_7.tar
$ nexcage create --name r1 --node titan shared-rdma:vztmpl/redis_7.tar

$ nexcage rmi shared-rdma:vztmpl/redis_7.tar --node titan
shared-rdma:vztmpl/redis_7.tar removed from the shared storage; it is gone from every node
```

That middle pair is why `pull` exists on its own: `create` pulls too, but only
onto **this** host's `local` storage, which the other node cannot read. Pulling
onto a shared storage is what makes `create --node` usable.

A storage marked `SHARED` carries the same files on every node and is listed
once rather than once per node. `rmi` on such a storage removes the file for
every node at once, whichever node was named, and says so.

Two limits worth knowing before you plan around them:

- Pulling needs **Proxmox VE 9.1 or later** — `oci-registry-pull` does not exist
  before it, and nexcage says which version it needs rather than failing
  obscurely.
- That endpoint takes **no credentials**, so a private registry cannot be
  authenticated through it. This is a property of the Proxmox API, not something
  nexcage left out.

## Fixed

- `state` reported `"pid": 0` for a running container whenever the PID could not
  be read, which a caller cannot tell apart from a container that has none. It
  is an error now — except for a container on another node, where there is no
  PID on this host and the annotation says which node to ask.

## Nothing here touches the runtime side

containerd, CRI-O and a kubelet drive nexcage as an OCI runtime, and that is
unchanged from 0.10.0. For Kubernetes, more than one host was never a runtime
question: a kubelet runs on each node and calls the binary there, the way runc is
called. The same goes for images — containerd and CRI-O implement CRI's
`ImageService` themselves and hand the runtime a bundle whose rootfs is already
unpacked.

## Still missing

- **`pause`, `resume`, `update`, `events`.** Nothing has asked for any of them in
  a single run against podman, `ctr`, containerd, CRI-O or a kubelet.
- The kubelet test on a node (`tests/k8s/pod_on_node.sh`) is run by hand. Making
  it a CI check needs a crun-enabled build published as an artifact; today that
  build exists only inside a Docker image.
