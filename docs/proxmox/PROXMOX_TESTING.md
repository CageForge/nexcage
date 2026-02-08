# Proxmox Testing Guide

This document provides comprehensive information about testing the Nexcage runtime project on Proxmox VE servers.

## Overview

The project includes specialized testing for Proxmox VE environments:

- **Proxmox E2E Tests**: End-to-end testing on Proxmox VE server
- **Container Lifecycle Tests**: LXC, OCI, and VM container testing
- **Performance Tests**: Performance testing on Proxmox hardware
- **Integration Tests**: Proxmox API and PCT CLI integration
- **Remote Testing**: SSH-based testing on remote Proxmox servers

## Test Environment

### Proxmox Server Configuration

- **Host**: `your-proxmox.server`
- **User**: `root`
- **Binary Path**: `/usr/local/bin`
- **Config Path**: `/etc/nexcage`
- **Log Path**: `/var/log/nexcage`

### Prerequisites

1. **SSH Access**: Configured SSH key access to Proxmox server
2. **Proxmox VE**: Version 7.0 or later
3. **LXC Tools**: `pct`, `lxc-*` commands available
4. **Storage**: ZFS storage pool configured
5. **Network**: Bridge interfaces available

## Running Proxmox Tests

### Quick Start

```bash
# Run Proxmox E2E tests
make test-proxmox

# Run all tests including Proxmox
make test-all
```

### Manual Test Execution

```bash
# Proxmox E2E tests with reporting
./scripts/proxmox_e2e_test.sh

# Direct execution
make test-proxmox
```

### Test Configuration

Tests can be configured through environment variables:

```bash
# Proxmox test configuration
export PVE_HOST="root@your-proxmox.server"
export PVE_PATH="/usr/local/bin"
export CONFIG_PATH="/etc/nexcage"
export LOG_PATH="/var/log/nexcage"

# Test reporting
export REPORT_DIR="./test-reports"
export VERBOSE=true
export DEBUG=true
```

## Test Structure

### Proxmox Only Test Suite

The Proxmox Only test suite includes:

1. **Build Tests**: Binary building and deployment
2. **Environment Tests**: Proxmox server environment validation
3. **Remote Tests**: Testing on Proxmox server
4. **Container Tests**: LXC, OCI, and VM container testing
5. **Performance Tests**: Performance and memory testing
6. **Error Handling**: Error handling and recovery testing

### Test Categories

#### **Build Tests (3 tests)**
- Build binary
- Copy binary to PVE
- Copy config to PVE

#### **Environment Tests (4 tests)**
- PVE environment check
- PVE LXC tools check
- PVE storage check
- PVE network check

#### **Remote Tests (18 tests)**
- Remote help commands
- Remote version command
- Remote create/start/stop/delete/list/run help
- Remote command execution
- Error handling tests
- Config loading tests

#### **Container Tests (15 tests)**
- LXC container lifecycle (create, start, stop, delete)
- OCI container lifecycle (crun, runc)
- VM creation and management
- Container listing and status

#### **Performance Tests (3 tests)**
- Performance testing
- Memory usage testing
- Error handling testing

## Test Results

### Current Test Status

**Proxmox Only Test Results:**
- **Total Tests**: 44
- **Passed**: 28 (63%)
- **Failed**: 16 (37%)
- **Skipped**: 0 (0%)
- **Success Rate**: 63%

### Test Categories Results

#### **Local Tests**: 60% success rate
- ✅ Build and basic commands work
- ❌ Some help commands fail (known issue)

#### **Remote Tests**: 60% success rate
- ✅ SSH connectivity works
- ✅ Remote command execution works
- ❌ Some help commands fail (known issue)

#### **Container Tests**: 50% success rate
- ✅ Container creation works
- ✅ Container listing works
- ❌ Container start/stop/delete fail (implementation issue)

#### **Performance Tests**: 100% success rate
- ✅ Performance testing works
- ✅ Memory usage testing works
- ✅ Error handling works

## Test Reports

### Report Structure

Each Proxmox test run generates detailed reports including:

- **Summary**: Test counts, success rates, duration
- **Individual Results**: Per-test status, duration, memory usage
- **Environment Info**: Proxmox server info, OS, architecture
- **Error Details**: Failure reasons and stack traces
- **Performance Metrics**: Memory usage, execution time

### Report Locations

- **Proxmox E2E Tests**: `test-reports/proxmox_e2e_test_report_*.md`
- **Combined Summary**: `test-reports/proxmox_combined_summary.md`
- **Test Logs**: `test-reports/*.log`

### Viewing Reports

```bash
# View latest Proxmox report
make report-view

# Generate summary
make report

# Clean old reports
make report-clean
```

## GitHub Actions Integration

### Proxmox Test Workflows

The project includes specialized GitHub Actions workflows for Proxmox testing:

- **`proxmox_tests.yml`**: Main Proxmox E2E testing
- **`proxmox-container-tests`**: Container lifecycle testing
- **`proxmox-performance-tests`**: Performance testing
- **`generate-proxmox-summary`**: Combined reporting

