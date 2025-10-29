# PR Title

Release v0.7.0 — kill/state, Proxmox fixes, security hardening

## Summary
- OCI `kill` and `state` commands
- Proxmox LXC image parsing fixes; ZFS validations; path security
- Logging stability and debug gating; input validators

## Changes
- See `CHANGELOG.md` (0.7.0) and `docs/releases/NOTES_v0.7.0.md`

## Testing
- Build green on Zig 0.15.1
- Proxmox E2E report: `test-reports/proxmox_e2e_test_report_20251029_194308.md`

## Checklist
- [ ] Build succeeds (ReleaseFast)
- [ ] CLI docs updated
- [ ] Roadmap updated with time spent
- [ ] Version bumped to 0.7.0
- [ ] Changelog updated 