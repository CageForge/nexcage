# Sprint 6.9 — Release 0.7.4 Dependency Refresh

## Update — 2025-11-07

- Completed OCI Runtime Spec v1.3.0 parsing work (`feature/oci-spec-1.3-upgrade`).
- Updated public docs (README, Dev Quickstart, MkDocs index) to declare new spec baseline.
- Added release notes (`docs/releases/NOTES_v0.7.4.md`) and changelog entry for v0.7.4.
- Verified build + unit tests via `zig build`, `zig build test`.
- Resolved libcrun ABI debug linking by auto-detecting `libsystemd` in build.zig and documenting the fallback.
- Next: map Intel RDT/netDevices metadata into runtime configuration and extend user docs with concrete examples.

