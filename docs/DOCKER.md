# Docker Build and Deployment Guide

This guide explains how to build and run Nexcage in Docker containers with all required dependencies.

## Table of Contents

- [Quick Start](#quick-start)
- [Dockerfile Architecture](#dockerfile-architecture)
- [Building the Image](#building-the-image)
- [Using Docker Compose](#using-docker-compose)
- [Configuration](#configuration)
- [Build Variants](#build-variants)
- [Runtime Requirements](#runtime-requirements)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Using Docker

```bash
# Build the image
docker build -t nexcage:latest .

# Run with help
docker run --rm nexcage:latest --help

# Run with a specific command
docker run --rm --privileged \
  -v $(pwd)/config.json:/etc/nexcage/config.json:ro \
  nexcage:latest list
```

### Using Docker Compose

```bash
# Build and run
docker-compose up nexcage

# Run specific service
docker-compose run --rm nexcage --version

# Development build
docker-compose up nexcage-dev
```

## Dockerfile Architecture

The Dockerfile uses a **multi-stage build** for optimal image size and security:

### Builder Stage

- **Base:** Ubuntu 24.04
- **Purpose:** Build nexcage binary with all dependencies
- **Size:** ~2GB (includes Zig toolchain and build tools)

**Installed Dependencies:**
- Build tools: gcc, make, cmake, git
- Zig 0.15.1 compiler
- Required libraries:
  - `libcap-dev` (capabilities)
  - `libseccomp-dev` (secure computing)
  - `libyajl-dev` (JSON parsing)
  - `libsystemd-dev` (systemd integration)
- Additional tools for submodule builds

### Runtime Stage

- **Base:** Ubuntu 24.04
- **Purpose:** Minimal runtime environment
- **Size:** ~500MB (significantly smaller)

**Installed Dependencies:**
- Runtime libraries: libcap2, libseccomp2, libyajl2, libsystemd0
- OCI runtimes: crun, runc
- ZFS utilities: zfsutils-linux
- Certificates: ca-certificates

## Building the Image

### Default Build (All Features)

```bash
docker build -t nexcage:latest .
```

This builds with:
- Core backends enabled (Proxmox LXC, Crun, Runc)
- ZFS integration enabled
- Plugin system enabled
- CLI-based Crun driver (libcrun ABI disabled)

### Custom Build with Flags

```bash
# Build with libcrun ABI enabled
docker build \
  --build-arg BUILD_FLAGS="-Denable-libcrun-abi=true" \
  -t nexcage:libcrun .

# Build with only Crun and Runc backends
docker build \
  --build-arg BUILD_FLAGS="-Denable-backend-proxmox-lxc=false -Denable-backend-proxmox-vm=false" \
  -t nexcage:oci-only .

# Minimal build
docker build \
  --build-arg BUILD_FLAGS="-Denable-backend-proxmox-lxc=false -Denable-backend-crun=false -Denable-backend-proxmox-vm=false -Denable-zfs=false -Denable-bfc=false -Denable-proxmox-api=false -Denable-plugins=false" \
  -t nexcage:minimal .
```

### Debug Build

```bash
# Build only the builder stage for development
docker build --target builder -t nexcage:dev .

# Run interactive shell in dev container
docker run -it --rm -v $(pwd):/app nexcage:dev /bin/bash
```

## Using Docker Compose

The project includes a `docker-compose.yml` with multiple service configurations:

### Services

#### `nexcage` (Default)
Production build with all features:
```bash
docker-compose up nexcage
```

#### `nexcage-dev` (Development)
Development environment with build tools:
```bash
docker-compose run --rm nexcage-dev zig build
```

#### `nexcage-libcrun` (libcrun ABI)
Build with libcrun ABI enabled:
```bash
docker-compose up nexcage-libcrun
```

### Environment Variables

Configure via `.env` file or export:

```bash
# .env file
LOG_LEVEL=debug
BUILD_VERSION=0.7.4  # or 'latest'
```

Or export:
```bash
export LOG_LEVEL=debug
docker-compose up nexcage
```

## Configuration

### Volume Mounts

Mount your configuration file:

```bash
docker run --rm --privileged \
  -v $(pwd)/config.json:/etc/nexcage/config.json:ro \
  nexcage:latest start my-container
```

### Persistent Storage

Use volumes for persistent data:

```bash
docker run --rm --privileged \
  -v nexcage-data:/var/lib/nexcage \
  -v /var/lib/containers:/var/lib/containers \
  nexcage:latest list
```

### Configuration File

Create a `config.json`:

```json
{
  "runtime_type": "crun",
  "default_runtime": "crun",
  "runtime": {
    "log_level": "info",
    "routing": []
  }
}
```

## Build Variants

### Production (ReleaseSafe)

Default build with safety checks:
```bash
docker build -t nexcage:prod .
```

### Performance (ReleaseFast)

Maximum performance, fewer safety checks:
```bash
docker build \
  --build-arg BUILD_FLAGS="-Doptimize=ReleaseFast" \
  -t nexcage:fast .
```

### Size-Optimized (ReleaseSmall)

Smallest binary size:
```bash
docker build \
  --build-arg BUILD_FLAGS="-Doptimize=ReleaseSmall" \
  -t nexcage:small .
```

## Runtime Requirements

### Privileged Mode

Nexcage requires privileged mode for container management:

```bash
docker run --privileged nexcage:latest
```

### Capabilities

Minimum required capabilities:

```bash
docker run --rm \
  --cap-add SYS_ADMIN \
  --cap-add NET_ADMIN \
  --cap-add SYS_PTRACE \
  --security-opt apparmor:unconfined \
  --security-opt seccomp:unconfined \
  nexcage:latest
```

### Networking

For container networking:

```bash
docker run --rm --privileged \
  --network host \
  nexcage:latest
```

## Troubleshooting

### Build Failures

**Error: Cannot find libcap/libseccomp/libyajl**
```
Solution: These are installed in the Dockerfile. If you modified it, ensure:
  apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

**Error: Git submodules not initialized**
```
Solution: The Dockerfile handles this automatically. If building locally:
  git submodule update --init --recursive
```

**Error: Zig build failed**
```
Solution: Check the BUILD_FLAGS are valid:
  docker build --no-cache -t nexcage:latest .
```

### Runtime Errors

**Error: Permission denied**
```
Solution: Run with --privileged flag:
  docker run --privileged nexcage:latest
```

**Error: Runtime not found (crun/runc)**
```
Solution: The runtime stage includes crun and runc. If missing:
  docker exec -it <container> which crun runc
```

**Error: ZFS utilities not available**
```
Solution: ZFS is installed but may need kernel modules on host:
  modprobe zfs
```

### Image Size

Check layer sizes:
```bash
docker history nexcage:latest
```

Remove build cache:
```bash
docker builder prune -af
```

### Debugging

Run interactive shell in container:
```bash
docker run -it --rm --entrypoint /bin/bash nexcage:latest
```

Check installed dependencies:
```bash
docker run --rm nexcage:latest dpkg -l | grep -E 'libcap|libseccomp|libyajl|crun|runc'
```

## Advanced Usage

### Multi-Platform Builds

Build for multiple architectures:

```bash
docker buildx create --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t nexcage:latest \
  --push .
```

### CI/CD Integration

GitHub Actions example:

```yaml
- name: Build Docker Image
  run: |
    docker build \
      --build-arg BUILD_VERSION=${{ github.ref_name }} \
      -t nexcage:${{ github.sha }} .
```

### Registry Push

```bash
# Tag for registry
docker tag nexcage:latest ghcr.io/cageforge/nexcage:latest

# Push to registry
docker push ghcr.io/cageforge/nexcage:latest
```

## See Also

- [Build Flags Documentation](BUILD_FLAGS.md) - Detailed build flag reference
- [Configuration Guide](configuration.md) - Runtime configuration options
- [Contributing Guide](../CONTRIBUTING.md) - Development workflow
