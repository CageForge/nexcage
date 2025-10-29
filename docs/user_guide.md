# User Guide

## Overview

This user guide provides comprehensive instructions for using Nexcage with the new OCI Image System. It covers installation, configuration, basic usage, and advanced features for container management.

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
git clone https://github.com/cageforge/nexcage.git
cd nexcage
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
./zig-out/bin/nexcage --version
```

#### 4. Install System Service (Optional)
```bash
# Copy service file
sudo cp nexcage.service /etc/systemd/system/

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable nexcage
sudo systemctl start nexcage
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
    "storage_path": "/var/lib/nexcage/images"
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
    "token_name": "nexcage",
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
export NEXCAGE_CONFIG="/etc/nexcage/config.json"
export NEXCAGE_LOG_LEVEL="info"
export NEXCAGE_STORAGE_PATH="/var/lib/nexcage"
```

## Basic Usage

### Command Structure

```bash
nexcage [COMMAND] [OPTIONS] [ARGUMENTS]
```

### Available Commands

- `create` - Create a new container
- `start` - Start a container
- `stop` - Stop a container
- `delete` - Delete a container
- `list` - List containers
- `state` - Show OCI-compatible container state
- `kill` - Send signal to a container

### Basic Container Operations

#### Create Container
```bash
# Create from OCI bundle directory (must contain config.json)
nexcage create \
  --name my-container \
  --image /path/to/oci-bundle
```

Signals and state:
```bash
# Send SIGTERM to a container
nexcage kill --name my-container --signal SIGTERM

# Get OCI state JSON
nexcage state --name my-container
```

#### Start Container
```bash
# Start a container
nexcage start my-container

# Start with specific options
nexcage start my-container --detach --interactive
```

#### Stop Container
```bash
# Stop gracefully
nexcage stop my-container

# Force stop
nexcage stop my-container --force
```

#### List Containers
```bash
# List all containers
nexcage list

# List with details
nexcage list --format json

# List running containers only
nexcage list --status running
```

## Image Management

### Working with Proxmox Templates and OCI Bundles

Images
-----
- For Proxmox LXC, use templates like `local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst` or a `.tar.zst` template file.
- Docker-style refs (e.g., `ubuntu:20.04`) are not fetched by Nexcage; use Proxmox templates or provide an OCI bundle directory with `config.json`.

### Working with OCI Images

#### Pull Image
```bash
# Pull from Docker Hub
nexcage image pull ubuntu:22.04

# Pull from private registry
nexcage image pull \
  --registry my-registry.com \
  --username myuser \
  --password mypass \
  myapp:latest
```

#### List Images
```bash
# List all images
nexcage image list

# List with details
nexcage image list --format json

# Show image layers
nexcage image list --show-layers
```

#### Inspect Image
```bash
# Show image details
nexcage image inspect ubuntu:22.04

# Show image configuration
nexcage image inspect ubuntu:22.04 --config

# Show image layers
nexcage image inspect ubuntu:22.04 --layers
```

#### Remove Image
```bash
# Remove image
nexcage image remove ubuntu:22.04

# Force remove (even if used by containers)
nexcage image remove ubuntu:22.04 --force
```

### Image Operations

#### Import Local Image
```bash
# Import from tar file
nexcage image import my-image.tar

# Import from directory
nexcage image import /path/to/image/directory

# Import with custom name
nexcage image import my-image.tar --name myapp:latest
```

#### Export Image
```bash
# Export to tar file
nexcage image export ubuntu:22.04 --output ubuntu-22.04.tar

# Export specific layers
nexcage image export ubuntu:22.04 --layers --output ubuntu-layers.tar
```

## Container Operations

### Container Lifecycle

#### Create and Start
```bash
# Create and start in one command
nexcage create \
  --name my-app \
  --image myapp:latest \
  --start

# Create with auto-start
nexcage create \
  --name my-app \
  --image myapp:latest \
  --auto-start
