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

---

Prepared for execution ahead of OCI spec upgrade implementation.

