# User Guide

## Overview

This user guide provides comprehensive instructions for using Proxmox LXCRI with the new OCI Image System. It covers installation, configuration, basic usage, and advanced features for container management.

## Table of Contents

1. [Installation](#installation)
2. [Configuration](#configuration)
3. [Basic Usage](#basic-usage)
4. [Image Management](#image-management)
5. [Container Operations](#container-operations)
6. [Advanced Features](#advanced-features)
7. [Troubleshooting](#troubleshooting)
8. [Examples](#examples)

## Installation

### Prerequisites

- **Operating System**: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Kernel**: Linux 5.0 or later
- **Zig Compiler**: Version 0.15.1 or later
- **Proxmox VE**: Version 7.0 or later (for full integration)
- **ZFS**: ZFS utilities and kernel modules
- **Storage**: Minimum 10GB available space

### System Requirements

- **CPU**: 2 cores minimum, 4+ cores recommended
- **Memory**: 4GB RAM minimum, 8GB+ recommended
- **Storage**: 10GB minimum, SSD recommended for performance
- **Network**: Network interface with internet access

### Installation Steps

#### 1. Clone Repository
```bash
git clone https://github.com/kubebsd/proxmox-lxcri.git
cd proxmox-lxcri
```

#### 2. Install Dependencies
```bash
# Install system dependencies
sudo apt update
sudo apt install -y build-essential zfsutils-linux

# Install Zig compiler (if not already installed)
wget https://ziglang.org/download/0.15.1/zig-linux-x86_64-0.15.1.tar.xz
tar -xf zig-linux-x86_64-0.15.1.tar.xz
sudo mv zig-linux-x86_64-0.15.1 /opt/
echo 'export PATH="/opt/zig-linux-x86_64-0.15.1:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### 3. Build Project
```bash
# Build the project
./zig-linux-x86_64-0.15.1/zig build

# Verify installation
./zig-out/bin/proxmox-lxcri --version
```

#### 4. Install System Service (Optional)
```bash
# Copy service file
sudo cp proxmox-lxcri.service /etc/systemd/system/

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable proxmox-lxcri
sudo systemctl start proxmox-lxcri
```

## Configuration

### Configuration Files

#### Main Configuration (`config.json`)
```json
{
  "proxmox": {
    "host": "192.168.1.100",
    "port": 8006,
    "username": "root@pam",
    "password": "your_password",
    "node": "pve-node-1"
  },
  "storage": {
    "type": "zfs",
    "pool": "tank",
    "dataset": "containers"
  },
  "network": {
    "bridge": "vmbr0",
    "vlan": null
  },
  "images": {
    "cache_size": 100,
    "storage_path": "/var/lib/proxmox-lxcri/images"
  }
}
```

#### Proxmox Configuration (`proxmox-config.json`)
```json
{
  "api": {
    "host": "192.168.1.100",
    "port": 8006,
    "username": "root@pam",
    "token_name": "proxmox-lxcri",
    "token_value": "your_api_token"
  },
  "cluster": {
    "enabled": true,
    "nodes": ["pve-node-1", "pve-node-2"]
  }
}
```

### Environment Variables

```bash
# Set environment variables
export PROXMOX_LXCRI_CONFIG="/etc/proxmox-lxcri/config.json"
export PROXMOX_LXCRI_LOG_LEVEL="info"
export PROXMOX_LXCRI_STORAGE_PATH="/var/lib/proxmox-lxcri"
```

## Basic Usage

### Command Structure

```bash
proxmox-lxcri [COMMAND] [OPTIONS] [ARGUMENTS]
```

### Available Commands

- `create` - Create a new container
- `start` - Start a container
- `stop` - Stop a container
- `delete` - Delete a container
- `list` - List containers
- `info` - Show container information
- `image` - Manage container images
- `exec` - Execute command in container
- `logs` - Show container logs

### Basic Container Operations

#### Create Container
```bash
# Create a basic container
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --memory 512 \
  --cores 1 \
  --storage zfs

# Create with custom configuration
proxmox-lxcri create \
  --name web-server \
  --image nginx:alpine \
  --memory 1024 \
  --cores 2 \
  --storage zfs \
  --network bridge=vmbr0 \
  --mount /host/path:/container/path \
  --env NODE_ENV=production
```

#### Start Container
```bash
# Start a container
proxmox-lxcri start my-container

# Start with specific options
proxmox-lxcri start my-container --detach --interactive
```

#### Stop Container
```bash
# Stop gracefully
proxmox-lxcri stop my-container

# Force stop
proxmox-lxcri stop my-container --force
```

#### List Containers
```bash
# List all containers
proxmox-lxcri list

# List with details
proxmox-lxcri list --format json

# List running containers only
proxmox-lxcri list --status running
```

## Image Management

### Working with OCI Images

#### Pull Image
```bash
# Pull from Docker Hub
proxmox-lxcri image pull ubuntu:22.04

# Pull from private registry
proxmox-lxcri image pull \
  --registry my-registry.com \
  --username myuser \
  --password mypass \
  myapp:latest
```

#### List Images
```bash
# List all images
proxmox-lxcri image list

# List with details
proxmox-lxcri image list --format json

# Show image layers
proxmox-lxcri image list --show-layers
```

#### Inspect Image
```bash
# Show image details
proxmox-lxcri image inspect ubuntu:22.04

# Show image configuration
proxmox-lxcri image inspect ubuntu:22.04 --config

# Show image layers
proxmox-lxcri image inspect ubuntu:22.04 --layers
```

#### Remove Image
```bash
# Remove image
proxmox-lxcri image remove ubuntu:22.04

# Force remove (even if used by containers)
proxmox-lxcri image remove ubuntu:22.04 --force
```

### Image Operations

#### Import Local Image
```bash
# Import from tar file
proxmox-lxcri image import my-image.tar

# Import from directory
proxmox-lxcri image import /path/to/image/directory

# Import with custom name
proxmox-lxcri image import my-image.tar --name myapp:latest
```

#### Export Image
```bash
# Export to tar file
proxmox-lxcri image export ubuntu:22.04 --output ubuntu-22.04.tar

# Export specific layers
proxmox-lxcri image export ubuntu:22.04 --layers --output ubuntu-layers.tar
```

## Container Operations

### Container Lifecycle

#### Create and Start
```bash
# Create and start in one command
proxmox-lxcri create \
  --name my-app \
  --image myapp:latest \
  --start

# Create with auto-start
proxmox-lxcri create \
  --name my-app \
  --image myapp:latest \
  --auto-start
```

#### Execute Commands
```bash
# Execute single command
proxmox-lxcri exec my-container ls -la

# Execute interactive shell
proxmox-lxcri exec my-container --interactive --tty /bin/bash

# Execute with specific user
proxmox-lxcri exec my-container --user root whoami
```

#### Container Logs
```bash
# Show container logs
proxmox-lxcri logs my-container

# Follow logs
proxmox-lxcri logs my-container --follow

# Show logs with timestamps
proxmox-lxcri logs my-container --timestamps

# Show last N lines
proxmox-lxcri logs my-container --tail 100
```

### Resource Management

#### Resource Limits
```bash
# Set memory limit
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --memory 1024 \
  --memory-swap 2048

# Set CPU limits
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --cores 2 \
  --cpu-shares 1024 \
  --cpu-quota 50000

# Set storage limits
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --storage-size 10G \
  --storage-type zfs
```

#### Network Configuration
```bash
# Bridge networking
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --network bridge=vmbr0

# Host networking
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --network host

# Custom network
proxmox-lxcri create \
  --name my-container \
  --image ubuntu:22.04 \
  --network custom=my-network
```

## Advanced Features

### LayerFS Operations

#### Layer Management
```bash
# Show layer information
proxmox-lxcri layer list

# Show layer dependencies
proxmox-lxcri layer dependencies ubuntu:22.04

# Validate layer integrity
proxmox-lxcri layer validate ubuntu:22.04

# Optimize layer access
proxmox-lxcri layer optimize ubuntu:22.04
```

#### Metadata Cache
```bash
# Show cache statistics
proxmox-lxcri cache stats

# Clear cache
proxmox-lxcri cache clear

# Show cache entries
proxmox-lxcri cache list

# Optimize cache
proxmox-lxcri cache optimize
```

### Performance Optimization

#### Parallel Processing
```bash
# Enable parallel layer processing
proxmox-lxcri config set parallel.processing true
proxmox-lxcri config set parallel.workers 4

# Show performance metrics
proxmox-lxcri performance metrics

# Run performance benchmark
proxmox-lxcri performance benchmark
```

#### Memory Management
```bash
# Show memory usage
proxmox-lxcri memory stats

# Optimize memory usage
proxmox-lxcri memory optimize

# Show memory leaks
proxmox-lxcri memory check
```

### ZFS Integration

#### ZFS Operations
```bash
# Create ZFS dataset
proxmox-lxcri zfs create tank/containers

# Show ZFS information
proxmox-lxcri zfs info

# Create snapshot
proxmox-lxcri zfs snapshot tank/containers@backup

# Clone dataset
proxmox-lxcri zfs clone tank/containers@backup tank/containers-clone
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check container status
proxmox-lxcri info my-container

# Check logs
proxmox-lxcri logs my-container

# Check system resources
proxmox-lxcri system resources

# Verify image integrity
proxmox-lxcri image validate myapp:latest
```

#### Image Pull Issues
```bash
# Check network connectivity
proxmox-lxcri network test

# Verify registry credentials
proxmox-lxcri registry auth

# Check image cache
proxmox-lxcri cache status

# Clear image cache
proxmox-lxcri cache clear
```

#### Performance Issues
```bash
# Check system performance
proxmox-lxcri performance check

# Monitor resource usage
proxmox-lxcri monitor

# Optimize configuration
proxmox-lxcri optimize
```

### Debug Mode

```bash
# Enable debug logging
export PROXMOX_LXCRI_LOG_LEVEL="debug"

# Run with verbose output
proxmox-lxcri --verbose create --name test ubuntu:22.04

# Show debug information
proxmox-lxcri debug info
```

## Examples

### Web Application Deployment

#### 1. Create Web Application Container
```bash
# Pull web application image
proxmox-lxcri image pull myapp:latest

# Create container
proxmox-lxcri create \
  --name web-app \
  --image myapp:latest \
  --memory 1024 \
  --cores 2 \
  --network bridge=vmbr0 \
  --port 8080:80 \
  --env NODE_ENV=production \
  --mount /var/log:/app/logs \
  --auto-start
```

#### 2. Scale Application
```bash
# Create multiple instances
for i in {1..3}; do
  proxmox-lxcri create \
    --name "web-app-$i" \
    --image myapp:latest \
    --memory 1024 \
    --cores 2 \
    --network bridge=vmbr0 \
    --port "808$i:80" \
    --env NODE_ENV=production \
    --auto-start
done
```

### Database Container

#### 1. Create Database Container
```bash
# Create PostgreSQL container
proxmox-lxcri create \
  --name postgres-db \
  --image postgres:15 \
  --memory 2048 \
  --cores 2 \
  --storage-size 20G \
  --env POSTGRES_PASSWORD=secret \
  --env POSTGRES_DB=myapp \
  --port 5432:5432 \
  --mount /var/lib/postgresql:/var/lib/postgresql/data \
  --auto-start
```

#### 2. Backup Database
```bash
# Create backup
proxmox-lxcri exec postgres-db \
  pg_dump -U postgres myapp > backup.sql

# Create ZFS snapshot
proxmox-lxcri zfs snapshot tank/containers/postgres-db@backup-$(date +%Y%m%d)
```

### Development Environment

#### 1. Create Development Container
```bash
# Create development container
proxmox-lxcri create \
  --name dev-env \
  --image ubuntu:22.04 \
  --memory 4096 \
  --cores 4 \
  --network bridge=vmbr0 \
  --mount /home/user/project:/app \
  --mount /home/user/.ssh:/root/.ssh \
  --port 2222:22 \
  --env DEBIAN_FRONTEND=noninteractive \
  --auto-start
```

#### 2. Install Development Tools
```bash
# Install development packages
proxmox-lxcri exec dev-env \
  apt update && apt install -y \
  build-essential \
  git \
  vim \
  curl \
  wget
```

## Conclusion

This user guide covers the essential aspects of using Proxmox LXCRI with the OCI Image System. The system provides powerful container management capabilities with advanced features like LayerFS, metadata caching, and ZFS integration.

For more detailed information, refer to:
- [API Documentation](api.md)
- [Architecture Documentation](architecture.md)
- [Testing Documentation](testing.md)
- [Development Guide](dev_guide.md)

For support and questions:
- Create an issue in the project repository
- Check the troubleshooting section
- Review the examples provided
- Consult the API documentation
