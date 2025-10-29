## Sprint 6.5 Progress — Full Modular Refactor

### 2025-10-14
- Created `Roadmap/SPRINT_6.5_PLAN.md`.
- Fixed build by removing nonexistent `oci` module usage:
  - Deleted `src/oci/mod.zig` and removed references from code/build.
  - Cleaned `src/integrations/mod.zig` exports (removed `nfs`).
- Verified `zig build` succeeds on Zig 0.15.1.

- Centralized release version management:
  - Added `VERSION` file and build options wiring.
  - Replaced hardcoded versions in `src/main.zig` and CLI.
  - Added `scripts/bump_version.sh` and CI workflow `version-check.yml`.
  - Local CI script `scripts/ci/check_version.sh` validates version embedding.
  - Added auto-release workflow `.github/workflows/release.yml` (tag+release on VERSION change).

Time spent: 1.7h (planning: 0.4h, build fixes: 0.3h, version system + CI: 1.0h)


### 2025-10-29
- Security/validation integration and memory-safety pass:
  - Exported `core.validation` from `src/core/mod.zig`.
  - Fixed `src/core/validation.zig` self-import and aligned errors with `core.Error` variants (use `ValidationError`).
  - Integrated validation in `src/backends/crun/driver.zig` via module export.
  - Verified successful build on Zig 0.15.1 (`zig build`).

Time spent: 0.6h (debug: 0.3h, fixes: 0.2h, build+verification: 0.1h)

### 2025-10-29 (cont.)
- Enforce CLI-only Proxmox interaction policy:
  - Removed `proxmox-api` module wiring from `build.zig` (no API usage at runtime).
  - Verified `zig build` succeeds after removal.

Time spent: +0.2h (cleanup: 0.2h)