```

#### Execute Commands
```bash
# Execute single command
nexcage exec my-container ls -la

# Execute interactive shell
nexcage exec my-container --interactive --tty /bin/bash

# Execute with specific user
nexcage exec my-container --user root whoami
```

#### Container Logs
```bash
# Show container logs
nexcage logs my-container

# Follow logs
nexcage logs my-container --follow

# Show logs with timestamps
nexcage logs my-container --timestamps

# Show last N lines
nexcage logs my-container --tail 100
```

### Resource Management

#### Resource Limits
```bash
# Set memory limit
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --memory 1024 \
  --memory-swap 2048

# Set CPU limits
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --cores 2 \
  --cpu-shares 1024 \
  --cpu-quota 50000

# Set storage limits
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --storage-size 10G \
  --storage-type zfs
```

#### Network Configuration
```bash
# Bridge networking
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --network bridge=vmbr0

# Host networking
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --network host

# Custom network
nexcage create \
  --name my-container \
  --image ubuntu:22.04 \
  --network custom=my-network
```

## Advanced Features

### LayerFS Operations

#### Layer Management
```bash
# Show layer information
nexcage layer list

# Show layer dependencies
nexcage layer dependencies ubuntu:22.04

# Validate layer integrity
nexcage layer validate ubuntu:22.04

# Optimize layer access
nexcage layer optimize ubuntu:22.04
```

#### Metadata Cache
```bash
# Show cache statistics
nexcage cache stats

# Clear cache
nexcage cache clear

# Show cache entries
nexcage cache list

# Optimize cache
nexcage cache optimize
```

### Performance Optimization

#### Parallel Processing
```bash
# Enable parallel layer processing
nexcage config set parallel.processing true
nexcage config set parallel.workers 4

# Show performance metrics
nexcage performance metrics

# Run performance benchmark
nexcage performance benchmark
```

#### Memory Management
```bash
# Show memory usage
nexcage memory stats

# Optimize memory usage
nexcage memory optimize

# Show memory leaks
nexcage memory check
```

### ZFS Integration

#### ZFS Operations
```bash
# Create ZFS dataset
nexcage zfs create tank/containers

# Show ZFS information
nexcage zfs info

# Create snapshot
nexcage zfs snapshot tank/containers@backup

# Clone dataset
nexcage zfs clone tank/containers@backup tank/containers-clone
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check container status
nexcage info my-container

# Check logs
nexcage logs my-container

# Check system resources
nexcage system resources

# Verify image integrity
nexcage image validate myapp:latest
```

#### Image Pull Issues
```bash
# Check network connectivity
nexcage network test

# Verify registry credentials
nexcage registry auth

# Check image cache
nexcage cache status

# Clear image cache
nexcage cache clear
```

#### Performance Issues
```bash
# Check system performance
nexcage performance check

# Monitor resource usage
nexcage monitor

# Optimize configuration
nexcage optimize
```

### Debug Mode

```bash
# Enable debug logging
export NEXCAGE_LOG_LEVEL="debug"

# Run with verbose output
nexcage --verbose create --name test ubuntu:22.04

# Show debug information
nexcage debug info
```

## Examples

### Web Application Deployment

#### 1. Create Web Application Container
```bash
# Pull web application image
nexcage image pull myapp:latest

# Create container
nexcage create \
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
  nexcage create \
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
nexcage create \
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
nexcage exec postgres-db \
  pg_dump -U postgres myapp > backup.sql

# Create ZFS snapshot
nexcage zfs snapshot tank/containers/postgres-db@backup-$(date +%Y%m%d)
```

### Development Environment

#### 1. Create Development Container
```bash
# Create development container
nexcage create \
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
nexcage exec dev-env \
  apt update && apt install -y \
  build-essential \
  git \
  vim \
  curl \
  wget
```

## Conclusion

This user guide covers the essential aspects of using Nexcage with the OCI Image System. The system provides powerful container management capabilities with advanced features like LayerFS, metadata caching, and ZFS integration.

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
