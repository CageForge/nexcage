# nexcage 0.10.0

**Kubernetes schedules pods onto nexcage.**

```
$ kubectl apply -f pod.yaml        # runtimeClassName: nexcage
$ kubectl get pod nexcage-pod
NAME          READY   STATUS    RESTARTS   AGE
nexcage-pod   1/1     Running   0          8s

$ kubectl logs nexcage-pod
HELLO_FROM_KUBERNETES
$ kubectl exec nexcage-pod -- /bin/echo EXEC_THROUGH_KUBECTL
EXEC_THROUGH_KUBECTL
```

At 0.9.1 nexcage was a command-line tool for LXC containers on one Proxmox VE
host, and nothing in Kubernetes could schedule onto it. It is now an OCI runtime
that podman, `ctr`, containerd's CRI, CRI-O and a kubelet all drive.

## What an engine needs from you

nexcage's default backend is still Proxmox LXC. A container engine's containers
go to the **crun** backend, and two things have to be true for that:

```bash
# 1. the binary has the backend compiled in
docker build --build-arg BUILD_FLAGS="-Denable-backend-crun=true -Dcpu=baseline" .

# 2. the configuration routes to it -- an engine never passes --runtime
cat > /etc/nexcage/config.json <<'JSON'
{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
JSON
```

A routing pattern is a regular expression **only** when it starts with `^` or
ends with `$`; everything else is a shell wildcard. `".*"` therefore matches
nothing, which is why the example file used to send every container to the
default backend without a word. Use `"*"`.

Then name the runtime wherever your engine names one:

```toml
# containerd
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage]
  runtime_type = "io.containerd.runc.v2"
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage.options]
    BinaryName = "/usr/local/bin/nexcage"

# CRI-O
[crio.runtime.runtimes.nexcage]
runtime_path = "/usr/local/bin/nexcage"
runtime_type = "oci"
```

A crun-enabled build links libyajl, libseccomp and libcap; a node needs
`libyajl2` installed, which Proxmox VE does not have by default.

## The command line

New in this release, and all of it is what an engine or a kubelet asks for:

| | |
|---|---|
| `create <id> --bundle <dir>` | with `--console-socket`, `--pid-file`, `--systemd-cgroup` |
| `state`, `start`, `kill`, `kill --all`, `delete --force` | on the crun backend, where `state` is libcrun's own output |
| `exec` | `nexcage exec <id> <cmd>`, and `exec --process <file>` — the shape an engine sends, `--detach` included |
| `ps` | `--format json` or a `PID` table; the host PIDs in the container's cgroup |
| `features` | the OCI features document, read from the libcrun this binary links |
| `--root`, `--log`, `--log-format json`, `--version` | the globals an engine puts before the command |

Flags are accepted in both spellings, `--root <dir>` and `--root=<dir>`,
because engines disagree: containerd sends the first, CRI-O sends both.

## Where the Proxmox LXC backend stops

`--console-socket`, `--pid-file`, `exec --process`, `exec --detach`, `ps` and
`features` are **refused** there, with an explanation, rather than accepted and
ignored. `pct create` starts no process, so there is no pty to hand over and no
pid to write; `pct exec` takes a command and returns when it ends; and
`pct exec <id> ps` reports the PIDs a container sees in its own namespace, which
is a different set of numbers for a different question. A flag that is accepted
and quietly does nothing is worse than one that is rejected.

## Fixed

Every one of these was found by running an engine, and not one was on the list
of what was thought to be missing:

- **The crun backend did not enter the bundle it was given.** An OCI spec names
  its rootfs relative to the bundle, and libcrun resolves that against the
  working directory — which is why crun and runc `chdir` first. containerd's
  shim serves a whole pod and runs the runtime from the *sandbox's* directory,
  so a pod's container looked for its rootfs inside the sandbox's and failed
  with `/bin/sh not found`. Sandboxes came up; their containers never did.
- **`--root=<dir>` was read as a command name**, so CRI-O could not make a
  single call.
- **An OCI bundle's `config.json` was read as nexcage's configuration.** It is
  first in the search path and an engine runs the runtime from the bundle, so
  the routing rules were silently replaced by a runtime spec. A file declaring
  `ociVersion` is skipped now.
- **A container engine's container id was rejected** by an RFC-1123 hostname
  rule that belongs to the Proxmox LXC backend, where the id becomes a hostname.
- **The crun backend did not build**, and had never been run at all.
- `--runtime` before the command was dropped; `kill --all` and `delete --force`
  were accepted and then not applied; the crun driver leaked its context
  strings and freed one of them with the wrong length.

## Upgrading from 0.9.1

Nothing in the Proxmox LXC command line changed, and no flag was removed. Two
changes can be noticed:

- If you keep a `config.json` in a directory you run nexcage from **and it
  declares `ociVersion`**, it is no longer read as configuration. That file is
  an OCI runtime spec, and reading it as configuration was the bug.
- `exec --process` and `exec --detach` now fail on the Proxmox LXC backend
  instead of being ignored.

Binaries are built with `-Dcpu=baseline`, as in 0.9.1, so they run on hosts
without AVX2.

## Still missing

- **One host.** Containers on other Proxmox VE nodes are not supported, and
  this is the largest functional limit.
- `pause`, `resume`, `update` and `events`: checkpointing, vertical resizing and
  a metrics stream. Nothing asked for any of them in a single run against
  podman, containerd, CRI-O or a kubelet.
- The kubelet test on a node (`tests/k8s/pod_on_node.sh`) is run by hand. Making
  it a CI check needs a crun-enabled build published as an artifact; today that
  build exists only inside a Docker image.
