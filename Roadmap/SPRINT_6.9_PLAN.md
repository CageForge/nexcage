# Sprint 6.9: Release 0.7.4 Dependency Refresh

**Date**: 2025-11-03  
**Status**: 📋 PLANNING  
**Duration**: 1 week (targeted)  
**Milestone**: Sprint 6.9 — Release 0.7.4 (Dependency Refresh)

## 🎯 Sprint Goal

Ship release `v0.7.4` with refreshed vendored dependencies (crun, Proxmox integration), OCI Runtime Specification v1.3.0 compatibility, and healthy build/test coverage.

## 🚀 Primary Deliverables

- Update vendored OCI specification definitions to v1.3.0.
- Refresh vendored `crun` sources and resolve systemd/seccomp linking for Debug builds.
- Track upstream Proxmox VE changes influencing dependency baselines.
- Adjust documentation (README, docs/) to state OCI 1.3.0 compatibility and the new release version.
- Provide migration notes for template authors referencing OCI fields.

## 🧩 Key Tasks

1. Inventory current OCI structures vs. 1.3.0 changes (hooks, annotations, process flags, platform constraints).
2. Update Zig type definitions and validation helpers for new/changed fields.
3. Regenerate or sync OCI JSON schemas used in tests (if applicable).
4. Update vendored `crun` and align build scripts with new headers and libraries.
5. Track Proxmox VE dependency bumps and validate compatibility.
6. Extend unit/E2E coverage to assert 1.3.0 semantics.
7. Refresh documentation and release notes to advertise the upgraded spec level.

## 🔍 Impact Assessment (OCI 1.3.0 vs 1.1.x)

- **config-linux.intelRdt** gains `enableMonitoring` and `schemata` requirements — audit `src/backends/crun/libcrun_ffi.zig` and ABI bindings for coverage.
- **config-linux.netDevices** introduces explicit device descriptors — our LXC adapter currently ignores this object; decide mapping or validation errors.
- **config-linux.memoryPolicy** adds `nodes` semantics — update resource parsing in `proxmox-lxc/oci_bundle.zig`.
- **config-linux.FileMode description fix** — confirm Zig types still align with schema (no change expected).
- **config-freebsd** newly specified — ensure we gate unsupported platform with clear errors.
- **Runtime hook behaviour** (`poststart` failure hard-stop) — verify CLI/ABI driver aligns with new requirement.
- **Feature reporting** additions — once schemas synced, update docs to state new flags support.

## 📈 Version Delta Breakdown (v1.0.2 → v1.3.0)

### v1.1.0 (Jul 2023)
- **Cgroup v2 parity**: new fields for idle, CFS burst, hugetlb reservations; ensure resource mapper covers `linux.resources` expansions.
- **Seccomp extensions**: `SCMP_ACT_KILL_PROCESS`, `SCMP_ACT_KILL_THREAD`, notify sockets, custom errno; review our seccomp pass-through for compatibility.
- **Intel RDT CMT/MBM** support: initial `intelRdt` object introduced.
- **Time namespace + scheduler + IO priority**: extend parsing structs to capture new blocks.
- **Domainname and ID mapping on mounts**: adjust bundle parsing and Proxmox translation.
- **Deprecations**: mark `memory.kernel`/`memory.kernelTCP` as discouraged, align validation messaging.
- **Feature manifest**: `features.json` formalised — incorporate into documentation of runtime capabilities.

### v1.2.0 (Feb 2024)
- **ID-mapped mounts**: `idmap`/`ridmap` options now spec’d; LXC backend must translate or reject gracefully.
- **Relative mount destinations** permitted — verify path normalization logic.
- **Annotation handling**: `org.opencontainers.image.*` explicitly included plus `potentiallyUnsafeConfigAnnotations`; update metadata pipeline and docs.

### v1.2.1 (Feb 2025)
- **CPU affinity**: Windows/Linux affinity descriptors added; ensure schema sync and decide backend support strategy (likely validation + warning for now).
- **Seccomp errno description fixes** and libseccomp 2.6 updates — verify generated bindings.

### v1.3.0 (Nov 2025)
- **Intel RDT monitoring enhancements** (`enableMonitoring`, `schemata`).
- **Linux `netDevices` inventory** object.
- **`memoryPolicy` clarification** impacting NUMA-aware scheduling.
- **FreeBSD platform spec**: confirm runtime gating.
- **Hook failure semantics** tightened (`poststart`).

### Summary Actions
- Synchronise `deps/crun/libocispec` schemas and regenerate Zig bindings if needed.
- Update our JSON parsing structs across `src/backends` to cover new objects/fields (with feature flags where unsupported).
- Document unsupported-but-validated fields to keep compliance honest while planning implementation.

## 📦 Dependencies & Risks

- Requires reviewing upstream OCI changelog for breaking differences since 1.1.0.
- Potential impact on crun ABI bindings if new fields map to libcrun structures.
- Need to confirm compatibility with existing Proxmox LXC workflows.

## ✅ Definition of Done

- All code paths that parse or emit OCI data align with spec v1.3.0.
- CI pipelines pass with updated fixtures/tests.
- Documentation and changelog explicitly state the new spec level.
- GitHub issue tracking this task is closed with review sign-off.

## 🕒 Session Log

- **2025-11-03** — Created sprint plan and opened GitHub Issue #145 for the OCI spec upgrade. Logged build verification via `make build`. _(30 min)_
- **2025-11-07** — Created GitHub milestone “Sprint 6.9 — Release 0.7.4 (Dependency Refresh)” and assigned issues #145, #141, #140, #139, #136. _(20 min)_
- **2025-11-07** — Reviewed OCI Runtime Spec v1.3.0 + interim releases (v1.1.0, v1.2.0, v1.2.1), documented deltas vs v1.0.2 in this plan. _(45 min)_

---

Prepared for execution ahead of OCI spec upgrade implementation.

