# Proxmox LXCRI

A Container Runtime Interface (CRI) implementation for Proxmox LXC containers. This project allows Kubernetes to use Proxmox LXC containers as its container runtime.

## Features

- Full CRI implementation for Proxmox LXC
- Pod and container lifecycle management
- Configuration management
- Logging system
- Proxmox VE API integration
- Multi-host support with automatic failover
- Node caching to reduce API calls

## Requirements

- Zig 0.14.0 or later
- Proxmox VE 7.0 or later
- gRPC development libraries
- Protocol Buffers compiler

## Building

1. Install dependencies:

   ```bash
   # Ubuntu/Debian
   apt-get install protobuf-compiler libgrpc-dev libgrpc++-dev
   
   # macOS
   brew install protobuf grpc
   ```

2. Generate gRPC code:

   ```bash
   protoc --zig_out=. --grpc-zig_out=. proto/runtime_service.proto
   ```

3. Build the project:

   ```bash
   zig build
   ```

## Configuration

The configuration file can be placed in one of these locations:

1. Path specified in `PROXMOX_LXCRI_CONFIG` environment variable
2. `/etc/proxmox-lxcri/config.json`
3. `./config.json`

Example configuration:

```json
{
    "proxmox": {
        "hosts": ["host1.example.com", "host2.example.com", "host3.example.com"],
        "port": 8006,
        "token": "YOUR-API-TOKEN",
        "node": "your-node",
        "node_cache_duration": 60
    },
    "runtime": {
        "socket_path": "/var/run/proxmox-lxcri.sock",
        "log_level": "info",
        "default_memory": 512,
        "default_swap": 256,
        "default_cores": 1,
        "default_rootfs_size": "8G"
    }
}
```

## Usage

1. Start the LXCRI service:

   ```bash
   sudo ./proxmox-lxcri
   ```

2. Configure Kubernetes to use LXCRI:

   ```yaml
   # /etc/kubernetes/kubelet.conf
   apiVersion: kubelet.config.k8s.io/v1beta1
   kind: KubeletConfiguration
   containerRuntime: remote
   containerRuntimeEndpoint: unix:///var/run/proxmox-lxcri.sock
   ```

3. Restart kubelet:

   ```bash
   sudo systemctl restart kubelet
   ```

## Architecture

The project consists of several key components:

1. **CRI Service**: Implements the Container Runtime Interface
2. **Pod Manager**: Handles pod lifecycle
3. **Container Manager**: Manages container operations
4. **Proxmox Client**: Communicates with Proxmox VE API
5. **Configuration System**: Manages service configuration
6. **Logging System**: Handles logging and debugging

## CI/CD and Releases

This project uses GitHub Actions for continuous integration and deployment:

- **Linting**: Code formatting is checked using `zig fmt`
- **Testing**: Unit tests are run using `zig test`
- **Building**: AMD64 binaries are built for Linux
- **Releases**: Automated release process with GitHub Releases

For more information about the release process, see [RELEASE.md](RELEASE.md).

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License - see LICENSE file for details 