# Development Environment Setup on Ubuntu

## 🚀 Development Environment for Proxmox LXCRI

While Proxmox LXCRI is designed exclusively for **Debian Linux** and **Proxmox VE** in production, developers can use **Ubuntu** as a development environment for code editing, compilation, and unit testing.

> **⚠️ Important**: Full integration testing requires a real Proxmox VE server. Ubuntu is only for development convenience.

## Prerequisites

### System Requirements
- **Ubuntu 22.04 LTS** or **Ubuntu 24.04 LTS**
- 8GB+ RAM (for comfortable development)
- 20GB+ free disk space
- Internet connection for dependencies

### Verify Ubuntu Environment
```bash
# Check Ubuntu version
lsb_release -a

# Verify system resources
free -h
df -h /
```

## Development Dependencies Installation

### Install Core Dependencies
```bash
# Update package list
sudo apt update

# Install build essentials
sudo apt install -y \
    build-essential \
    git \
    curl \
    wget \
    pkg-config \
    libseccomp-dev \
    libsystemd-dev \
    zfsutils-linux

# Install container runtime dependencies (for testing)
sudo apt install -y \
    crun \
    runc \
    uidmap \
    systemd-container
```

### Install Zig Compiler
```bash
# Download and install Zig 0.15.1
ZIG_VERSION="0.15.1"
ZIG_ARCH="x86_64"  # or "aarch64" for ARM64

curl -L "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${ZIG_ARCH}-${ZIG_VERSION}.tar.xz" \
    | sudo tar -xJ -C /usr/local --strip-components=1

# Verify installation
zig version
```

### Install Development Tools
```bash
# Install debugging and profiling tools
sudo apt install -y \
    gdb \
    valgrind \
    strace \
    htop \
    tree

# Install VS Code (optional)
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
sudo apt update
sudo apt install code
```

## Project Setup

### Clone Repository
```bash
# Clone the project
git clone https://github.com/kubebsd/proxmox-lxcri.git
cd proxmox-lxcri

# Verify project structure
tree -L 2
```

### Configure Git (if not already done)
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

## Development Workflow

### Build Project
```bash
# Debug build for development
zig build -Doptimize=Debug

# Release build (production-like)
zig build -Doptimize=ReleaseSafe

# Check build artifacts
ls -la zig-out/bin/
```

### Run Unit Tests
```bash
# Run all unit tests
zig build test

# Run specific test module
zig build test -- --filter "memory"

# Run tests with verbose output
zig build test -- --verbose
```

### Code Quality Checks
```bash
# Format code
zig fmt src/

# Static analysis
zig build analyze

# Check for memory leaks (basic)
zig build test-memory
```

### Development Configuration
```bash
# Create development configuration
cat > config/development.json << 'EOF'
{
  "runtime": {
    "primary": "crun",
    "fallback": "runc",
    "data_dir": "/tmp/proxmox-lxcri-dev"
  },
  "logging": {
    "level": "debug",
    "format": "text",
    "file": "/tmp/proxmox-lxcri-dev.log"
  },
  "development": {
    "enable_profiling": true,
    "mock_proxmox": true,
    "skip_zfs_checks": true
  }
}
EOF
```

### Development Testing
```bash
# Test basic functionality (without Proxmox VE)
export PROXMOX_LXCRI_CONFIG="$(pwd)/config/development.json"
./zig-out/bin/proxmox-lxcri --version
./zig-out/bin/proxmox-lxcri spec

# Run development smoke tests
zig build test-dev
```

## IDE Setup

### VS Code Configuration
Create `.vscode/settings.json`:
```json
{
    "zig.initialSetupDone": true,
    "zig.zigPath": "/usr/local/bin/zig",
    "zig.buildOnSave": true,
    "zig.enableLanguageServer": true,
    "files.associations": {
        "*.zig": "zig"
    },
    "editor.formatOnSave": true,
    "[zig]": {
        "editor.defaultFormatter": "ziglang.vscode-zig"
    }
}
```

