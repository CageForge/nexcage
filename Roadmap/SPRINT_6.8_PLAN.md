# Sprint 6.8: v0.8.0 ZFS & Observability

## Goal
Deliver v0.8.0 focused on ZFS enablement for templates and storage, plus baseline observability and E2E coverage to stabilize Proxmox LXC flows.

## Scope
- ZFS ABI integration and storage enablement for containers and templates
- Template management & caching improvements
- Observability foundation: structured logs, metrics, basic tracing
- E2E tests for libcrun ABI operations and Proxmox flows
- Runtime detection of libcrun availability

## Deliverables
- ZFS-backed template creation and basic dataset lifecycle
- Structured JSON logging with contextual error chaining
- Prometheus metrics endpoint (minimal set)
- E2E tests covering create/start/stop/delete on Proxmox and libcrun ABI ops
- Automatic runtime selection for libcrun vs CLI fallback

## Milestone
- Title: Sprint 6.8: v0.8.0 ZFS & Observability
- Due date: 2025-11-17

## Backlog → In Scope Items
- From SPRINT 6.5 “Next Steps”
  - [ ] Resolve systemd linking issues for Debug builds (optional dependency) — see #136
  - [ ] Add E2E tests for libcrun ABI operations — see #134
  - [ ] Performance benchmarking (ABI vs CLI) — see #135
  - [ ] Runtime detection of libcrun availability for dynamic driver selection — see #133

- From SPRINT 6.7 (ZFS & OCI Integration)
  - [ ] #116 Native ZFS Library Integration via ABI
  - [ ] #117 Container Storage on ZFS Datasets
  - [ ] #118 Enhanced OCI Image Template Creation with ZFS Snapshots
  - [ ] #119 Template Management and Caching

- From SPRINT 6.6 (Codebase Improvements)
  - [ ] Error handling unification (`!T`, error context, chaining)
  - [ ] Audit `defer`/`errdefer`, introduce arena allocators where suitable
  - [ ] Add structured JSON logging; basic metrics export (Prometheus)

## Non-Goals (This Sprint)
- Full distribution image pulling/registry integration
- CRIU-based checkpoint/restore
- Cross-OS backends parity beyond defined E2E scope

## Acceptance Criteria
- Zig build green (Debug, ReleaseFast) on Zig 0.15.1
- v0.8.0 tag ready with release notes
- E2E suite passing for Proxmox create/start/stop/delete
- libcrun ABI E2E passing on supported runner
- Logs structured JSON; metrics endpoint exposes core counters

## Work Breakdown
- ZFS
  - [ ] Implement ABI bindings minimal surface (create/destroy/list dataset)
  - [ ] Wire datasets for container rootfs/template storage
  - [ ] Template snapshot flow for OCI→LXC templates

- Observability
  - [ ] Introduce structured logger facade
  - [ ] Add request/operation IDs and error context in hot paths
  - [ ] Export Prometheus metrics (process/runtime/core counters)

- Testing
  - [ ] E2E for libcrun ABI operations — see #134
  - [ ] Proxmox lifecycle E2E (create/start/stop/delete)
  - [ ] Performance benchmarks: ABI vs CLI

- Runtime Selection
  - [ ] Detect libcrun at runtime, auto-select driver, fallback to CLI — see #133

## Timeline (high-level)
- Week 1: ZFS ABI skeleton + structured logging
- Week 2: ZFS datasets wiring + metrics + runtime detection
- Week 3: Template snapshots + E2E (ABI + Proxmox) + perf benchmarks

## Links
- Issues: #116, #117, #118, #119
- Prior: `Roadmap/SPRINT_6.5_PROGRESS.md`, `Roadmap/SPRINT_6.6_CODEBASE_IMPROVEMENTS.md`, `Roadmap/SPRINT_6.7_START.md`


