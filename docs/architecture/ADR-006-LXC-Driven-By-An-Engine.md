# ADR-006: The Proxmox LXC backend driven by a container engine

- Status: **Proposed** 2026-10-09. It needs the maintainer's answers to the questions under *For review*.
- Date: 2026-10-09
- Issue: [#316](https://github.com/CageForge/nexcage/issues/316)
- Builds on: [ADR-005](ADR-005-Isolation-Profiles.md), Isolation profiles

## Problem

ADR-005 lets an isolation profile name a backend. On crun that is done
(#315): one node runs pods under different profiles, checked from inside the
pods. #316 asks for the same with a profile that names **Proxmox LXC**. Its
done-when:

- a pod runs whose profile names LXC;
- the pod is Ready with a CNI address;
- `kubectl logs`, `kubectl exec` and delete work;
- its container is in `pct list` while it runs.

This ADR records what an engine requires of the runtime, and what Proxmox VE
and LXC can do. It then asks whether the result is worth what it costs.

## What the engine requires

These facts come from containerd **v2.1.9**'s runc shim
(`cmd/containerd-shim-runc-v2`) and go-runc v1.1.0, read in code. CRI-O's
conmon imposes the same shape. Paths are relative to the containerd tree.

| # | Requirement | Where |
|---|---|---|
| E1 | `create` exits 0 only once the container's process exists. Its pid is in `--pid-file` as bare decimal, and the runtime's fds 0/1/2 have been handed to that process. Those fds are the pipes behind `kubectl logs`. | `process/init.go:110-180`, `go-runc/io.go:143`, `go-runc/utils.go:28` |
| E2 | The shim learns that a process exited **only** by reaping it, as a child subreaper with `wait4(-1)`. The pid must be a host pid whose parents have all exited. A process started by someone else, systemd for instance, never produces an exit: Wait blocks, stop times out, and delete fails with "task must be stopped". | `pkg/shim/shim.go:243`, `pkg/sys/reaper/reaper_unix.go:254`, `task/service.go:654-657` |
| E3 | The CRI plugin joins a pod's app containers to `/proc/<sandbox pid>/ns/{net,ipc,uts,…}`. So the **sandbox's** pid has to be in the sandbox's namespaces. | `internal/cri/opts/spec_opts.go:322-383` |
| E4 | The shim reads `/proc/<pid>/cgroup` for stats and OOM events. | `runc/container.go:147,487` |
| E5 | The shim runs `exec` as `--process f --detach --pid-file p`. The exec'd process must end up as the shim's child, and the shim kills it with plain `kill(2)`. | `process/exec.go:154,176-240` |
| E6 | The CRI plugin creates and configures the pod's network namespace (CNI) **before** the sandbox exists. The bundle's rootfs is a snapshot the shim mounts at `<bundle>/rootfs`. | `sandbox_run.go:191-276`, `runc/container.go:74-122` |
| E7 | `state` is never called. A runtime's error reaches the kubelet as the last `level: error` line of `--log`. | `process/init.go:482` |

## What Proxmox VE and LXC do

pve-container 6.0.18 and lxc-pve 6.0.5 (Proxmox VE 9.1 GA) were read in code.
Behaviour was then **observed on the E2E node**, which runs Proxmox VE
**9.2.20** with pve-container 6.1.14, lxc-pve 7.0.0 and kernel 7.0.14. That was
a one-off probe in #379, run 37933452858; the P-numbers refer to it.

| # | Fact | Source |
|---|---|---|
| X1 | `pct start` runs `systemctl start pve-container@<vmid>`, whose `ExecStart` is `lxc-start -F` with stdout to `/dev/null`. That container's process is systemd's, which rules it out under E2, and its stdio can never be the shim's pipes, which rules it out under E1. | `pve-container@.service`, `PVE/LXC.pm vm_start` |
| X2 | `lxc-execute -n <vmid> -- argv`, run in the foreground by any process, starts the container. It **passes its stdio to the container's process** and **exits with the container's status**: 7 for `exit 7`, 143 for SIGTERM. `lxc-start -F` in the same position fails to set up ttys on such a container and exits 1 whatever happens. | P3, P4; `lxc_execute.c:229-237` |
| X3 | `lxc-execute --share-net /var/run/netns/<name>` (or `/proc/<pid>/ns/net`) puts the container into an existing network namespace. Proxmox drops `lxc.namespace.share.*` from a container's configuration, so it can only go on the command line. | P5; `confile_utils.c:898`, `Config.pm` allowlist |
| X4 | While `lxc-execute` runs, `pct status` says running and `pct list` lists the container. The process `lxc-execute` started is **LXC's monitor**: it stays in the host's namespaces, in cgroup `/lxc.monitor/<vmid>`. The container's processes are in `/lxc/<vmid>/ns`. | P6 |
| X5 | A host directory can be a container's rootfs (`rootfs: /path`, root only), and `pct destroy` leaves the directory as it was. But **`pct create` unpacks the template into that directory**: 528 MiB of Debian on the probe. | P1, P11 |
| X6 | `/var/lib/lxc/<vmid>/config`, which `lxc-execute` reads, is written by `PVE::LXC::update_lxc_config`, an internal perl function, not an API. It works without `pct start`. Timings on the probe: about **1.0 s** per call with perl's start-up, `pct config` 1.4 s, `pvesh get /cluster/nextid` 1.7 s. | P2, P12 |
| X7 | Proxmox gives a container `memory: 512` and `swap: 512` when none are set, and turns them into `memory.max` and `memory.swap.max`. | P1, P2 |
| X8 | `lxc-attach` passes the command's exit status through: 5 for `exit 5`. SIGTERM to the `lxc-attach` process, reached through `sudo`, ended it with 143 while **the attached process kept running** in the container. Not verified without `sudo`. The working directory inside is lxc-attach's own, so there is no `--cwd`. | P7, P7b; `attach.c:1580` |
| X9 | `pct stop` on a container that `lxc-execute` runs makes `lxc-execute` exit **1**. | P9 |
| X10 | `lxc.cgroup.dir.*` lines in a container's configuration are kept. Proxmox 9.2 warns: "lxc.cgroup.dir.monitor is deprecated, this will be a hard error in the future!" Where the container then lands was not observed. | P10 |
| X11 | A container's configuration lives in pmxcfs, `/etc/pve`: shared by the cluster, persistent, and read-only without quorum. `pct list` reads the cluster's VM list. | `PVE/LXC.pm:81-103`; Proxmox VE docs |

## What follows from it

1. **The sandbox cannot be a Proxmox container.**
   - The process that can satisfy E2 is the one `lxc-execute` starts, which is LXC's monitor. That process is in the host's namespaces (X4). E3 needs the sandbox's pid in the pod's namespaces.
   - So under an LXC profile the pod's sandbox (`pause`) runs on crun. Each app container is a Proxmox container that joins the sandbox's namespaces with `--share-net`, `--share-ipc` and `--share-uts` (X3).
   - The bundle says which kind it is: `io.kubernetes.cri.container-type`, or CRI-O's `io.kubernetes.cri-o.ContainerType`.
2. **An app container is started with runc's own pattern.**
   - `create` forks a process that holds the shim's fds and waits on a FIFO. It writes that process's pid to `--pid-file` and exits, so the shim inherits it (E1, E2).
   - `start` releases the FIFO, and the process execs `lxc-execute -n <vmid> --share-net … -- <process.args>`. The pid and the stdio stay the same. The container's exit status becomes that process's exit status (X2).
   - What the shim does **not** get:
     - E4 points at the monitor's cgroup, so `kubectl top` and OOM reporting for the pod are wrong.
     - A debug container that targets this one cannot join its pid namespace.
3. **The container must not be made with `pct create`,** which would unpack a template into the engine's snapshot (X5).
   - nexcage would write the configuration itself, with `rootfs: <bundle>/rootfs`, no `net0`, `console: 0`, `ostype: unmanaged`, through Proxmox's own `create_and_lock_config` and `write_config`. It then calls `update_lxc_config` (X6).
   - That is one perl process per create, about 1–2 s, against crun's tens of milliseconds. It also depends on functions Proxmox does not publish as an API.
4. **The container would be privileged.**
   - The snapshot's files belong to the host's uid 0, and a bind-mounted rootfs is not uid-shifted. Per-mount `idmap` arrived in pve-container 6.1.6, and the node has 6.1.14, but it was not tried here.
   - Until it is, `hostUsers: false` under an LXC profile is refused. That is the opposite of what ADR-005 sketched for LXC: "a pod in an unprivileged Proxmox container".
5. **ADR-005's `lxc` keys do not apply.**
   - `storage` and `rootfs_size_gb` have nothing to act on: the rootfs is the engine's snapshot.
   - `bridge` has nothing to act on either: the network is CNI's, through `--share-net`.
   - What remains are resources, which must be set explicitly: otherwise Proxmox imposes 512 MiB (X7). That leaves `unprivileged` once idmap is proven.
6. **`exec` needs more than `lxc-attach`** (X8).
   - The shim kills an exec'd process with `kill(2)` (E5), and the attached process survived that.
   - liblxc's `attach()` creates the process with `CLONE_PARENT`, which makes it the shim's own child. It also takes a working directory. Using it adds a C binding to liblxc.
7. **Lifecycle is not the engine's.**
   - A container's configuration outlives the engine's container. After a reboot or a lost shim, `/etc/pve` still holds configurations whose rootfs no longer exists, visible to the whole cluster. Something has to collect them.
   - Without quorum (X11) no LXC pod can start on that node. crun pods are unaffected.
   - An administrator's `pct stop` reaches the engine as exit 1 (X9). Their `pct start` runs the container with no shim at all.

## Failure modes

| Failure | Effect | Mitigation if built |
|---|---|---|
| A Proxmox upgrade changes `update_lxc_config` or `create_and_lock_config` | Every LXC pod fails to create | Pin to the tested pve-container versions, refuse others by name, keep the E2E on the node |
| Node reboot, shim crash | Orphaned configurations in `/etc/pve`, cluster-wide | Collect containers tagged by nexcage whose rootfs is gone, at every create and at boot |
| Quorum lost | No LXC pod starts on that node | None. This is pmxcfs by design. |
| Pod churn (Jobs, CronJobs) | A pmxcfs write and corosync traffic for every pod, across the cluster | Measure first; a rate the cluster cannot take means LXC profiles are wrong for that workload |
| A pod with no memory limit | Silently limited to 512 MiB | Map `linux.resources` explicitly; refuse what cannot be mapped |
| The cgroup is outside the kubelet's pod cgroup (X4, X10) | Pod-level limits, QoS and eviction do not see the container; `kubectl top` reports the monitor | `lxc.cgroup.dir.container` under the pod's cgroup, but Proxmox is deprecating that key (X10) |
| An administrator stops or starts the container | The engine sees exit 1, or a container runs with no shim | Tag the containers; document it; a hookscript that refuses `pct start` is possible |

## Alternatives

- **A. An engine-driven Proxmox container** (1–7 above).
  - It meets the done-when: Ready, CNI address, logs, exec, delete, `pct list`. The probe shows the mechanics hold (X2–X5).
  - Its costs are structural, not tuning: Proxmox internals, pmxcfs on the pod path, a privileged container, cgroup accounting outside the kubelet, and `exec` through a C binding.
  - Estimate: 6–8 pull requests, then the E2E work.
- **B. Proxmox-native.**
  - nexcage pulls the image through Proxmox, then `pct create` and `pct start`.
  - It fails E1 and E2: the process belongs to systemd and its stdout goes to `/dev/null` (X1). It also copies the image on every create.
  - Rejected.
- **C. LXC's isolation on crun.**
  - A crun profile can already require a user namespace and seccomp, and drop capabilities (#315).
  - Adding Proxmox's AppArmor profile (`lxc-container-default-cgns`) and its capability drops gives a pod LXC's protections without a Proxmox container.
  - It does not give `pct list`.
  - Cost: one or two PRs.
- **D. Keep `runtime: lxc` refused.** #371 already refuses it with "not there yet (#316)". #316 then moves past 1.0, with this ADR as its record.

## Proposal

**D now, plus C if LXC's protections are what is wanted. A only for a named need that only a Proxmox container meets.**

A works: the probe settled the hard questions in its favour. But each piece of value it adds comes with a structural cost. What a pod gains by being a Proxmox container is its place in `pct list` and Proxmox's UI. It does not gain the rest:

- not backup: vzdump cannot back up a rootfs that is the engine's snapshot;
- not the Proxmox firewall: the network namespace is CNI's;
- not HA or migration: the container is the engine's;
- not an unprivileged container: idmap is not proven.

Against that come these costs, all of them on the path of every pod:

- coupling to Proxmox's perl internals;
- pmxcfs and quorum;
- 1–2 s more per create;
- a privileged container;
- resource accounting the kubelet cannot see.

If the maintainer names the need, A is built in these steps, each with its own check on the E2E node:

1. Under an LXC profile, the sandbox goes to crun. Proof: the simulator, and a crun test with the annotation.
2. A Proxmox container's configuration is written by one perl helper, and its latency is measured.
3. The holding process plus `lxc-execute`. Proof: `crictl` on the node, covering logs, exit codes, the network namespace and `pct list`.
4. `exec` through liblxc's `attach()`, with the shim's `kill(2)` checked.
5. Orphans collected; resources mapped; 512 MiB never imposed.
6. A k3s pod under an LXC profile, which is #316's done-when.

## For review

1. **What must an LXC pod give that a crun pod with a profile does not?** Visibility in `pct list` and the UI only, or something more? The answer chooses between A and C/D.
2. If A: is a **privileged** container acceptable for the first version, with `hostUsers: false` refused? Or does A wait until an idmapped rootfs is proven on 9.2?
3. If A: is depending on Proxmox's **perl internals** (`update_lxc_config`, `create_and_lock_config`) acceptable, pinned to tested versions? The alternative is nexcage writing LXC's configuration itself, which bypasses Proxmox's generation (AppArmor, cgroups, hooks).
4. **0.17.0**: release it with profiles on crun and move #316 to a later milestone?

## Verification of this ADR

- **The engine's contract** was read in containerd v2.1.9 (commit 9260092); the paths are in the table above.
- **Proxmox and LXC** were read in pve-container 6.0.18 (963730e) and lxc-pve 6.0.5-3 (proxmox/lxc 8242e22). The Proxmox git server refused the proxy, so the GitHub mirrors were used.
- **The probe** ran on the E2E node: `.github/workflows/probe_lxc_engine.yml`, added and removed again in #379.
- **Not settled:**
  - where `lxc.cgroup.dir.container` lands the container (P10);
  - what `lxc-attach` does with SIGTERM without `sudo` in between (P7b);
  - lxc-attach's working directory (P7: the probe lost the output);
  - an idmapped bind rootfs on 9.2.
