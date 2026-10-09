# nexcage 0.16.0

The OCI runtime is measured by the suites that define it, a Kubernetes node on
Proxmox VE is installed from what a release ships, and a private registry needs
one `skopeo login` per node.

Nothing a script or an engine sends is read differently. Upgrading is
installing.

## Conformance, on record

The first three run in `crun_build.yml` on every push and pull request to
`main`, against the `-crun` build routed to crun. runtime-tools and critest
run again against crun itself, for reference. A failure not on a suite's
known-failures list turns CI red, and so does a listed one that passes.

| Suite | Result | Where it is written down |
|---|---|---|
| runtime-spec validation ([runtime-tools], runtime-spec 1.3.0) | **33 of 58 pass.** Each of the 25 that fail also fails with crun 1.30.1 run directly: the suite cannot read cgroup v2, cgroup v1 settings libcrun refuses by name, and tests that contradict runtime-spec 1.3.0 or themselves | [RUNTIME_SPEC_VALIDATION.md](https://github.com/CageForge/nexcage/blob/v0.16.0/docs/RUNTIME_SPEC_VALIDATION.md), `tests/runtime-tools/known-failures` (#310) |
| critest ([cri-tools] v1.37.0, containerd with nexcage as the handler) | **110 of 142 pass, 10 fail, 22 skipped**, spec for spec what crun gets. The 10: AppArmor specs that need `apparmor_parser` in the image, and pod metrics, which containerd reads from a cgroup parent critest does not set under cgroupfs | [KUBERNETES_INTEGRATION.md](https://github.com/CageForge/nexcage/blob/v0.16.0/docs/KUBERNETES_INTEGRATION.md), `tests/cri/critest-known-failures` (#311) |
| `update`'s flags against the cgroup | `--memory`, `--memory-reservation`, `--memory-swap`, `--pids-limit`, `--cpu-quota`/`--cpu-period`, `--cpuset-cpus` and `--cpu-share` read back from the container's cgroup v2 files; `--kernel-memory` refused | `tests/crun/update.sh` (#359) |
| A pod through k3s | Ready, `kubectl logs`, `kubectl exec` and a delete, on the E2E node, from the `-crun` binary built from the commit | `k8s_e2e.yml`, on release tags, on demand, and on a pull request that changes the test (#312) |

critest's first run found a defect the engines had not: **containerd could not
stop a pod whose container had just exited** (#361). With `--log <file>`, which
every engine passes, nexcage wrote libcrun's reason to the file only.
containerd's shim reads "no such process" from the command's output to know a
`kill` came too late. It got `operation failed` instead, and StopPodSandbox
failed with it. An error now goes to stderr as well, as runc and crun print
theirs.

## A Kubernetes node on Proxmox VE

`docs/INSTALL.md` has the steps in order. The files they install are in the
release's tag:

| File | What it is |
|---|---|
| `packaging/config/config.oci.example.json` | The routing that sends every container an engine asks for to crun |
| `deploy/kubernetes/node/k3s-config-v3.toml.tmpl` | nexcage as a runtime of k3s |
| `deploy/kubernetes/node/containerd.toml` | The same for containerd 2.x |
| `deploy/kubernetes/node/crio.conf` | The same for CRI-O |
| `deploy/kubernetes/node/runtimeclass.yaml` | The `RuntimeClass` a pod names |

They are examples, and nothing enables them for you. A pod runs on nexcage
only when it names the class; the node's default runtime is unchanged.
`tests/k8s/pod_on_node.sh` installs these same files, so `k8s_e2e.yml` checks
what an administrator is told to install. The `-crun` build stays a bare
binary. A package for it belongs to the APT repository (#319).

## Images from a private registry

Proxmox's pull takes no credentials, but it runs `skopeo copy` as root, and
skopeo reads root's auth file on the node that pulls. On the E2E node that was
checked through `pvesh`, and through `pvesh` with the environment emptied as
`pvedaemon`'s is, which is how a pull with `--node` runs on the other node.
The API path itself was not run. So:

```bash
skopeo login --authfile /root/.config/containers/auth.json registry.example.com
```

on each node that pulls. With `--node titan`, that is titan. Give
`--authfile`: skopeo's default for root is under `/run`, which a reboot
empties. The file holds the credentials encoded, not encrypted, so use a token
that can only read.

The same check found that **`pvesh` exits 0 when its pull task fails**.
nexcage reported every such failure as "reported success but … holds no new
template". It now gives skopeo's reason. When the registry refused a login, it
also gives the `skopeo login` line for the node that pulls:

```
$ nexcage pull ghcr.io/acme/private:1
[1791499398] ERROR nexcage: pulling ghcr.io/acme/private:1 into local on pve1 failed: initializing source docker://ghcr.io/acme/private:1: unable to retrieve auth token: invalid username/password: unauthorized: incorrect username or password
[1791499398] ERROR nexcage: for a registry that needs a login, run as root on pve1: skopeo login --authfile /root/.config/containers/auth.json ghcr.io (docs/INSTALL.md)
nexcage: pull: operation failed
```

The Proxmox E2E puts wrong credentials for docker.io in that file on every run
and requires the pull to be refused with that reason and that line. That
proves the file is read without a secret in CI. A pull from a real private
registry has not been run in CI. It needs a registry and a credential owned by
the project.

## Security

**The self-hosted jobs no longer run a pull request from a fork** (#362).
`proxmox_e2e.yml` and `buildagent.yml` ran any pull request's code, and on the
E2E node the runner user has sudo for everything. A fork's pull request now
skips them. `k8s_e2e.yml` was written that way from the start.

## Not in this release

**`events`.** The 0.16.0 plan took it only once an engine sends it. None has:
podman, `ctr`, containerd's CRI, CRI-O, critest and a kubelet ran without
asking for it.

## Upgrading from 0.15.0

- Install and carry on.
- A pull that fails now says why. If you parsed "holds no new template" out
  of stderr, the message is skopeo's reason now.

[runtime-tools]: https://github.com/opencontainers/runtime-tools
[cri-tools]: https://github.com/kubernetes-sigs/cri-tools
