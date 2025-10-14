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

Time spent: 1.3h (planning: 0.4h, build fixes: 0.3h, version system + CI: 0.6h)


