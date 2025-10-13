# Sprint 6.5 Plan: Legacy Refactoring and Modular Integration

Date: 2025-10-13
Owner: @moriarti
Status: Planned

Goals
- Move `legacy/` to `archive/legacy/` while preserving history
- Integrate reusable legacy components into modular architecture (`src/*` backends)
- Remove any imports to `legacy/*`, update paths
- Ensure successful build and tests

Scope
- Directory `legacy/` (subfolders: `bfc/`, `common/`, `config/`, `crun/`, `network/`, `oci/`, `performance/`, `proxmox/`, `raw/`, `zfs/`)
- Check intersections with `src/*` and `tests/*`

Deliverables
- `archive/legacy/` with complete contents
- Updated imports/references
- Any extracted modules placed under `src/*`
- `Roadmap/SPRINT_6.5_PROGRESS.md`, `Roadmap/SPRINT_6.5_COMPLETED.md`

Risks
- Broken imports or missing symbols after move
- Duplicate implementations between `legacy/` and `src/`

Mitigations
- Repository-wide reference search and staged updates
- API comparison and selecting a single source of truth

Plan
1. Inventory all references to `legacy/` in codebase
2. Move `legacy/` → `archive/legacy/`
3. Update imports/references
4. Extract useful modules into `src/*` if needed
5. Build, test, fix issues
6. Document and open PR

Timebox
- Overall: 1 working day
- Reserve: 2 hours for build fixes


