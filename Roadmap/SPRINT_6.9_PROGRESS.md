# Sprint 6.9 — Release 0.7.4 Dependency Refresh

## Update — 2025-11-07

- Completed OCI Runtime Spec v1.3.0 parsing work (`feature/oci-spec-1.3-upgrade`).
- Updated public docs (README, Dev Quickstart, MkDocs index) to declare new spec baseline.
- Added release notes (`docs/releases/NOTES_v0.7.4.md`) and changelog entry for v0.7.4.
- Verified build + unit tests via `zig build`, `zig build test`.
- Resolved libcrun ABI debug linking by auto-detecting `libsystemd` in build.zig and documenting the removal of the CLI fallback; vendored `deps/crun` is now compiled directly.
- Next: map Intel RDT/netDevices metadata into runtime configuration and extend user docs with concrete examples.

## Plan — Intel RDT & Net Devices Integration

- **netDevices → Proxmox LXC**
  - Derive pct `--netX` arguments from `linux.netDevices` aliases (fallback to default bridge when host link is absent).
  - Render `/etc/network/interfaces` entries for every declared alias while preserving the loopback stanza.
  - Persist effective interface mapping into runtime metadata for later orchestration tooling.
- **intelRdt metadata**
  - Capture `closID`, schemata, cache/bandwidth profiles and monitoring flag during template conversion.
  - Write structured runtime metadata alongside the existing `/run/nexcage/<id>/state.json` to unblock future cgroup2 hooks.
  - Surface metadata through `TemplateManager` so UI / automation can display the profile before container launch.

## Update — 2025-11-10

- Implemented pct networking synthesis from OCI `linux.netDevices` (multiple adapters, default bridge fallback) and regenerated `/etc/network/interfaces`.
- Captured Intel RDT metadata in template cache and persisted a per-container `runtime-metadata.json` with schemata/monitoring flags.
- Added manual JSON serialization helpers compatible with Zig 0.15 writer API.
- Build + test: `zig build`, `zig build test`.

