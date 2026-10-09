# ADR-005: Isolation profiles

- Status: **Accepted** 2026-10-09 — the maintainer's answers are under *Decided on review*
- Date: 2026-10-09
- Issue: [#314](https://github.com/CageForge/nexcage/issues/314); implementation in
  [#315](https://github.com/CageForge/nexcage/issues/315) (crun) and
  [#316](https://github.com/CageForge/nexcage/issues/316) (Proxmox LXC driven by an engine)

## Problem

A container engine addresses a container by a 64-character hex id and never
passes `--runtime`. The only routing rule a host that serves an engine can
usefully write is `"*"`, so today **one node is one backend with one set of
parameters**: every pod on nexcage is a libcrun container with exactly what the
engine put in its bundle.

What a Kubernetes user should get from nexcage that crun does not give is a
choice, per pod, among isolation settings the node's administrator defined: a
pod on crun with the engine's own settings next to a pod on crun in a user
namespace with capabilities dropped, next to (#316) a pod in an unprivileged
Proxmox container on a chosen storage and bridge. That named choice is an
**isolation profile**.

This decision is made before 1.0 because 1.0 freezes the configuration it
changes ([#317](https://github.com/CageForge/nexcage/issues/317)).

## Constraints

What an engine can vary per runtime handler, read in the engines' source:

| Engine | Per handler | What reaches the runtime binary |
|---|---|---|
| containerd 2.1 (`io.containerd.runc.v2`) | `BinaryName`, `Root`, `SystemdCgroup`, …, and `pod_annotations` / `container_annotations` allowlists | go-runc runs `exec.CommandContext(ctx, BinaryName, args...)` (`command_linux.go`), so **argv[0] is `BinaryName`**. The shim's options have no field for extra arguments or environment (`api/types/runc/options/oci.proto`). The CRI plugin writes `io.kubernetes.cri.*` annotations (sandbox id, name, namespace, uid, container name, image) into every bundle, but **not the handler's name** (`internal/cri/annotations`); pod annotations reach the bundle only through the handler's allowlists |
| CRI-O 1.33 | `runtime_path`, `runtime_root`, `allowed_annotations`, `monitor_env`, … | conmon builds the runtime's argv with `runtime_path` as argv[0] (`runtime_args.c`) and `execv`s it; CRI-O's own calls (`features`, `--version`) run `runtime_path` as well. CRI-O writes `io.kubernetes.cri-o.RuntimeHandler` into the **sandbox** bundle only (`server/sandbox_run_linux.go`) |
| podman | `--runtime <path>` | the path, as argv[0] |

Everything an engine sends to nexcage on later commands — `start`, `state`,
`kill`, `delete`, `exec`, `ps`, `update` — is the id and global flags; the
bundle is read only at `create`.

From nexcage itself ([#371](https://github.com/CageForge/nexcage/issues/371),
[#372](https://github.com/CageForge/nexcage/issues/372)):

- Nothing records which backend a container is on; every command derives it
  again from routing.
- The configuration file does not fail closed: an unknown runtime name routes to
  LXC, unknown keys are ignored.
- On crun, nexcage never reads or changes the bundle: libcrun loads
  `config.json` from the file.

## Assumptions

Each is checked by the verification below, not taken on trust.

1. argv[0] arrives as configured on every engine call. True in containerd's and
   CRI-O's source; a wrapper script that `exec`s nexcage without `exec -a`
   loses it (see failure modes).
2. libcrun reports a container's annotations in `state` from the config it
   stored at create. True in libcrun 1.30.1 (`libcrun_container_state` reads
   the config from the state directory and prints its `annotations`).
3. libcrun can be given an edited spec: `libcrun_container_load_from_memory` is
   public API in the vendored libcrun.
4. A Kubernetes pod's sandbox and its containers all go to the pod's handler,
   so a profile chosen by handler applies to the whole pod.

## Decision

### 1. What a profile holds

A profile is a **name, one backend, and that backend's parameters**, defined in
the configuration file on the node. Nothing in a bundle defines or changes one.

```json
{
  "profiles": {
    "hardened": {
      "runtime": "crun",
      "crun": {
        "user_namespace": "require",
        "seccomp": "require",
        "capabilities": { "drop": ["CAP_NET_RAW", "CAP_SYS_CHROOT", "CAP_MKNOD"] },
        "limits": { "memory": "2G", "pids": 512 }
      }
    },
    "pve-small": {
      "runtime": "lxc",
      "lxc": { "storage": "local-zfs", "rootfs_size_gb": 8, "bridge": "vmbr1", "unprivileged": true }
    }
  }
}
```

- **The name** is a DNS label (`[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?`), so it
  can be a `RuntimeClass` handler's name as it is.
- **`runtime`** is `crun` or `lxc`, as in a routing rule.
- **`crun` parameters** start with what #315's acceptance test checks, and
  nothing more:

  | Parameter | Effect |
  |---|---|
  | `user_namespace: "require"` | A bundle without a user namespace and uid/gid mappings is refused. Nothing is added: a user namespace changes who owns the root filesystem, which is the engine's to arrange (Kubernetes `hostUsers: false`) |
  | `seccomp: "require"` | A bundle without `linux.seccomp` is refused. The message names the fix (`securityContext.seccompProfile.type: RuntimeDefault`) |
  | `capabilities.drop` | Removed from every capability set of the container's process. A later `exec --process` gets no capability the container's own process was denied: nexcage takes that from the config libcrun stored at create, not from the profile, which only `create` reads (decision 3) |
  | `limits.memory`, `limits.pids` | The bundle's limit, or the profile's when the bundle has none or a larger one |

  `no_new_privileges`, AppArmor, read-only root and the rest can follow when
  someone asks for them, under the same rule (decision 4).
- **`lxc` parameters** are the keys the `proxmox` and `network` sections take
  today (`storage`, `rootfs_size_gb`, `unprivileged`, `ostype`, `bridge`), with
  the same meaning, so a profile is a named override of those sections. #316
  decides what more an engine-driven LXC container needs.
- The `profiles` section is read **strictly**: an unknown key, backend or
  parameter, a value of the wrong type, or a name that is not a DNS label makes
  nexcage refuse the whole file (exit 1, as for a file that is not JSON,
  naming the key). A misspelt parameter must not silently weaken isolation
  (#371).

### 2. How an engine names a profile: by the program name

A profile is named by **argv[0]**: nexcage run as `nexcage@<profile>` — a
symbolic or hard link to the same binary — uses that profile. The node's
administrator makes one link per profile and points the handler at it:

```toml
# containerd 2.x
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-hardened]
  runtime_type = 'io.containerd.runc.v2'
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.nexcage-hardened.options]
    BinaryName = '/usr/local/bin/nexcage@hardened'
```

```toml
# CRI-O
[crio.runtime.runtimes.nexcage-hardened]
runtime_path = "/usr/local/bin/nexcage@hardened"
runtime_type = "oci"
```

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: { name: nexcage-hardened }
handler: nexcage-hardened
```

A pod with `runtimeClassName: nexcage-hardened` then runs under `hardened`.

- `--profile <name>` names a profile for one command, for a person or a script.
  When both are given and disagree, the command exits 2.
- **`@`, not `-`.** crun does the same with `crun-<handler>`, but nexcage's
  release files are called `nexcage-0.16.0-amd64-crun`, and a binary run under
  that name must not be read as a profile called `0.16.0-amd64-crun`. A program
  name with no `@` names no profile.
- **A profile that is named but not configured is an error** (exit 2, naming it
  and the profiles the file has), never a fallback to the plain handler: that
  fallback would be weaker isolation without a word.
- **The bundle cannot name or change a profile.** `io.cageforge.nexcage.profile`
  is reserved for nexcage to write (decision 5); a bundle that arrives carrying
  it is refused, as libcrun refuses a `run.oci.handler` annotation that tries to
  override the handler it was started with.
- **A program name with no profile** is today's behaviour: routing decides.

### 3. What becomes of `runtime.routing`

Routing stays as it is, **next to** profiles, and decides only at `create`:

1. a profile, from `--profile` or the program name;
2. else `--runtime`;
3. else the first matching routing rule;
4. else LXC.

`--runtime` together with a profile whose backend differs exits 2.

**After `create`, the container decides, not the configuration (#372).** Every
other command goes to the backend that has the container: libcrun's state
directory for the id first (a `stat`), then the Proxmox cluster. Neither the
profile nor routing is consulted. A profile renamed, edited or removed, or a
rule changed, while containers run can then never send `kill` or `delete` to
the wrong backend or block them with "unknown profile".

A routing rule that names a profile instead of a runtime would let a person's
container names choose profiles too. Nobody has asked for it, so it is not part
of this decision; the shape leaves room for it.

### 4. A profile only narrows

A profile may **narrow** what the engine's bundle grants and may **never widen
it**:

- It may drop capabilities, lower limits, and refuse a bundle that lacks a user
  namespace or a seccomp filter.
- It may not add a capability, add a device or a host namespace, make a
  container privileged, or relax seccomp or AppArmor.

What cannot be narrowed by editing the bundle is a **requirement**: the bundle
is refused, and the message says what it lacked.

The engine's bundle is what the cluster's policy produced — PodSecurity
admission, the pod's `securityContext`, the kubelet's defaults. A profile that
could widen it would let whoever may pick a `RuntimeClass` step around that
policy. A profile that only narrows gives at least the bundle's isolation and
never less, so which pods may use which class stays the cluster's decision
(admission policy), and picking any class is never an escalation.

On LXC "narrow" has a different object: an engine-driven LXC container's
parameters come from the profile, not the bundle (#316). The same rule holds
for what the bundle asks: it may not get more than the profile allows.

### 5. How `state` reports the profile

`state` carries the annotation **`io.cageforge.nexcage.profile: <name>`** on
both backends; a container made without a profile has none.

- **crun**: nexcage loads the bundle's spec, applies the profile, adds the
  annotation, and hands the result to libcrun with
  `libcrun_container_load_from_memory`. libcrun stores that config in its state
  directory and prints its annotations in `state` (assumption 2). That state
  directory is also the record decision 3 looks for; nexcage writes nothing
  else.
- **LXC**: the annotation goes into the `state.json` nexcage already writes,
  next to `io.cageforge.nexcage.node`.

The name records what was applied at `create`. If the profile's parameters are
edited later, running containers keep what they were made with.

## Failure modes

| What goes wrong | What happens | Why that is acceptable |
|---|---|---|
| The `nexcage@<profile>` link is missing, or the handler's path is misspelt | The engine fails the pod with "no such file" | Visible at the first pod |
| A profile is named that the file does not define | `create` exits 2, naming it and listing the defined ones | No fallback to weaker isolation |
| A misspelt key or parameter in `profiles` | The whole file is refused | Strict reading, decision 1 |
| **A wrapper script `exec`s nexcage without `exec -a "$0"`** | The program name is lost; the container is made **without the profile**, by routing | Cannot be detected by nexcage. Documented next to the engine configuration, and the tests' trace wrappers use `exec -a`. A wrapper can pass `--profile` instead |
| The bundle lacks what a requirement asks (no user namespace, no seccomp) | `create` fails; the pod stays in `ContainerCreating` with the reason in `kubectl describe` | The reason names the `securityContext` field that fixes it |
| A requirement breaks the pod's sandbox (pause) container | The pod never starts | Assumption 4: #315's test runs a whole pod, sandbox included, under `hardened` |
| A bundle carries `io.cageforge.nexcage.profile` | Refused | Otherwise `state` could report a profile that was not applied |
| A profile's parameters are edited while its containers run | Running containers keep the old parameters; `state` shows the same name | The name means "as defined at create"; documented |
| A profile is removed while its containers run | `kill`, `delete` and `state` still work | Decision 3: only `create` reads profiles |
| A pod author picks a class the cluster did not mean them to | The pod gets that class's profile | Never more than its bundle grants (decision 4); which pods may use which class is admission policy, outside nexcage |

## Alternatives

| Alternative | Why not |
|---|---|
| **An annotation selects the profile** (`pod_annotations` in containerd, `allowed_annotations` in CRI-O) | The value comes from the pod's author, not the node; containerd puts no handler identity in the bundle, so the annotation would be the only signal. It needs an allowlist per handler in each engine's configuration, reaches only `create`, and CRI-O and containerd pass annotations differently. What it would add — a different profile per container in one pod — nobody has asked for |
| **A wrapper script per handler** (`exec nexcage --profile x "$@"`) | Works, and is the fallback for an engine that cannot use a path with `@`. As the default it adds a second executable to keep and secure, and a shell on every runtime call, to do what the program name does |
| **`Root` / `runtime_root` per handler mapped to a profile** | Couples a state location to a policy; a mistake in one silently changes the other |
| **An environment variable per handler** | containerd cannot set one per runtime handler |
| **Profiles replace routing** | Breaks every configuration that routes by name today, including the shipped examples, for no gain to engines, which only ever use `*` |
| **Profiles that may also widen** (add capabilities, privileged) | Turns the choice of a `RuntimeClass` into a way around the cluster's policy (decision 4) |
| **A default profile applied when none is named** | Implicit: the same binary would behave differently depending on a key elsewhere in the file. The plain program name keeps today's behaviour |

## Consequences

Positive:

- One node can run pods under several isolation settings the administrator
  defined, chosen by `RuntimeClass`, with no change to Kubernetes or the
  engines.
- Choosing a class can never escalate (decision 4), and naming a profile that
  is not there fails rather than downgrades (decision 2).
- A container's backend no longer depends on today's configuration (#372).
- `state` says which profile a container was made with.

Negative and costs:

- An install step: one link per profile, and one engine runtime entry per
  profile. `docs/INSTALL.md` and `deploy/kubernetes/node/` get both.
- nexcage reads and edits the bundle's spec on crun for the first time. That
  is new code on the path every engine container takes; it runs only when a
  profile is named.
- The program name is a convention an intermediary can break (the wrapper
  failure mode).
- The configuration file gets stricter: from 0.17.0 an unknown key anywhere in
  it is an error (#371). A file that carried a misspelt or obsolete key and
  loaded until now stops loading, and says which key.

## Verification

- **#315** — two `RuntimeClass`es on one k3s node, `nexcage` and
  `nexcage-hardened`, one pod each. From inside each container: compare
  - `/proc/self/uid_map` (identity versus a mapping);
  - `Seccomp:` and `CapBnd:` in `/proc/self/status`;
  - the cgroup's `memory.max` and `pids.max`.

  The hardened pod also runs its sandbox under the profile (assumption 4), and
  a pod without `seccompProfile` is refused with the documented reason.
- **Simulator**:
  - `nexcage@hardened`, `nexcage` and `nexcage-0.16.0-amd64-crun` as program
    names: only the first names a profile;
  - an undefined profile exits 2;
  - a bundle carrying the reserved annotation is refused;
  - `--runtime` against a profile's backend exits 2;
  - a container created under one routing is stopped and deleted after the
    routing changes (#372);
  - misspelt `profiles` keys are refused (#371).
- **CRI-O**: the source says conmon passes `runtime_path` as argv[0]. The CRI-O
  path is tested in #315 if the CI image can run CRI-O; otherwise that remains
  the one engine path proved only by reading its source, and the docs say so.

## Decided on review

1. **The program-name form is `nexcage@<profile>`.**
2. **`seccomp: "require"` refuses** a bundle without a filter. nexcage does not
   apply a filter of its own.
3. **An unknown key anywhere in the configuration file is an error from
   0.17.0**, with no release of warnings first (#371).

## Links

- [ADR-001](ADR-001-Container-Runtime-Selection.md) — routing, and "a container
  is one thing on one backend"
- [#314](https://github.com/CageForge/nexcage/issues/314),
  [#315](https://github.com/CageForge/nexcage/issues/315),
  [#316](https://github.com/CageForge/nexcage/issues/316),
  [#317](https://github.com/CageForge/nexcage/issues/317),
  [#371](https://github.com/CageForge/nexcage/issues/371),
  [#372](https://github.com/CageForge/nexcage/issues/372)
- crun's `fill_handler_from_argv0` and `libcrun_configure_handler` — the same
  choice made by program name, with a bundle annotation refused when it would
  override it
- containerd 2.1.4 `internal/cri/annotations`, `api/types/runc/options/oci.proto`,
  go-runc 1.1.0 `command_linux.go`; CRI-O 1.33.0
  `server/sandbox_run_linux.go`, conmon 2.1.13 `src/runtime_args.c`
