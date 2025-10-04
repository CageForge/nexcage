# Proxmox LXC Runtime Interface (proxmox-lxcri)

A modern container runtime interface for Proxmox VE that supports both LXC and OCI containers with intelligent backend routing.

## Features

- **Multi-Backend Support**: LXC, OCI crun, and OCI runc backends
- **Intelligent Routing**: Automatic backend selection based on container name patterns
- **Proxmox Integration**: Native integration with Proxmox VE via `pct` CLI
- **OCI Compliance**: Support for OCI container specifications
- **Modern Architecture**: Clean separation of concerns with modular design

## Quick Start

### Prerequisites

- Proxmox VE server with `pct` CLI installed
- Zig 0.13.0 or later
- Linux system with required dependencies

### Installation

1. Clone the repository:
```bash
git clone https://github.com/kubebsd/proxmox-lxcri.git
cd proxmox-lxcri
```

2. Build the project:
```bash
zig build
```

3. Install to system:
```bash
sudo cp zig-out/bin/proxmox-lxcri /usr/local/bin/
sudo cp config.json /etc/proxmox-lxcri/
```

### Configuration

Edit `/etc/proxmox-lxcri/config.json`:

```json
{
    "proxmox": {
        "pct_path": "/usr/bin/pct",
        "node": "your-node-name",
        "timeout": 30
    },
    "container_config": {
        "crun_name_patterns": ["kube-ovn-*", "cilium-*"],
        "default_container_type": "lxc"
    }
}
```

## Usage

### Create Container
```bash
# LXC container (default)
proxmox-lxcri create --name my-app ubuntu:20.04

# OCI container (matches kube-ovn-* pattern)
proxmox-lxcri create --name kube-ovn-pod ubuntu:20.04
```

### Manage Container
```bash
# Start container
proxmox-lxcri start my-app

# Stop container
proxmox-lxcri stop my-app

# Delete container
proxmox-lxcri delete my-app
```

## Architecture

### Backend Routing

The system automatically selects the appropriate backend based on container name patterns:

- **OCI Backends**: Containers matching `kube-ovn-*` or `cilium-*` patterns
- **LXC Backend**: All other containers (default)

### Module Structure

```
src/
├── core/           # Core functionality and types
├── cli/            # Command-line interface
├── backends/       # Backend implementations
│   ├── lxc/        # LXC backend
│   ├── crun/       # OCI crun backend
│   └── runc/       # OCI runc backend
└── oci/            # OCI specification support
```

## Development

### Building

```bash
# Debug build
zig build

# Release build
zig build -Doptimize=ReleaseFast
```

### Testing

The project includes comprehensive testing with detailed reporting:

```bash
# Run all tests with detailed reporting
make test

# Run specific test suites
make test-unit      # Unit tests only
make test-e2e       # E2E tests only
make test-proxmox   # Proxmox E2E tests only
make test-ci        # CI tests only
make test-all       # All test suites

# View test reports
make report-view
make report-clean
```

**Test Coverage:**
- **Unit Tests**: Individual component testing
- **Integration Tests**: Component interaction testing
- **E2E Tests**: End-to-end functionality testing
- **Proxmox Tests**: Proxmox VE server testing (mgr.cp.if.ua)
- **CI Tests**: Continuous integration testing

**Test Reports:**
- Detailed Markdown reports with timing and memory usage
- Color-coded output for easy reading
- Automated GitHub Actions integration
- PR comments with test results

**CI/CD Pipeline:**
- **Self-Hosted Runner**: Proxmox server as GitHub Actions runner
- **Automatic Testing**: Tests run directly on Proxmox server after each commit
- **Deployment**: Automatic deployment to Proxmox server on main branch
- **Monitoring**: Server health and application status monitoring
- **Reporting**: Detailed reports and artifacts for each workflow run

For detailed testing information, see:
- [TESTING.md](TESTING.md) - General testing guide
- [PROXMOX_TESTING.md](PROXMOX_TESTING.md) - Proxmox-specific testing
- [CI_CD_SETUP.md](CI_CD_SETUP.md) - GitHub CI/CD setup guide
- [SELF_HOSTED_RUNNER.md](SELF_HOSTED_RUNNER.md) - Self-hosted runner setup guide

### Adding New Backends

1. Create backend driver in `src/backends/<name>/`
2. Implement required methods: `create`, `start`, `stop`, `delete`
3. Add to `src/backends/mod.zig`
4. Update CLI commands to handle new backend type
5. Add routing logic in `core/config.zig`

## Configuration Reference

### Proxmox Settings
- `pct_path`: Path to `pct` CLI executable
- `node`: Proxmox node name
- `timeout`: Command timeout in seconds

### Container Configuration
- `crun_name_patterns`: Array of patterns for OCI crun backend
- `default_container_type`: Default backend type (lxc, crun, runc)

### Runtime Settings
- `log_level`: Logging level (debug, info, warn, error)
- `log_path`: Path to log file
- `root_path`: Root directory for container data

## Troubleshooting

### Common Issues

1. **Segmentation Fault**: Known issue with ArrayList in LXC driver, workaround implemented
2. **Command Not Found**: Ensure `pct` is in PATH or update `pct_path` in config
3. **Permission Denied**: Run with appropriate permissions for Proxmox operations

### Debug Mode

Enable debug logging:
```bash
proxmox-lxcri create --name test ubuntu:20.04 --debug
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Roadmap

- [x] CLI refactoring and OCI backend support
- [x] Backend routing implementation
- [x] E2E testing framework
- [ ] Full OCI container functionality
- [ ] Performance optimizations
- [ ] Additional backend support
- [ ] Container orchestration features

## Support

For issues and questions:
- Create an issue on GitHub
- Check the documentation in `Roadmap/`
- Review the architecture documentation

## Changelog

### v0.5.0 (Current)
- CLI refactoring completed
- OCI backend support added
- Backend routing implemented
- E2E testing framework

### v0.4.0
- Initial Proxmox integration
- LXC backend implementation
- Basic CLI commands