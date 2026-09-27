# ADR-001: Container Runtime Selection

## Status

**Revised 2026-09-27.** This supersedes the decision of 2024-12-01, which chose
crun as the primary container runtime with runc as an automatic fallback. That
decision was never what shipped; the review that produced this revision is
[#85](https://github.com/CageForge/nexcage/issues/85).

## Context

nexcage is one binary on a Proxmox VE host, called from two directions
([OVERVIEW.md](OVERVIEW.md)): a person or a script manages LXC containers with
it, and a container engine — podman, containerd, CRI-O, a kubelet — drives it
with the OCI runtime-spec command line. The 2024 decision was taken before the
first of those existed as the centre of the project, and it assumed nexcage
would *call* a runtime binary. Two questions need an answer that the code
agrees with: which backend a container goes to by default, and how that is
decided for a container whose caller never says.

## Decision

1. **The Proxmox LXC backend is the default.** It turns commands into `pct`
   and Proxmox API calls, across every node of the cluster, and is what a
   plain build contains. Nothing selects it; everything not routed elsewhere
   lands there.

2. **The crun backend is libcrun, linked in.** For an OCI bundle — what an
   engine hands over — nexcage does the container work through the vendored
   libcrun (`deps/crun`, a fork), not by executing a `crun` binary. It is an
   opt-in build (`-Denable-backend-crun=true`) and ships as the `-crun`
   release binary. It is the backend an engine's host is configured for.

3. **Routing is a name lookup, in the configuration, first match wins.**
   `runtime.routing` is a list of `{ "pattern", "runtime" }`; a pattern is a
   glob unless it starts with `^` or ends with `$`, in which case it is a
   regular expression. `*` is the catch-all. `--runtime` overrides it for one
   command. An engine never passes `--runtime`, so a host that runs
   containers for one is configured with a single rule:

   ```json
   { "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
   ```

   `container_config.routing` and `container_config.default_runtime` are also
   read, for older files; when both lists are present the `container_config`
   one replaces the other wholesale. `container_config.crun_name_patterns`, a
   glob list routing to crun that predates `routing`, is **removed** in this
   revision: a glob under `routing` is the same matcher, so each entry had a
   one-line equivalent. A file that still carries it gets a warning naming
   the replacement.

4. **There is no fallback between backends.** The 2024 design had
   `auto_fallback_enabled`: try the primary, use the other if it is
   unavailable. A container is one thing on one backend — an LXC container
   and a libcrun container are not interchangeable — so a command routed to a
   backend that is compiled out fails with `UnsupportedOperation` and says
   how to build it, rather than quietly making a different kind of
   container.

5. **runc is not a supported backend.** `src/backends/runc` shells out to a
   `runc` binary for create/start/kill/delete; no workflow builds it and it
   has never been run. A second OCI backend would implement the same
   interface libcrun already answers. Its removal is
   [#88](https://github.com/CageForge/nexcage/issues/88).

## Consequences

Positive:

- One code path per face, each verified where it is used: the LXC backend by
  the Proxmox E2E job on a real PVE 9.2 host; the crun backend by podman,
  `ctr`, containerd's CRI, CRI-O and a kubelet, with a Kubernetes pod
  scheduled onto it through a `RuntimeClass`
  ([KUBERNETES_INTEGRATION.md](../KUBERNETES_INTEGRATION.md)).
- Routing is one function (`Config.getRoutedRuntime`) with one source of
  rules, and the simulator proves both directions of a rule.

Negative:

- Linking libcrun couples nexcage to its ABI. The fork's `features` structs
  differ from upstream's by a trailing field, which segfaulted `features`
  once; `scripts/check_features_abi.sh` now compares the vendored header
  against the Zig mirror in CI. A crun bump is a deliberate change, not a
  version number ([#227](https://github.com/CageForge/nexcage/issues/227)).
- The `-crun` binary needs `libyajl2`, `libseccomp2` and `libcap2` on the
  host, and a Proxmox VE install lacks the first.

## What changed since 2024-12-01, and why

| Then | Now | Why |
|---|---|---|
| crun primary, runc fallback | Proxmox LXC default; crun for engines; runc unsupported | nexcage became a Proxmox-first runtime; the OCI half is driven by engines, and libcrun answers them |
| call the `crun` binary | link libcrun | one process, libcrun's own errors, no PATH dependence |
| automatic fallback | none | a container is one thing on one backend |
| `crun_name_patterns` | `runtime.routing` | one matcher, one list |

## References

- [OVERVIEW.md](OVERVIEW.md), [BACKENDS.md](BACKENDS.md)
- [KUBERNETES_INTEGRATION.md](../KUBERNETES_INTEGRATION.md) — what each engine asks a runtime
- README, *Configure* — the routing table as a user sees it
- [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)
- [crun](https://github.com/containers/crun) and the vendored fork, `deps/crun`
- [#85](https://github.com/CageForge/nexcage/issues/85), [#88](https://github.com/CageForge/nexcage/issues/88), [#227](https://github.com/CageForge/nexcage/issues/227)

---
**Last updated**: 2026-09-27 (revision); original 2024-12-01
