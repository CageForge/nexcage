# Debug Logging Guide

## Overview

Nexcage has an advanced logging system that allows detailed tracking of command execution, problem diagnosis, and performance analysis. The system supports DEBUG mode, file logging, and detailed execution time logging.

## Key Features

### 1. DEBUG Mode
- Detailed system information
- Logging of all operations
- Command execution tracing
- Runtime environment information

### 2. File Logging
- Writing logs to file
- Simultaneous console and file output
- Log preservation for further analysis

### 3. Performance Measurement
- Command execution time in milliseconds
- Detailed operation information
- Execution stage tracing

## Usage

### Basic Usage

```bash
# Normal mode
./nexcage list

# DEBUG mode
./nexcage --debug list

# DEBUG mode with file logging
./nexcage --debug --log-file /tmp/nexcage-debug.log list

# File logging only (without DEBUG)
./nexcage --log-file /tmp/nexcage.log list
```

### Advanced Options

```bash
# Set logging level
./nexcage --log-level debug list

# Combined options
./nexcage --debug --log-file /var/log/nexcage.log --log-level info create --name test-container --image ubuntu:20.04
```

## Log Levels

| Level | Description | Usage |
|-------|-------------|-------|
| `trace` | Most detailed logging | Internal operations, loops |
| `debug` | Detailed logging | Diagnostics, development |
| `info` | General information | Normal usage |
| `warn` | Warnings | Potential problems |
| `error` | Errors | Critical errors |
| `fatal` | Critical errors | System failures |

## Log Structure

### Log Format
```
[timestamp] LEVEL component: message
```

### DEBUG Log Example
```
[1760799760] INFO  nexcage: Starting nexcage v0.13.0
[1760799760] DEBUG nexcage: System Information:
[1760799760] DEBUG nexcage:   OS: linux
[1760799760] DEBUG nexcage:   Architecture: x86_64
[1760799760] DEBUG nexcage:   Target: native
[1760799760] DEBUG nexcage:   Zig version: 0.15.1
[1760799760] INFO  nexcage: Starting command: list
[1760799760] DEBUG nexcage: Command execution environment:
[1760799760] DEBUG nexcage:   Debug mode: enabled
[1760799760] DEBUG nexcage:   Log file: none
[1760799760] DEBUG nexcage:   Timestamp: 1760799760
[1760799760] INFO  nexcage: Command 'list' completed in 3ms
[1760799760] INFO  nexcage: Command 'list' completed successfully
```

## Troubleshooting

### 1. Container Issues

#### Container Not Created
```bash
# Enable DEBUG mode for detailed logging
./nexcage --debug create --name test-container --image ubuntu:20.04 2> /tmp/create-debug.log

# Check logs
cat /tmp/create-debug.log
```

**Common Issues:**
- Missing OCI bundle
- Incorrect image path
- Permission problems
- Missing dependencies

#### Container Not Starting
```bash
# Startup diagnostics
./nexcage --debug start --name test-container

# Check status
./nexcage --debug list
```

**Common Issues:**
- Container doesn't exist
- Configuration problems
- Missing resources

### 2. Performance Issues

#### Slow Command Execution
```bash
# Measure execution time
./nexcage --debug --log-file /tmp/perf.log list

# Analyze logs
grep "completed in" /tmp/perf.log
```

**Optimization:**
- Check network connection
- Analyze resource usage
- Check system configuration

### 3. Logging Issues

#### Logs Not Created
```bash
# Check permissions
ls -la /tmp/nexcage-debug.log

# Check directory availability
mkdir -p /var/log/nexcage
./nexcage --log-file /var/log/nexcage/debug.log list
```

#### Formatting Issues
```bash
# Check encoding
file /tmp/nexcage-debug.log

# The log file holds no color codes: they are written only to a terminal
cat /tmp/nexcage-debug.log
```

## Usage Scenarios

### 1. Development and Testing

```bash
# Full logging for development
export NEXCAGE_DEBUG=1
export NEXCAGE_LOG_FILE=/tmp/dev.log
./nexcage --debug create --name dev-container --image ubuntu:20.04
```

