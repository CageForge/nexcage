# v0.7.5 — ABI-First OCI Integration (2025-11-11)

## Highlights
- **oci-specs-zig dependency**: All OCI runtime structures (memoryPolicy, intelRdt, netDevices) now derive from the shared [`cageforge/oci-specs-zig`](https://github.com/CageForge/oci-specs-zig) package. Projects consuming `nexcage` inherit spec updates by refreshing this dependency.
- **Proxmox metadata propagation**: Parsed Intel RDT and network device data are persisted in runtime metadata and template caches to drive QoS automation.
- **ABI-only crun backend**: The CLI fallback is removed; builds compile vendored libcrun+libocispec sources and link against systemd via pkg-config.

## Upgrade Notes
1. Ensure `zig fetch --save https://github.com/CageForge/oci-specs-zig/archive/<commit>.tar.gz` has been run so that `build.zig.zon` carries the latest package fingerprint.
2. Verify `libsystemd-dev` (or the distro equivalent) is installed; the build panics if pkg-config cannot resolve `libsystemd`.
3. Regenerate vendored crun headers when updating the submodule:
   ```bash
   make prepare-crun
   ```
4. Run `zig build` and `zig build test` to confirm ABI linkage and schema parsing succeed end-to-end.

## Testing
- `zig build`
- `zig build test`
- Proxmox LXC workflow smoke checks (`pct create`, `pct set`) with OCI bundles containing intelRdt/netDevices metadata.

## Contributors
- @themoriarti

