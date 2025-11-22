# Developer Workflow for macOS

This guide provides a recommended development workflow for contributors working on Nexcage from macOS systems.

## Overview

Since Nexcage is a Linux container runtime that interfaces with Proxmox VE and LXC, macOS developers need to use a hybrid workflow:

- **Code editing and Git operations:** Done natively on macOS
- **Building and testing:** Done in a Linux environment (Docker, VM, or remote Proxmox host)

## Prerequisites

### Required on macOS

- **Homebrew:** Package manager for macOS
- **Git:** Version control
- **Docker Desktop:** For building and basic testing
- **IDE/Editor:** VS Code, Zed, or your preferred editor
- **SSH client:** For remote development on Proxmox hosts

### Optional Tools

- **Zig 0.15.1:** Can be installed on macOS for syntax checking and LSP support
- **Remote SSH extension:** For VS Code remote development
- **gh CLI:** GitHub command-line tool for PR management

## Setup Instructions

### 1. Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Development Tools

```bash
# Core tools
brew install git gh

# Optional: Zig for local syntax checking (LSP)
brew install zig

# Docker Desktop
brew install --cask docker
```

### 3. Clone the Repository

```bash
git clone https://github.com/CageForge/nexcage.git
cd nexcage
```

### 4. Configure Git

```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

## Development Workflows

### Workflow 1: Docker-Based Development (Recommended for Most Tasks)

This workflow is ideal for:

- Code changes and local builds
- Unit testing
- Documentation updates
- Quick iteration cycles

#### Build in Docker

```bash
# Build the Docker image with all dependencies
docker build -t nexcage:dev .

# Run a build inside the container
docker run --rm -v $(pwd):/workspace -w /workspace nexcage:dev zig build

# Run tests
docker run --rm -v $(pwd):/workspace -w /workspace nexcage:dev zig build test

# Interactive shell for development
docker run --rm -it -v $(pwd):/workspace -w /workspace nexcage:dev bash
```

#### Using Docker Compose

```bash
# Start development environment
docker-compose up -d nexcage

# Access the container
docker-compose exec nexcage bash

# Build inside container
zig build

# Run the binary
./zig-out/bin/nexcage version
```

#### Custom Builds with Feature Flags

```bash
# Build with specific backends only
docker run --rm -v $(pwd):/workspace -w /workspace nexcage:dev \
  zig build \
  -Denable-backend-crun=true \
  -Denable-backend-proxmox-lxc=false \
  -Denable-backend-proxmox-vm=false

# Build with libcrun ABI
docker run --rm -v $(pwd):/workspace -w /workspace nexcage:dev \
  zig build -Denable-libcrun-abi=true
```

### Workflow 2: Remote Proxmox Development (For Integration Testing)

This workflow is essential for:

- Testing Proxmox-specific features
- LXC container integration
- End-to-end testing
- Performance testing

#### SSH Access to Proxmox Host

```bash
# Set up SSH key (if not already done)
ssh-keygen -t ed25519 -C "your.email@example.com"
ssh-copy-id root@proxmox-host

# SSH to Proxmox host
ssh root@proxmox-host
```

#### Sync Code to Proxmox

```bash
# Use rsync to sync your local changes
rsync -avz --exclude 'zig-cache' --exclude 'zig-out' \
  ~/dev/nexcage/ root@proxmox-host:/root/nexcage/

# Or use git on the remote host
ssh root@proxmox-host
cd /root/nexcage
git pull origin feature-branch
```

#### Build and Test on Proxmox

```bash
# SSH into Proxmox
ssh root@proxmox-host

# Navigate to project
cd /root/nexcage

# Build
zig build

# Run integration tests
./zig-out/bin/nexcage create --runtime lxc test-container
./zig-out/bin/nexcage list
./zig-out/bin/nexcage delete test-container
```

### Workflow 3: VS Code Remote Development

This workflow provides the best of both worlds - native IDE on macOS, but building/testing on Linux.

#### Setup Remote SSH in VS Code

1. Install "Remote - SSH" extension in VS Code
2. Edit SSH config (`~/.ssh/config`):

```
Host proxmox-dev
    HostName <proxmox-ip-address>
    User root
    IdentityFile ~/.ssh/id_ed25519
```

3. Connect to remote host:

   - Open VS Code
   - Press `Cmd+Shift+P`
   - Select "Remote-SSH: Connect to Host"
   - Choose `proxmox-dev`

4. Open the nexcage folder on the remote host
5. Install extensions on remote (Zig Language Server, etc.)
6. Develop as if local, but builds run on Linux

#### Recommended VS Code Extensions

- **Remote - SSH:** Remote development
- **Zig Language:** Zig language support
- **GitLens:** Enhanced Git integration
- **Docker:** Docker container management
- **Markdown All in One:** Documentation editing

## Development Tasks

### Making Changes

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes in your editor

# Build and test (choose a workflow above)
docker run --rm -v $(pwd):/workspace -w /workspace nexcage:dev zig build

# Check for errors
docker run --rm -v $(pwd):/workspace -w /workspace nexcox:dev zig build test
```

### Running Specific Tests

```bash
# Run all tests
zig build test

# Run specific test file (on Linux/Docker)
zig test src/path/to/test_file.zig
```

### Code Quality Checks

```bash
# Format check (Zig has built-in formatter)
zig fmt --check src/

# Auto-format all files
zig fmt src/

# Build with all backends disabled to test modularity
zig build \
  -Denable-backend-proxmox-lxc=false \
  -Denable-backend-proxmox-vm=false \
  -Denable-backend-crun=false \
  -Denable-backend-runc=false
```

