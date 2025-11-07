# v0.7.4 — OCI 1.3.0 Compatibility Sweep

## Highlights
- Added parsing support for OCI Runtime Spec v1.3.0 Linux additions:
  - NUMA `memoryPolicy` (modes, nodes, flags)
  - Intel RDT monitoring (`schemata`, `enableMonitoring`, cache/bandwidth schemas)
  - `netDevices` inventory map
- Extended Proxmox LXC bundle parser with stricter validation and safer memory management.
- Updated developer docs to call out the new spec baseline and runtime guarantees.
- Build tooling now requires `libcrun` and `libsystemd` via `pkg-config`; builds fail if the ABI dependencies are absent, reflecting the removal of the legacy CLI fallback.

## Upgrade Notes
- Bundles declaring `ociVersion: 1.3.0` or newer 1.x releases now load without manual downgrades.
- Intel RDT fields are parsed and surfaced for validation; runtime mapping to Proxmox primitives remains opt-in.
- Unknown `memoryPolicy` flags or malformed `netDevices` entries will now raise structured errors during conversion.

## Validation
- `zig build` (Linux amd64, Zig 0.15.1)
- `zig build test`

## Follow-ups
- Map parsed Intel RDT values to Proxmox-specific QoS controls.
- Implement runtime behaviour for `netDevices` alias → LXC config bridging.
- Extend integration docs with examples for OCI 1.3.0 bundles.

