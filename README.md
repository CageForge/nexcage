# NexCage

Next-generation container runtime for Proxmox VE using LXC and OCI backends (crun/runc).

## Compatibility Snapshot
- **OCI Runtime Specification**: fully parses Linux additions up to v1.3.0 (NUMA memoryPolicy, Intel RDT monitoring, netDevices inventory).
- **Proxmox VE**: verified on 8.x hypervisors; upcoming work tracks 9.x updates.

- Architecture: amd64 (x86_64) only
- Environment: runs on Proxmox VE host (no containerization)

## Archival Policy
- Deprecated documentation and code are moved to `archive/`
- Legacy code is kept under `archive/legacy/` and may be removed in future

## Quick Start (Ubuntu 22.04/24.04)

1) Install dependencies
```bash
sudo apt-get update
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

2) Install Zig 0.15.1 (or use CI setup)
```bash
# See https://ziglang.org/download/ for binary tarball
zig version  # should print 0.15.1
```

3) Build and run
```bash
zig build
./zig-out/bin/nexcage --help
./zig-out/bin/nexcage version
```

## CLI Examples
```bash
# Show command-specific help
./zig-out/bin/nexcage create --help

# List containers (LXC)
./zig-out/bin/nexcage list --runtime lxc
```

## Development
- Dev quickstart: see docs/DEV_QUICKSTART.md
- CLI reference: see docs/CLI_REFERENCE.md
- Architecture overview: see docs/architecture/OVERVIEW.md
- ADRs: see docs/architecture/

## Testing
- CI smoke/unit run on GitHub Actions
- E2E tests run on self-hosted Proxmox runner
- **Debug Logging**: See [DEBUG_LOGGING_GUIDE.md](docs/DEBUG_LOGGING_GUIDE.md)
- **Troubleshooting**: See [TROUBLESHOOTING_GUIDE.md](docs/TROUBLESHOOTING_GUIDE.md)
- **Test Results**: See [TESTING_RESULTS.md](docs/TESTING_RESULTS.md)
- Details: TESTING.md and PROXMOX_TESTING.md

## Security & Policies
- Security policy: SECURITY.md
- Maintainers/Governance: MAINTAINERS.md, GOVERNANCE.md
- Reproducible builds: REPRODUCIBLE_BUILDS.md