Create `.vscode/tasks.json`:
```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "zig build",
            "type": "shell",
            "command": "zig",
            "args": ["build"],
            "group": {
                "kind": "build",
                "isDefault": true
            },
            "presentation": {
                "clear": true
            },
            "problemMatcher": []
        },
        {
            "label": "zig test",
            "type": "shell",
            "command": "zig",
            "args": ["build", "test"],
            "group": "test",
            "presentation": {
                "clear": true
            }
        }
    ]
}
```

### Install VS Code Extensions
```bash
code --install-extension ziglang.vscode-zig
code --install-extension ms-vscode.cpptools
code --install-extension GitHub.copilot  # optional
```

## Debugging

### Debug Build
```bash
# Build with debug symbols
zig build -Doptimize=Debug

# Run with GDB
gdb ./zig-out/bin/proxmox-lxcri
```

### Memory Analysis
```bash
# Check for memory leaks with Valgrind
valgrind --leak-check=full --track-origins=yes \
    ./zig-out/bin/proxmox-lxcri spec
```

### System Call Tracing
```bash
# Trace system calls
strace -o trace.log ./zig-out/bin/proxmox-lxcri --version

# Analyze trace
less trace.log
```

## Limitations on Ubuntu

### What Works
✅ Code compilation and building  
✅ Unit tests execution  
✅ Static analysis and formatting  
✅ Memory leak detection  
✅ Basic functionality testing  
✅ Development tools and debugging  

### What Doesn't Work
❌ **Full Proxmox VE integration** (requires real Proxmox VE)  
❌ **ZFS snapshots** (Ubuntu setup different from Proxmox VE)  
❌ **Container runtime registration** (systemd integration)  
❌ **Production deployment** (Debian/Proxmox VE only)  
❌ **Full integration tests** (mock environment only)  

## Production Testing

### Proxmox VE Test Environment
For complete testing, you need:

1. **Proxmox VE Server** (version 8.0+)
2. **Debian 12 (Bookworm)** base system
3. **ZFS storage pool** configured
4. **Network configuration** for containers

### Setting up Proxmox VE Test
```bash
# On actual Proxmox VE server
# Transfer built binary from Ubuntu development
scp zig-out/bin/proxmox-lxcri root@proxmox-server:/tmp/

# SSH to Proxmox VE server
ssh root@proxmox-server

# Install and test on Proxmox VE
cp /tmp/proxmox-lxcri /usr/local/bin/
chmod +x /usr/local/bin/proxmox-lxcri

# Run full integration tests
proxmox-lxcri --version
proxmox-lxcri create test-container --image alpine:latest
```

## Continuous Integration

### GitHub Actions (Ubuntu Runner)
The CI/CD pipeline uses Ubuntu 22.04 runners for:
- ✅ Building for Debian targets
- ✅ Running unit tests
- ✅ Code quality checks
- ✅ Security scanning
- ✅ Package building

### Local CI Simulation
```bash
# Simulate CI locally
./scripts/ci-local.sh
```

## Best Practices

### Development Workflow
1. **Code on Ubuntu** with full IDE support
2. **Build and test** locally for quick feedback
3. **Push to repository** for CI/CD validation
4. **Deploy to Proxmox VE** for integration testing
5. **Release** only after Proxmox VE validation

### Code Organization
```
src/
├── common/          # Platform-independent code
├── oci/            # OCI runtime implementation  
├── proxmox/        # Proxmox VE specific code
└── platform/       # Platform-specific implementations
    ├── debian/     # Debian/Proxmox VE code
    └── mock/       # Development mocks
```

### Configuration Management
- **Development**: Mock Proxmox VE API calls
- **Testing**: Use development configuration
- **Production**: Real Proxmox VE integration

## Troubleshooting

### Common Issues

**Build Errors:**
```bash
# Clean build cache
rm -rf zig-cache zig-out
zig build
```

**Missing Dependencies:**
```bash
# Reinstall dependencies
sudo apt install --reinstall libseccomp-dev libsystemd-dev
```

**Permission Issues:**
```bash
# Fix permissions
sudo chown -R $USER:$USER .
```

### Getting Help

1. **Documentation**: Check `/docs` directory
2. **Issues**: GitHub Issues for bugs
3. **Discussions**: GitHub Discussions for questions
4. **Community**: Join our development community

---

**Remember**: Ubuntu is for development convenience only. Production deployment requires **Debian Linux** with **Proxmox VE**!
