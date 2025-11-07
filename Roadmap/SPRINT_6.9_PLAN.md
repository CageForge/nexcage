# Sprint 6.9: OCI Spec 1.3.0 Upgrade

**Date**: 2025-11-03  
**Status**: 📋 PLANNING  
**Duration**: 1 week (targeted)

## 🎯 Sprint Goal

Elevate the project9s OCI runtime support to comply with the OCI Runtime Specification v1.3.0 while keeping existing backends stable.

## 🚀 Primary Deliverables

- Update vendored OCI specification definitions to v1.3.0.
- Extend ABI driver structures and validation logic to cover new runtime fields.
- Adjust documentation (README, docs/) to state OCI 1.3.0 compatibility.
- Provide migration notes for template authors referencing OCI fields.

## 🧩 Key Tasks

1. Inventory current OCI structures vs. 1.3.0 changes (hooks, annotations, process flags, platform constraints).
2. Update Zig type definitions and validation helpers for new/changed fields.
3. Regenerate or sync OCI JSON schemas used in tests (if applicable).
4. Extend unit/E2E coverage to assert 1.3.0 semantics.
5. Refresh documentation and release notes to advertise the upgraded spec level.

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

---

Prepared for execution ahead of OCI spec upgrade implementation.