### 2. Production Diagnostics

```bash
# Minimal logging for production
./nexcage --log-file /var/log/nexcage/prod.log --log-level warn create --name prod-container --image ubuntu:20.04
```

### 3. Performance Analysis

```bash
# Logging with time measurement
./nexcage --debug --log-file /tmp/perf-analysis.log list
./nexcage --debug --log-file /tmp/perf-analysis.log create --name perf-test --image ubuntu:20.04
./nexcage --debug --log-file /tmp/perf-analysis.log start --name perf-test

# Analyze results
grep "completed in" /tmp/perf-analysis.log | sort -k8 -n
```

### 4. Network Problem Diagnostics

```bash
# Logging network operations
./nexcage --debug create --name net-test --image ubuntu:20.04 2> /tmp/network-debug.log
```

## Configuration Priority

nexcage uses a priority system for logging configuration, where higher priority sources override lower priority ones:

### Priority Order (Highest to Lowest)
1. **Command Line Arguments** - Highest priority
2. **Environment Variables** - Medium priority  
3. **Configuration File** - Low priority
4. **Default Values** - Lowest priority

A level of `info` on the command line or in `NEXCAGE_LOG_LEVEL` (or an unknown level, which is read as `info`) counts as unset, so it does not override a level set by a lower priority source. No source turns DEBUG mode off once another has turned it on.

### Command Line Arguments
```bash
# Override all other settings
./nexcage --debug --log-file /tmp/debug.log --log-level trace list
```

### Environment Variables
```bash
# Override config file and defaults
export NEXCAGE_DEBUG=1
export NEXCAGE_LOG_FILE=/var/log/nexcage/debug.log
export NEXCAGE_LOG_LEVEL=debug
./nexcage list
```

### Configuration File
```json
{
  "log_level": "debug",
  "log_file": "/var/log/nexcage/nexcage.log"
}
```

#### Configuration File Locations
nexcage searches for configuration files in the following order:
1. `./config.json` (current directory)
2. `/etc/nexcage/config.json`
3. `/etc/nexcage/nexcage.json`

#### Configuration File Example
```json
{
  "log_level": "debug",
  "log_file": "/var/log/nexcage/nexcage.log",
  "network": {
    "bridge": "vmbr0"
  }
}
```

## Environment Variables

| Variable | Description | Values |
|----------|-------------|--------|
| `NEXCAGE_DEBUG` | Enable DEBUG mode | `1` or `true` |
| `NEXCAGE_LOG_FILE` | Log file path | `/path/to/logfile` |
| `NEXCAGE_LOG_LEVEL` | Logging level | `trace`, `debug`, `info`, `warn`, `error`, `fatal` |
| `NEXCAGE_PERF_TRACKING` | Read, but has no effect: a command's time is logged whenever DEBUG mode or a log file is on, if the command succeeds | `1` or `true` |
| `NEXCAGE_MEMORY_TRACKING` | Read, but has no effect: nothing tracks memory | `1` or `true` |

## Log Analysis Examples

### 1. Error Search
```bash
# Find all errors (commands write them to stderr, not to the --log-file)
./nexcage --debug list 2>&1 | grep "ERROR"

# Find warnings
./nexcage --debug list 2>&1 | grep "WARN"
```

### 2. Performance Analysis
```bash
# Command execution time
grep "completed in" /tmp/nexcage-debug.log

# Slowest operations
grep "completed in" /tmp/nexcage-debug.log | sort -k8 -n -r | head -10
```

### 3. Operation Tracing
```bash
# All operations with container
grep "test-container" /tmp/nexcage-debug.log

# Create operations
grep "Starting command: create" /tmp/nexcage-debug.log
```

## Configuration for Different Environments

### Development
```bash
# Maximum logging
export NEXCAGE_DEBUG=1
export NEXCAGE_LOG_LEVEL=trace
```

### Staging
```bash
# Medium level logging
export NEXCAGE_LOG_LEVEL=debug
export NEXCAGE_LOG_FILE=/var/log/nexcage/staging.log
```

