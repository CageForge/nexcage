## Sprint 6.5 Plan — Full Modular Refactor

### Goal
Complete project-wide refactor to a fully modular architecture with clear boundaries, stable public interfaces, and feature-flagged builds.

### Key Outcomes
- Core owns abstractions; implementations in separate modules
- Module registry for discovery and dependency wiring
- CLI commands depend only on interfaces
- Build flags to include/exclude modules
- Tests organized per module with interface-level coverage

### Milestones
1. Architecture analysis and gap report
2. Define interfaces and contracts (core)
3. Implement module registry + wiring
4. Backend refactor to interfaces (phase 1)
5. CLI refactor to decouple routing and execution
6. Build system feature flags and targets
7. Tests reorganization per module
8. Docs updates and release notes draft

### Definition of Done
- `zig build` succeeds with feature flags combinations
- Unit tests per module pass; E2E happy path passes
- Docs updated: `docs/MODULAR_ARCHITECTURE.md`, CLI reference
- Roadmap and changelog updated

### Risks & Mitigations
- Interface churn → lock minimal stable contracts early; iterate behind flags
- Coupling leaks → enforce imports only via core interfaces
- Build fragility → CI matrix for flags combinations


