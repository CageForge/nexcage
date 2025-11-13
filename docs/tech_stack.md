# Nexcage Technical Stack

This document describes the technical stack used in the Nexcage project, including versions, features, and reasons for technology selection.

## Core Technologies

### 1. Zig Programming Language
- **Version**: 0.15.1+
- **Features**:
  - Memory safety
  - Zero-cost abstractions
  - Cross-compilation
  - Built-in testing
- **Why Zig?**
  - Performance and safety
  - Modern tooling
  - Active community
  - Good C interoperability

### 2. Proxmox VE
- **Version**: 7.4+
- **Features**:
  - LXC container support
  - ZFS storage backend
  - REST API
  - Web interface
- **Why Proxmox VE?**
  - Enterprise-grade virtualization
  - ZFS integration
  - Active development
  - Good documentation

### 3. containerd
- **Version**: 1.7+
- **Features**:
  - OCI runtime support
  - Image management
  - Container lifecycle
  - Plugin architecture
- **Why containerd?**
  - Industry standard
  - Kubernetes integration
  - Active development
  - Good community support

## Storage

### 1. ZFS
- **Version**: 2.1+
- **Features**:
  - Copy-on-write
  - Snapshots
  - Compression
  - Deduplication
- **Why ZFS?**
  - Data integrity
  - Performance
  - Enterprise features
  - Linux integration

## Networking

### 1. Linux Network Stack
- **Components**:
  - Network namespaces
  - Virtual Ethernet
  - iptables/nftables
  - Routing
- **Why Linux Network?**
  - Native support
  - Performance
  - Flexibility
  - Security

### 2. Open vSwitch
- **Version**: 2.15+
- **Features**:
  - Virtual switching
  - OpenFlow support
  - Network virtualization
  - Performance
- **Why OVS?**
  - Enterprise features
  - Performance
  - Kubernetes integration
  - Active development

## Security

### 1. Linux Security Modules
- **Components**:
  - SELinux
  - AppArmor
  - Seccomp
  - Capabilities
- **Why LSM?**
  - Mandatory access control
  - Process isolation
  - Resource limits
  - Industry standard

### 2. Linux Capabilities
- **Features**:
  - Fine-grained permissions
  - Process isolation
  - Security boundaries
  - Resource control
- **Why Capabilities?**
  - Security
  - Flexibility
  - Performance
  - Standardization

## Development Tools

### 1. Zig Build System
- **Features**:
  - Dependency management
  - Cross-compilation
  - Testing
  - Documentation
- **Why Zig Build?**
  - Simplicity
  - Performance
  - Integration
  - Modern features

### 2. Testing Tools
- **Components**:
  - Zig test runner
  - Integration tests
  - Performance tests
  - Security tests
- **Why Zig Tests?**
  - Built-in support
  - Performance
  - Reliability
  - Integration

### 3. Debugging Tools
- **Components**:
  - GDB
  - LLDB
  - strace
  - perf
- **Why these tools?**
  - Industry standard
  - Performance
  - Features
  - Integration

## Monitoring

### 1. Metrics Collection
- **Components**:
  - VictoriaMetrics
  - Grafana
  - Node Exporter
  - Custom exporters
- **Why these tools?**
  - Industry standard
  - Performance
  - Features
  - Integration

### 2. Logging
- **Components**:
  - Journald
  - VictoriaLogs
  - Grafana
- **Why these tools?**
  - Performance
  - Features
  - Integration
  - Scalability

## CI/CD

### 1. GitHub Actions
- **Version**: Latest
- **Features**:
  - Workflow automation
  - Matrix builds
  - Artifact storage
  - Security scanning
- **Why GitHub Actions?**
  - Integration
  - Features
  - Performance
  - Community

### 2. Docker
- **Version**: 24.0+
- **Features**:
  - Containerization
  - Build automation
  - Image management
  - Registry support
- **Why Docker?**
  - Industry standard
  - Performance
  - Features
  - Community
