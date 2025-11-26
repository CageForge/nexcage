# Testing Guide

This document provides comprehensive information about testing the Nexcage Runtime project.

## Overview

The project includes multiple testing layers with detailed reporting:

- **Unit Tests**: Individual component testing
- **Integration Tests**: Component interaction testing
- **E2E Tests**: End-to-end functionality testing
- **CI Tests**: Continuous integration testing
- **Performance Tests**: Performance and memory testing
- **Security Tests**: Security vulnerability testing

## Test Structure

```
tests/
├── all_tests.zig              # Main test runner
├── test_runner.zig            # Enhanced test runner with reporting
├── comprehensive_test.zig     # Comprehensive test suite
├── config_test.zig           # Configuration testing
├── memory/                   # Memory leak testing
├── performance/              # Performance testing
├── security/                 # Security testing
├── oci/                      # OCI runtime testing
├── integration/              # Integration testing
├── lxc/                      # LXC backend testing
├── proxmox/                  # Proxmox API testing
└── ...

scripts/
├── proxmox_e2e_test.sh       # Proxmox E2E test runner
├── proxmox_only_test.sh      # Proxmox-only test runner
├── check_dependencies.sh     # Dependency checker
├── bump_version.sh            # Version bumping
└── archive/                   # Archived scripts (one-time setup, old test runners)

test-reports/                 # Generated test reports
├── unit_test_report_*.md     # Unit test reports
├── e2e_test_report_*.md      # E2E test reports
├── ci_test_report_*.md       # CI test reports
└── summary.md                # Combined summary
```

## Running Tests

### Quick Start

```bash
# Run all tests with detailed reporting
make test

# Run specific test suites
make test-unit    # Unit tests only
make test-e2e     # E2E tests only
make test-ci      # CI tests only
make test-all     # All test suites
```

### Manual Test Execution

```bash
# Proxmox E2E tests
./scripts/proxmox_e2e_test.sh

# Proxmox-only tests
./scripts/proxmox_only_test.sh

# Direct test execution
zig build test
zig run tests/test_runner.zig
```

**Note**: Legacy test reporting scripts have been archived to `scripts/archive/`. Use the Makefile commands or direct Zig test execution instead.

### Test Configuration

Tests can be configured through environment variables:

```bash
# E2E test configuration
export PVE_HOST="root@mgr.cp.if.ua"
export PVE_PATH="/usr/local/bin"
export CONFIG_PATH="/etc/nexcage"
export LOG_PATH="/var/log/nexcage"

# Test reporting
export REPORT_DIR="./test-reports"
export VERBOSE=true
export DEBUG=true
```

## Test Reports

### Report Structure

Each test run generates detailed reports including:

- **Summary**: Test counts, success rates, duration
- **Individual Results**: Per-test status, duration, memory usage
- **Environment Info**: OS, architecture, Zig version
- **Error Details**: Failure reasons and stack traces
- **Performance Metrics**: Memory usage, execution time

### Report Locations

- **Unit Tests**: `test-reports/unit_test_report_YYYYMMDD_HHMMSS.md`
- **E2E Tests**: `test-reports/e2e_test_report_YYYYMMDD_HHMMSS.md`
- **CI Tests**: `test-reports/ci_test_report_YYYYMMDD_HHMMSS.md`
- **Combined Summary**: `test-reports/summary.md`

### Viewing Reports

```bash
# View latest report
make report-view

# Generate summary
make report

# Clean old reports
make report-clean
```

## Test Types

### Unit Tests

Test individual components in isolation:

```bash
# Run unit tests
make test-unit

# Specific test files
zig run tests/config_test.zig
zig run tests/memory/memory_leak_test.zig
zig run tests/performance/optimized_performance_test.zig
```

**Coverage:**
- Configuration loading and validation
- Memory management and leak detection
- Error handling and recovery
- Data structure operations
- Utility functions

### Integration Tests

Test component interactions:

```bash
# Run integration tests
zig run tests/integration/end_to_end_test.zig
zig run tests/integration/container_lifecycle_test.zig
zig run tests/integration/test_concurrency.zig
```

**Coverage:**
- Backend routing and selection
- CLI command execution
- API client interactions
- Container lifecycle management
- Error propagation

### E2E Tests

Test complete workflows:

```bash
# Run E2E tests
make test-e2e

# Manual E2E testing (Proxmox)
./scripts/proxmox_e2e_test.sh
```

**Coverage:**
- Complete container lifecycle (create → start → stop → delete)
- Remote Proxmox server testing
- Configuration validation
- Error handling and recovery
- Performance under load

### CI Tests

Test continuous integration scenarios:

```bash
# Manual CI testing (via Makefile)
make test-ci
```

**Coverage:**
- Build process validation
- Binary functionality
- Command-line interface
- Error handling
- Environment compatibility

