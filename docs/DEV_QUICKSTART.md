# Developer Quickstart

This guide helps you set up a development environment quickly.

## Requirements
- OS: Ubuntu 22.04/24.04 (Proxmox VE host recommended)
- Arch: amd64 (x86_64)
- Packages: libcap-dev, libseccomp-dev, libyajl-dev
- Compiler: Zig 0.15.1
- Spec baseline: OCI Runtime Specification v1.3.0 (Linux additions fully parsed)

## Setup
```bash
sudo apt-get update
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
# install Zig 0.15.1 and ensure zig is on PATH
zig version
```

## Build & Run
```bash
zig build
./zig-out/bin/nexcage --help
./zig-out/bin/nexcage version
```

### libcrun ABI requirements
- `pkg-config` must resolve both `libcrun` and `libsystemd` development packages.
- Build command: `zig build -Denable-libcrun-abi=true` (default).
- The build fails if those dependencies are missing; install the dev packages or use the vendored libcrun workflow.

## Local Smoke (no Proxmox)
```bash
./zig-out/bin/nexcage create --help
./zig-out/bin/nexcage list --runtime lxc || true
```

## Proxmox E2E (self-hosted)
- Configure self-hosted runner on Proxmox VE (see SELF_HOSTED_RUNNER.md)
- Run: GitHub Actions job "Proxmox E2E (Self-Hosted)"

## Debugging
- Enable debug logs with `--debug` or `--verbose`
- Check system libs presence: `ldconfig -p | grep -E 'libcap|libseccomp|libyajl'`

## Next
- CLI Reference: docs/CLI_REFERENCE.md
- Architecture: docs/architecture/OVERVIEW.md
- Testing: TESTING.md, PROXMOX_TESTING.md
