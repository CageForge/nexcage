# ADR-004: Mermaid-based Architecture-as-Code Documentation

- Status: Accepted
- Date: 2025-09-30

## Context
We want documentation to be versioned alongside code and machine-renderable in GitHub.

## Decision
Adopt Mermaid diagrams in `docs/architecture/` and keep ADRs for architectural decisions.

## Consequences
- Pros: Up-to-date diagrams, easy reviews in PRs, simple diffs.
- Cons: Limited rendering locally without preview; requires consistent style.

## Alternatives
- PlantUML: requires additional tooling.
- Images: not diff-friendly.

## Links
- `docs/architecture/OVERVIEW.md`
- `docs/architecture/BACKENDS.md`
