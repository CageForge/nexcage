# Release Notes — v0.7.0

## Highlights
- OCI `kill` command with `--signal`, wired for proxmox-lxc, crun, runc
- OCI `state` command with OCI-compatible JSON output
- Proxmox LXC image parsing fix (templates vs docker-style refs)
- ZFS pool/dataset validation and parent dataset auto-create
- Path security hardening for OCI bundles
- Logging stability (allocator safety) and debug gating via `--debug`
- Foundational input validators and hostname validation in CLI

## Changes
### Added
- `kill` CLI command (OCI-compliant) and backend implementations
- `state` CLI command with standardized JSON output
- Input validation helpers: hostname/VMID/storage/path/env

### Changed
- Debug output is disabled by default; enable with `--debug`
- Safer logging allocator and file handling
- Stricter image handling in Proxmox LXC backend

### Fixed
- Segfault during `create` due to logger allocator misuse
- ZFS errors when pool missing; now graceful and/or auto-create parents

## Testing
- Local build: green (Zig 0.15.1)
- Proxmox E2E: smoke OK; functional flows pending create/start stabilization
  - Report: `test-reports/proxmox_e2e_test_report_20251029_194308.md`

## Upgrade Notes
- Docker-style image refs (e.g. `ubuntu:20.04`) are not auto-fetched in Proxmox flow; use Proxmox templates or OCI bundles

## Links
- Changelog entry: `CHANGELOG.md` (0.7.0)