### Production
```bash
# Minimal logging
export NEXCAGE_LOG_LEVEL=warn
export NEXCAGE_LOG_FILE=/var/log/nexcage/production.log
```

## Recommendations

### 1. Log Size
- Regularly clean old logs
- Use logrotate for automatic rotation
- Set maximum log file size

### 2. Security
- Don't log sensitive data (passwords, tokens)
- Restrict access to log files
- Use secure paths for logs

### 3. Performance
- DEBUG mode may affect performance
- Use file logging only when needed
- Monitor log size

## Common Problems and Solutions

### 1. "not found in PATH" Errors
```bash
# Check command availability
./nexcage --debug list 2>&1 | grep -i "not found in PATH"

# Solution: run nexcage on a Proxmox VE host, which provides pct and pvesh
```

### 2. Permission Problems
```bash
# nexcage needs root on the Proxmox host
sudo ./nexcage --debug list
```

### 3. Network Problems
```bash
# Network diagnostics
./nexcage --debug create --name net-test --image ubuntu:20.04 2>&1 | grep -i network
```

## Monitoring System Integration

### 1. Prometheus
```bash
# Export performance metrics
grep "completed in" /var/log/nexcage/production.log | tr -d "'" | \
  awk '{print "nexcage_command_duration_seconds{command=\""$5"\"} " $8/1000}' > /var/lib/prometheus/nexcage.prom
```

### 2. ELK Stack
```bash
# Configure Filebeat to send logs to Elasticsearch
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/nexcage/*.log
  fields:
    service: nexcage
```

### 3. Grafana
```bash
# Dashboard for performance monitoring
# Use queries like:
# rate(nexcage_command_duration_seconds[5m])
# histogram_quantile(0.95, rate(nexcage_command_duration_seconds_bucket[5m]))
```

## Testing Results

### Configuration Priority Testing

The configuration priority system has been thoroughly tested with the following scenarios:

#### Test 1: Configuration File Priority
```bash
# Test with config.json containing debug settings
./nexcage list
```
**Result**: ✅ DEBUG mode enabled, logs written to `/tmp/nexcage-logs/nexcage.log`
- System information logged
- Command execution time tracked (6ms)
- File logging working correctly

#### Test 2: Command Line Override
```bash
# Override config file settings via command line
./nexcage --debug --log-file /tmp/override.log list
```
**Result**: ✅ Command line arguments override config file
- DEBUG mode enabled
- Log file changed to `/tmp/override.log`
- Command execution time tracked (6ms)

#### Test 3: Environment Variable Override
```bash
# Override via environment variables
NEXCAGE_LOG_FILE=/tmp/env-test.log NEXCAGE_LOG_LEVEL=warn ./nexcage list
```
**Result**: ✅ Environment variables partially override config file
- Log file changed to `/tmp/env-test.log`
- DEBUG mode still enabled (from config file)
- Command execution time tracked (5ms)

### Performance Metrics

| Test Scenario | Execution Time | Log File | DEBUG Mode | Status |
|---------------|----------------|----------|------------|--------|
| Config file only | 6ms | `/tmp/nexcage-logs/nexcage.log` | ✅ Enabled | ✅ Pass |
| Command line override | 6ms | `/tmp/override.log` | ✅ Enabled | ✅ Pass |
| Environment override | 5ms | `/tmp/env-test.log` | ✅ Enabled | ✅ Pass |

### Memory Management

Debug and ReleaseSafe builds (release binaries are ReleaseSafe) print an `error(gpa): memory address ... leaked` report to stderr when a command exits without freeing memory; the report does not change the exit status. The three scenarios above report none, and tests/sim/run.sh fails if any command it runs prints one. Giving `--log-file` or `--log` more than once still leaks the earlier path.

### Log File Verification

All test scenarios successfully created log files with proper content:
- Timestamp formatting: `[1760801308]`
- Log levels: `INFO`, `DEBUG`
- System information logging
- Command execution tracking
- Performance metrics

## Summary

The nexcage debug logging system provides powerful tools for:
- Problem diagnostics
- Performance analysis
- Command execution tracing
- System monitoring

Use the appropriate logging level for your environment and regularly analyze logs to optimize system performance.