## Test Environment

### Prerequisites

```bash
# Install dependencies
make deps

# Or manually
sudo apt-get update
sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
```

### Local Testing

```bash
# Build project
make build

# Run tests
make test

# Check results
make report-view
```

### Remote Testing

```bash
# Configure remote host
export PVE_HOST="root@your-proxmox-server"

# Run E2E tests
make test-e2e
```

## Continuous Integration

### GitHub Actions

The project includes comprehensive CI workflows:

- **CI with Reports**: `ci_with_reports.yml`
- **Simple CI**: `simple-ci.yml`
- **Legacy CI**: `ci.yml`

### CI Features

- **Automated Testing**: All test suites run on push/PR
- **Detailed Reporting**: Test results uploaded as artifacts
- **PR Comments**: Test results posted to pull requests
- **Artifact Storage**: Reports stored for 30 days
- **Multi-Platform**: Tests run on Ubuntu, with plans for other platforms

### CI Configuration

```yaml
# .github/workflows/ci_with_reports.yml
name: CI with Detailed Reports
on:
  push:
    branches: [ main, develop, feature/**, feat/** ]
  pull_request:
    branches: [ main, develop ]
```

## Performance Testing

### Memory Testing

```bash
# Run memory leak tests
zig run tests/memory/memory_leak_test.zig

# Performance tests
zig run tests/performance/optimized_performance_test.zig
```

### Performance Metrics

- **Memory Usage**: Track memory consumption and leaks
- **Execution Time**: Measure command execution duration
- **Resource Utilization**: Monitor CPU and disk usage
- **Scalability**: Test with multiple containers

## Security Testing

### Security Tests

```bash
# Run security tests
zig run tests/security/test_security.zig
```

### Security Coverage

- **Input Validation**: Test malicious input handling
- **Permission Checks**: Verify access control
- **Resource Limits**: Test resource exhaustion scenarios
- **Error Handling**: Ensure secure error reporting

## Troubleshooting

### Common Issues

1. **Build Failures**
   ```bash
   # Clean and rebuild
   make clean
   make build
   ```

2. **Test Failures**
   ```bash
   # Check logs
   make report-view
   
   # Run specific test
   zig run tests/specific_test.zig
   ```

3. **E2E Test Failures**
   ```bash
   # Check remote connection
   ssh $PVE_HOST "pct help"
   
   # Verify configuration
   cat config.json
   ```

### Debug Mode

```bash
# Enable debug logging
export DEBUG=true
export VERBOSE=true

# Run tests with debug output
make test
```

### Log Files

Test logs are stored in:
- **Unit Tests**: `test-reports/unit_test_log_*.log`
- **E2E Tests**: `test-reports/e2e_test_log_*.log`
- **CI Tests**: `test-reports/ci_test_log_*.log`

## Best Practices

### Writing Tests

1. **Test Isolation**: Each test should be independent
2. **Clear Naming**: Use descriptive test names
3. **Error Handling**: Test both success and failure cases
4. **Resource Cleanup**: Always clean up resources
5. **Documentation**: Document test purpose and expected behavior

### Test Organization

1. **Group Related Tests**: Use test suites for related functionality
2. **Separate Concerns**: Unit tests vs integration tests
3. **Mock Dependencies**: Use mocks for external dependencies
4. **Test Data**: Use consistent test data and fixtures

### Reporting

1. **Detailed Information**: Include context and environment info
2. **Clear Results**: Use consistent formatting and status indicators
3. **Error Details**: Include stack traces and error messages
4. **Performance Metrics**: Track execution time and resource usage

## Contributing

### Adding Tests

1. **Create Test File**: Add new test file in appropriate directory
2. **Update Test Runner**: Add test to test runner if needed
3. **Update Documentation**: Document new test in this guide
4. **Test Coverage**: Ensure adequate test coverage

### Test Standards

1. **Code Quality**: Follow project coding standards
2. **Documentation**: Include comprehensive comments
3. **Error Handling**: Proper error handling and cleanup
4. **Performance**: Consider performance impact of tests

## Resources

- **Zig Testing**: [Zig Test Documentation](https://ziglang.org/documentation/master/#Zig-Test)
- **GitHub Actions**: [GitHub Actions Documentation](https://docs.github.com/en/actions)
- **Proxmox API**: [Proxmox API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- **OCI Runtime**: [OCI Runtime Specification](https://github.com/opencontainers/runtime-spec)

## Support

For testing-related issues:

1. **Check Logs**: Review test logs for error details
2. **Run Individual Tests**: Isolate failing tests
3. **Check Environment**: Verify dependencies and configuration
4. **Create Issue**: Report bugs with test details and logs

---

**Last Updated**: 2025-11-13
**Version**: 0.7.5
**Maintainer**: CageForge Team
