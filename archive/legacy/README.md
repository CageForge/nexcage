# Legacy (Archived)

Status: Deprecated (Archived)

This directory preserves legacy sources and documentation for historical reference only. The active codebase has fully migrated to the modular architecture under `src/`.

Where to look now
- CLI: `src/cli/`
- Core types/config: `src/core/`
- Backends: `src/backends/` (LXC, OCI/crun)
- Integrations (Proxmox): `src/integrations/`
- Utilities: `src/utils/`

Policies
- No new development will occur in `archive/legacy/`.
- References to legacy modules should be removed or replaced with their modular equivalents.
- If a feature exists only in legacy, extract and refactor it into `src/*` with tests.

Build & CI
- Legacy code is excluded from the default build and CI pipelines.
- Follow `README.md` for building the modular runtime.

Contact
- Maintainers: see `MAINTAINERS.md`
- Governance: see `GOVERNANCE.md`
# Legacy Architecture (Deprecated)

⚠️ **WARNING**: This legacy architecture is deprecated as of v0.4.0.

## Status

- **Deprecated**: October 1, 2025
- **End of Support**: December 31, 2025
- **Migration Required**: Yes - use modular architecture

## Migration

Please migrate to the new modular architecture:

1. **Read**: [../MODULAR_ARCHITECTURE.md](../docs/MODULAR_ARCHITECTURE.md)
2. **Examples**: [../examples/](../examples/)
3. **Migration Guide**: [../LEGACY_DEPRECATION.md](../LEGACY_DEPRECATION.md)

## Build Legacy Version

```bash
# Build legacy version (not recommended)
cd legacy
zig build
```

## Legacy Structure

```
legacy/src/
├── main_legacy.zig          # Legacy main entry point
├── common/                  # Legacy common modules
├── oci/                     # Legacy OCI implementation
├── proxmox/                 # Legacy Proxmox integration
├── network/                 # Legacy network module
├── performance/             # Legacy performance module
├── raw/                     # Legacy raw module
├── config/                  # Legacy config module
├── bfc/                     # Legacy BFC module
├── crun/                    # Legacy Crun module
└── zfs/                     # Legacy ZFS module
```

## Support Policy

- **Critical Bug Fixes**: Security and stability issues only
- **Security Updates**: Important security patches
- **Migration Help**: Support for migration process
- **No New Features**: No feature development

## Getting Help

- **Migration**: See [../MODULAR_ARCHITECTURE.md](../docs/MODULAR_ARCHITECTURE.md)
- **Issues**: Create GitHub issue for migration help
- **Community**: Join community discussions

---

**Please migrate to the modular architecture for continued support and new features.**