### Commit and Push

```bash
# Stage changes
git add .

# Commit with descriptive message
git commit -m "feat: add new feature description"

# Push to your fork
git push origin feature/your-feature-name
```

### Creating Pull Requests

```bash
# Using gh CLI
gh pr create --title "feat: your feature" --body "Description of changes"

# Or use GitHub web interface
open https://github.com/CageForge/nexcage/compare
```

## Common Development Scenarios

### Scenario 1: Fixing a Bug

1. Create issue branch: `git checkout -b fix/issue-123`
2. Write a failing test that reproduces the bug
3. Fix the bug
4. Verify test passes
5. Commit and create PR

### Scenario 2: Adding a New Feature

1. Create feature branch: `git checkout -b feature/new-backend`
2. Update `build.zig` if adding new build options
3. Implement feature with tests
4. Update documentation in `docs/`
5. Add entry to `CHANGELOG.md`
6. Create PR with comprehensive description

### Scenario 3: Documentation Updates

1. Edit markdown files in `docs/`
2. Preview locally (use VS Code markdown preview)
3. Commit and push (can be done entirely on macOS)
4. Create PR

### Scenario 4: Testing Proxmox Integration

1. Make code changes on macOS
2. Sync to Proxmox host:
   ```bash
   rsync -avz --exclude 'zig-cache' --exclude 'zig-out' \
     . root@proxmox-host:/root/nexcage/
   ```
3. SSH to Proxmox: `ssh root@proxmox-host`
4. Build and test:
   ```bash
   cd /root/nexcage
   zig build
   ./zig-out/bin/nexcage create --runtime lxc test-ct
   ```

## Tips and Best Practices

### Performance Tips

- **Use Docker BuildKit:** Set `DOCKER_BUILDKIT=1` for faster builds
- **Mount cache volumes:** Speed up repeated builds
  ```bash
  docker run --rm \
    -v $(pwd):/workspace \
    -v zig-cache:/workspace/zig-cache \
    -w /workspace nexcage:dev zig build
  ```
- **Keep builds incremental:** Don't `rm -rf zig-cache` unless necessary

### Git Workflow

- **Keep commits atomic:** One logical change per commit
- **Write descriptive messages:** Follow [Conventional Commits](https://www.conventionalcommits.org/)
- **Rebase before pushing:** Keep history clean
  ```bash
  git fetch origin
  git rebase origin/main
  ```
- **Use draft PRs:** For work-in-progress features

### Testing Strategy

1. **Unit tests:** Run in Docker (fast, no Proxmox needed)
2. **Integration tests:** Run on Proxmox host (real environment)
3. **Smoke tests:** Quick sanity checks after builds
4. **E2E tests:** Full workflow testing on Proxmox

### Debugging

```bash
# Enable debug output
./zig-out/bin/nexcage --debug command

# Use verbose logging
./zig-out/bin/nexcage --verbose command

# Check binary dependencies (on Linux)
ldd ./zig-out/bin/nexcage

# Inspect build options
zig build --help
```

## Troubleshooting

### Issue: "Zig version mismatch"

```bash
# Install exact version via Homebrew
brew install zig@0.15.1

# Or download from https://ziglang.org/download/
```

### Issue: "Cannot connect to Docker daemon"

```bash
# Start Docker Desktop
open -a Docker

# Verify Docker is running
docker info
```

### Issue: "Permission denied" when syncing to Proxmox

```bash
# Check SSH key permissions
chmod 600 ~/.ssh/id_ed25519

# Verify SSH access
ssh -v root@proxmox-host
```

### Issue: "libsystemd not found" in Docker build

```bash
# Rebuild Docker image to include all dependencies
docker build --no-cache -t nexcage:dev .
```

### Issue: Build fails with "undefined symbols"

```bash
# This usually means you're missing build flags
# Enable libcrun ABI:
zig build -Denable-libcrun-abi=true

# Or disable backends that need unavailable libraries:
zig build -Denable-backend-crun=false
```

## Recommended Project Structure on macOS

```
~/dev/
└── nexcage/                    # Main repository
    ├── .git/                   # Git metadata
    ├── src/                    # Source code
    ├── docs/                   # Documentation
    ├── zig-cache/              # Build cache (in .gitignore)
    ├── zig-out/                # Build output (in .gitignore)
    ├── build.zig               # Build configuration
    └── Dockerfile              # For Docker-based builds
```

## Additional Resources

- **Main Documentation:** [docs/index.md](index.md)
- **Ubuntu Development:** [DEVELOPMENT_UBUNTU.md](DEVELOPMENT_UBUNTU.md)
- **Build Flags:** [BUILD_FLAGS.md](BUILD_FLAGS.md)
- **Docker Guide:** [DOCKER.md](DOCKER.md)
- **Contributing Guide:** [../CONTRIBUTING.md](../CONTRIBUTING.md)
- **Troubleshooting:** [TROUBLESHOOTING_GUIDE.md](TROUBLESHOOTING_GUIDE.md)

## Getting Help

- **GitHub Issues:** https://github.com/CageForge/nexcage/issues
- **Discussions:** https://github.com/CageForge/nexcage/discussions
- **Pull Requests:** https://github.com/CageForge/nexcage/pulls

## Summary

This hybrid approach gives you the best macOS development experience while ensuring your code works correctly in the target Linux environment.
