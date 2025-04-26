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
  * Image configuration
Returns a pointer to the created Pod or an error.

#### Create StatefulSet Pod
```zig
pub fn createStatefulPod(
    self: *Self, 
    config: types.StatefulSetConfig, 
    ordinal: u32
) !*StatefulPodIdentity
```

Creates a new StatefulSet Pod with stable network identity:
- `config`: StatefulSet configuration including:
  * Set name and service name
  * Network configuration with headless service
  * Pod prefix for naming
- `ordinal`: Pod index in the StatefulSet
Returns the pod's stable identity information.

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

## Network Manager API

### Bridge Management

#### Create Deployment Bridge
```zig
pub fn createDeploymentBridge(
    self: *Self,
    config: BridgeConfig,
) !void
```

Creates a new bridge for a Deployment:
- `config`: Bridge configuration including:
  * Name and deployment ID
  * MTU and VLAN settings
  * STP configuration

#### Configure Bridge Security
```zig
pub fn configureBridgeSecurity(
    self: *Self,
    deployment_id: []const u8,
) !void
```

Configures security settings for a deployment bridge:
- `deployment_id`: Deployment identifier
Enables VLAN filtering, multicast snooping, and isolation.

### StatefulSet Networking

#### Setup StatefulSet Networking
```zig
pub fn setupStatefulSetNetworking(
    self: *Self,
    config: StatefulSetConfig,
) !void
```

Sets up networking for a StatefulSet:
- `config`: StatefulSet configuration including:
  * Headless service settings
  * Persistent address configuration
  * DNS policy

#### Setup Headless Service
```zig
pub fn setupHeadlessService(
    self: *Self,
    config: StatefulSetConfig,
) !void
```

Creates and configures a headless service:
- `config`: Service configuration
Creates DNS zone and configures service discovery.

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
- `config`: Image configuration including:
  * Format (ZFS/Raw)
  * Storage options
Returns path to prepared image.

#### Convert Image
```zig
pub fn convertImage(
    self: *Self,
    source: []const u8,
    format: ImageFormat
) !void
```

Converts image to specified format:
- `source`: Source image path
- `format`: Target format (ZFS/Raw)

#### Cache Management
```zig
pub fn prepareImageFromCache(
    self: *Self,
    image_info: ImageInfo
) !ImageId
```

Retrieves or downloads image using cache:
- `image_info`: Image metadata
Returns cached image ID or downloads new one.

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
    BridgeCreationFailed,
    BridgeNotFound,
    HeadlessServiceFailed,
    NetworkIdentityError,
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
    CacheError,
    ReferenceCountError,
};
```

## Usage Examples

### Creating a StatefulSet Pod
```zig
// StatefulSet configuration
const statefulset_config = StatefulSetConfig{
    .name = "web",
    .service_name = "nginx",
    .replicas = 3,
    .pod_prefix = "web",
    .network = .{
        .headless_service = true,
        .persistent_addresses = true,
    },
};

// Create pod with stable identity
const pod_identity = try pod_manager.createStatefulPod(statefulset_config, 0);
```

### Setting up Deployment Bridge
```zig
// Create bridge for deployment
try network_manager.createDeploymentBridge(.{
    .name = "web-deployment",
    .deployment_id = "web-app",
    .mtu = 1500,
    .stp = true,
});

// Configure bridge security
try network_manager.configureBridgeSecurity("web-app");
```

### Using Image Cache
```zig
// Prepare image using cache
const image_info = ImageInfo{
    .name = "ubuntu",
    .version = "22.04",
    .hash = "sha256:...",
};

const image_id = try image_manager.prepareImageFromCache(image_info);
``` 