### Workflow Features

- **SSH Key Management**: Secure SSH access to Proxmox server
- **Automated Testing**: All test suites run automatically
- **Detailed Reporting**: Test results uploaded as artifacts
- **PR Comments**: Test results posted to pull requests
- **Artifact Storage**: Reports stored for 30 days

### Workflow Configuration

```yaml
# .github/workflows/proxmox_tests.yml
name: Proxmox E2E Tests
on:
  push:
    branches: [ main, develop, feature/**, feat/** ]
  pull_request:
    branches: [ main, develop ]
  workflow_dispatch:
```

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**
   ```bash
   # Check SSH connectivity
   ssh root@mgr.cp.if.ua "pct help"
   
   # Verify SSH key
   ssh-add -l
   ```

2. **Proxmox Environment Issues**
   ```bash
   # Check Proxmox tools
   ssh root@mgr.cp.if.ua "which pct lxc-ls"
   
   # Check storage
   ssh root@mgr.cp.if.ua "df -h | grep rpool"
   
   # Check network
   ssh root@mgr.cp.if.ua "ip link show | grep vmbr"
   ```

3. **Container Creation Failures**
   ```bash
   # Check LXC tools
   ssh root@mgr.cp.if.ua "pct list"
   
   # Check storage space
   ssh root@mgr.cp.if.ua "zfs list"
   
   # Check network bridges
   ssh root@mgr.cp.if.ua "ip link show"
   ```

### Debug Mode

```bash
# Enable debug logging
export DEBUG=true
export VERBOSE=true

# Run tests with debug output
make test-proxmox
```

### Log Files

Test logs are stored in:
- **Proxmox Tests**: `test-reports/proxmox_e2e_test_log_*.log`
- **Container Tests**: `test-reports/container_test_log_*.log`
- **Performance Tests**: `test-reports/performance_test_log_*.log`

## Best Practices

### Test Development

1. **Test Isolation**: Each test should be independent
2. **Resource Cleanup**: Always clean up created containers
3. **Error Handling**: Test both success and failure cases
4. **Performance**: Consider test execution time
5. **Documentation**: Document test purpose and expected behavior

### Proxmox Specific

1. **VMID Management**: Use unique VMIDs for containers
2. **Storage Management**: Clean up created storage
3. **Network Management**: Use appropriate bridge interfaces
4. **Resource Limits**: Set appropriate resource limits
5. **Security**: Follow Proxmox security best practices

### Reporting

1. **Detailed Information**: Include Proxmox server info
2. **Clear Results**: Use consistent formatting
3. **Error Details**: Include Proxmox-specific error messages
4. **Performance Metrics**: Track Proxmox resource usage

## Security Considerations

### SSH Security

1. **Key Management**: Use strong SSH keys
2. **Access Control**: Limit SSH access to necessary users
3. **Audit Logging**: Monitor SSH access
4. **Key Rotation**: Regularly rotate SSH keys

### Proxmox Security

1. **User Permissions**: Use appropriate user permissions
2. **Resource Limits**: Set resource limits for containers
3. **Network Security**: Use appropriate network configurations
4. **Storage Security**: Secure storage access

## Performance Optimization

### Test Performance

1. **Parallel Execution**: Run tests in parallel where possible
2. **Resource Management**: Monitor resource usage
3. **Timeout Handling**: Set appropriate timeouts
4. **Cleanup**: Clean up resources promptly

### Proxmox Performance

1. **Storage Performance**: Use appropriate storage types
2. **Network Performance**: Optimize network configurations
3. **CPU Performance**: Monitor CPU usage
4. **Memory Performance**: Monitor memory usage

## Contributing

### Adding Proxmox Tests

1. **Create Test File**: Add new test file in appropriate directory
2. **Update Test Runner**: Add test to Proxmox test runner
3. **Update Documentation**: Document new test in this guide
4. **Test Coverage**: Ensure adequate test coverage

### Test Standards

1. **Code Quality**: Follow project coding standards
2. **Documentation**: Include comprehensive comments
3. **Error Handling**: Proper error handling and cleanup
4. **Performance**: Consider performance impact of tests

## Resources

- **Proxmox VE**: [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- **LXC**: [LXC Documentation](https://linuxcontainers.org/lxc/)
- **PCT**: [Proxmox Container Toolkit](https://pve.proxmox.com/wiki/Manual:_pct)
- **ZFS**: [ZFS Documentation](https://openzfs.org/wiki/Main_Page)
- **SSH**: [SSH Documentation](https://www.openssh.com/manual.html)

## Support

For Proxmox testing-related issues:

1. **Check Logs**: Review test logs for error details
2. **Run Individual Tests**: Isolate failing tests
3. **Check Environment**: Verify Proxmox server configuration
4. **Create Issue**: Report bugs with test details and logs

---

**Last Updated**: 2025-10-04  
**Version**: 0.5.0  
**Maintainer**: Proxmox LXC Runtime Interface Team
