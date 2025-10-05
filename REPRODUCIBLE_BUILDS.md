# Reproducible Builds

This project targets reproducible builds where feasible.

## Tooling versions
- Zig: 0.13.0 (pinned in workflows)
- System libs: libcap-dev, libseccomp-dev, libyajl-dev (CI installs)

## Determinism guidelines
- Avoid embedding timestamps; prefer constant version strings
- Use `zig build -Doptimize=ReleaseFast` in release
- Record commit hash in `proxmox-lxcri version` output

## How to reproduce
1. Checkout the release tag
2. Use Ubuntu `ubuntu-latest` runner or documented environment
3. Run: `zig build -Doptimize=ReleaseFast`
4. Compare sha256 checksums with release assets
