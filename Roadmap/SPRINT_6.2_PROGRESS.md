Sprint 6.2 - Backend integration and v0.5.0 features

Date: 2025-09-30

Scope for this slice:
- Re-enable LXC backend calls in CLI (`list`, `start`, `stop`, `delete`) replacing earlier no-op stubs
- Stabilize process execution and logging; avoid crashes when LXC tools are missing

Changes implemented:
- CLI commands now initialize `LxcBackend` and call real driver methods
- Proper use of allocator and safe `defer` with optional network bridge
- `LxcDriver` switched to allocator.create/destroy for single structs
- `runCommand` now uses `std.process.Child.run` and handles `error.FileNotFound` gracefully
- Added handling for exit code 127:
  - `list` returns empty set with a warning if `lxc-ls` isn't available
  - `start/stop/delete` return `UnsupportedOperation` with a clear warning if tools are missing

2025-09-30 (later the same day):
- CLI now catches `UnsupportedOperation` and logs user-friendly warnings in `start/stop/delete/list`
- Build remains green; behavior is stable without system LXC tools

Build & tests:
- `zig build` OK
- CLI smoke:
  - `list --runtime lxc`: no crash; empty result if LXC tools absent
  - `start/stop/delete container-1`: controlled `UnsupportedOperation` when tools missing

Notes:
- Next: install LXC utilities in CI/smoke environment to exercise real flows
- Next: extend error mapping and JSON parsing for `lxc-ls --format json`

CI:
- Added GitHub Actions workflow `.github/workflows/ci.yml`:
  - Build with Zig 0.13
  - Smoke run `help` and `list --runtime lxc`
  - Enforced on PRs to `main`/`develop`

Documentation (Architecture as Code):
- Added Mermaid-based docs:
  - `docs/architecture/OVERVIEW.md` (system and sequence)
  - `docs/architecture/BACKENDS.md` (backends/class)
  - ADRs: `ADR-000-Template.md`, `ADR-004-Mermaid-Architecture-Docs.md`
  - `docs/architecture/MODULES.md`, `docs/architecture/DEPLOYMENT.md`

Time spent: 1h 15m

