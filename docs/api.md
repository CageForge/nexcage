# API Documentation

## Pod Manager API

### Initialization
```zig
pub fn init(
    allocator: std.mem.Allocator,
    proxmox_client: *proxmox.Client,
    network_manager: *network.NetworkManager,
    storage_path: []const u8,
) !PodManager
```

Initializes a new Pod Manager instance with the following parameters:
- `allocator`: Memory allocator for resource management
- `proxmox_client`: Proxmox API client instance
- `network_manager`: Network manager instance
- `storage_path`: Path for storage operations

### Pod Operations

#### Create Pod
```zig
pub fn createPod(self: *Self, config: types.PodConfig) !*Pod
```

Creates a new Pod with the specified configuration:
- `config`: Pod configuration including:
  * ID and name
  * Network settings
  * Resource limits
  * Storage configuration
Returns a pointer to the created Pod or an error.

#### Delete Pod
```zig
pub fn deletePod(self: *Self, id: []const u8) !void
```

Deletes a Pod with the specified ID:
- `id`: Pod identifier
Throws an error if Pod not found or deletion fails.

#### Get Pod
```zig
pub fn getPod(self: *Self, id: []const u8) ?*Pod
```

Retrieves a Pod by ID:
- `id`: Pod identifier
Returns optional pointer to Pod.

#### List Pods
```zig
pub fn listPods(self: *Self) ![]const *Pod
```

Returns an array of pointers to all existing Pods.

## Pod API

### Pod Lifecycle

#### Start Pod
```zig
pub fn start(self: *Self) !void
```

Starts the Pod and its containers:
- Configures network
- Sets up resources
- Starts LXC container

#### Stop Pod
```zig
pub fn stop(self: *Self) !void
```

Stops the Pod and its containers:
- Stops LXC container
- Cleans up network configuration

#### Update Resources
```zig
pub fn updateResources(self: *Self, resources: types.ResourceConfig) !void
```

Updates Pod resource configuration:
- `resources`: New resource limits and requests

## Network Manager API

### DNS Configuration
```zig
pub fn configureDNS(
    self: *Self,
    servers: []const []const u8,
    search: []const []const u8,
    options: []const []const u8
) !void
```

Configures DNS settings for a Pod:
- `servers`: DNS server addresses
- `search`: Search domains
- `options`: Additional DNS options

### Port Forwarding
```zig
pub fn addPortForward(
    self: *Self,
    mapping: types.PortMapping
) !void
```

Adds port forwarding rule:
- `mapping`: Port mapping configuration

## Image Manager API

### Image Operations

#### Prepare Image
```zig
pub fn prepareImage(
    self: *Self,
    url: []const u8,
    config: ImageConfig
) ![]const u8
```

Prepares container image:
- `url`: Image source URL
- `config`: Image configuration
Returns path to prepared image.

#### Mount Image
```zig
pub fn mountImage(
    self: *Self,
    image_path: []const u8,
    mount_point: []const u8,
    config: ImageConfig
) !void
```

Mounts container image:
- `image_path`: Path to image
- `mount_point`: Mount destination
- `config`: Mount configuration

## Error Types

### Pod Errors
```zig
pub const PodError = error{
    PodCreationFailed,
    PodDeletionFailed,
    PodStartFailed,
    PodStopFailed,
    PodListFailed,
    NetworkSetupFailed,
    NetworkCleanupFailed,
    ResourceUpdateFailed,
    PodAlreadyExists,
    PodNotFound,
    PodStillRunning,
    InvalidState,
};
```

### Network Errors
```zig
pub const NetworkError = error{
    ConfigurationFailed,
    PortForwardingFailed,
    DNSConfigurationFailed,
};
```

### Image Errors
```zig
pub const ImageError = error{
    DownloadFailed,
    ExtractFailed,
    ConversionFailed,
    MountFailed,
    InvalidFormat,
    StorageError,
    ZFSError,
};
```

## Usage Examples

### Creating and Starting a Pod
```zig
// Initialize managers
var pod_manager = try PodManager.init(allocator, proxmox_client, network_manager);
defer pod_manager.deinit();

// Create Pod configuration
const pod_config = PodConfig{
    .id = "test-pod",
    .name = "Test Pod",
    .namespace = "default",
    .network = NetworkConfig{...},
    .resources = ResourceConfig{...},
};

// Create and start Pod
const pod = try pod_manager.createPod(pod_config);
try pod.start();
```

### Network Configuration
```zig
// Configure DNS
try network_manager.configureDNS(
    &[_][]const u8{"8.8.8.8", "8.8.4.4"},
    &[_][]const u8{"example.com"},
    &[_][]const u8{},
);

// Add port forwarding
try network_manager.addPortForward(.{
    .protocol = .tcp,
    .container_port = 80,
    .host_port = 8080,
});
``` 