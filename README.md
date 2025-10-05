# Proxmox LXCRI

System CLI utility for managing containers on Proxmox VE using LXC and OCI backends (crun/runc).

- Architecture: amd64 (x86_64) only
- Environment: runs on Proxmox VE host (no containerization)

## Quick Start (Ubuntu 22.04/24.04)

1) Install dependencies
```bash
sudo apt-get update
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

2) Install Zig 0.13.0 (or use CI setup)
```bash
# See https://ziglang.org/download/ for binary tarball
zig version  # should print 0.13.0
```

3) Build and run
```bash
zig build
./zig-out/bin/proxmox-lxcri --help
./zig-out/bin/proxmox-lxcri version
```

## CLI Examples
```bash
# Show command-specific help
./zig-out/bin/proxmox-lxcri create --help

# List containers (LXC)
./zig-out/bin/proxmox-lxcri list --runtime lxc
```

## Development
- Dev quickstart: see docs/DEV_QUICKSTART.md
- CLI reference: see docs/CLI_REFERENCE.md
- Architecture overview: see docs/architecture/OVERVIEW.md
- ADRs: see docs/architecture/

## Testing
- CI smoke/unit run on GitHub Actions
- E2E tests run on self-hosted Proxmox runner
- Details: TESTING.md and PROXMOX_TESTING.md

## Security & Policies
- Security policy: SECURITY.md
- Maintainers/Governance: MAINTAINERS.md, GOVERNANCE.md
- Reproducible builds: REPRODUCIBLE_BUILDS.md
