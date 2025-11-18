# v0.7.4 — OCI 1.3.0 Compatibility Sweep

## Highlights
- Added parsing support for OCI Runtime Spec v1.3.0 Linux additions:
  - NUMA `memoryPolicy` (modes, nodes, flags)
  - Intel RDT monitoring (`schemata`, `enableMonitoring`, cache/bandwidth schemas)
  - `netDevices` inventory map
- Extended Proxmox LXC bundle parser with stricter validation and safer memory management.
- Updated developer docs to call out the new spec baseline and runtime guarantees.
- Build tooling now compiles vendored `deps/crun` sources and only relies on `pkg-config libsystemd` at build time; the legacy CLI fallback is gone.

## Upgrade Notes
- Bundles declaring `ociVersion: 1.3.0` or newer 1.x releases now load without manual downgrades.
- Intel RDT fields are parsed and persisted to runtime metadata (`/run/nexcage/<id>/runtime-metadata.json`); applying QoS remains a manual step for now.
- `linux.netDevices` aliases are emitted as pct `--netX` definitions and rendered into `/etc/network/interfaces`, defaulting to the configured bridge when host links are absent.
- Unknown `memoryPolicy` flags or malformed `netDevices` entries will now raise structured errors during conversion.

## Validation
- `zig build` (Linux amd64, Zig 0.15.1)
- `zig build test`

## Follow-ups
- Automate Proxmox QoS configuration for Intel RDT profiles (current release only persists metadata).
- Extend integration docs with examples for OCI 1.3.0 bundles.

