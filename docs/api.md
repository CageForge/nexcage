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

## OCI Image System API

### Layer Management

#### Create Layer
```zig
pub fn createLayer(
    allocator: std.mem.Allocator,
    media_type: []const u8,
    digest: []const u8,
    size: u64,
    annotations: ?std.StringHashMap([]const u8),
) !*Layer
```

Creates a new OCI image layer:
- `allocator`: Memory allocator
- `media_type`: OCI media type (e.g., "application/vnd.oci.image.layer.v1.tar")
- `digest`: SHA256 digest of the layer
- `size`: Size in bytes
- `annotations`: Optional key-value annotations
Returns a pointer to the created Layer.

#### Create Layer with Metadata
```zig
pub fn createLayerWithMetadata(
    allocator: std.mem.Allocator,
    media_type: []const u8,
    digest: []const u8,
    size: u64,
    annotations: ?std.StringHashMap([]const u8),
    created: ?[]const u8,
    author: ?[]const u8,
    comment: ?[]const u8,
    dependencies: ?[][]const u8,
    order: u32,
    storage_path: ?[]const u8,
    compressed: bool,
    compression_type: ?[]const u8,
) !*Layer
```

Creates a layer with full metadata support:
- `created`: ISO 8601 timestamp
- `author`: Layer author information
- `comment`: Layer description
- `dependencies`: Array of dependent layer digests
- `order`: Layer ordering in the image
- `storage_path`: Path to layer storage
- `compressed`: Whether layer is compressed
- `compression_type`: Type of compression used

#### Layer Validation
```zig
pub fn validate(self: *Layer, allocator: std.mem.Allocator) !void
```

Validates layer integrity and metadata:
- Checks media type validity
- Verifies digest format and length
- Validates size constraints
- Checks annotation validity
Throws `LayerError` on validation failure.

#### Layer Integrity Verification
```zig
pub fn verifyIntegrity(self: *Layer, allocator: std.mem.Allocator) !void
```

Verifies layer file integrity:
- Reads layer file from storage
- Calculates SHA256 hash
- Compares with stored digest
- Updates validation status
Throws `LayerError` on integrity failure.

### Layer Manager

#### Initialize Layer Manager
```zig
pub fn init(allocator: std.mem.Allocator) !*LayerManager
```

Creates a new Layer Manager instance:
- `allocator`: Memory allocator
Returns a pointer to the LayerManager.

#### Add Layer
```zig
pub fn addLayer(self: *Self, layer: *Layer) !void
```

Adds a layer to the manager:
- `layer`: Layer to add
Throws error if layer already exists or addition fails.

#### Get Layer
```zig
pub fn getLayer(self: *Self, digest: []const u8) ?*Layer
```

Retrieves a layer by digest:
- `digest`: SHA256 digest of the layer
Returns optional pointer to Layer.

#### Check Dependencies
```zig
pub fn checkCircularDependencies(self: *Self) !void
```

Validates layer dependency graph:
- Detects circular dependencies
- Ensures valid layer ordering
Throws `LayerError` on circular dependency detection.

#### Sort Layers by Dependencies
```zig
pub fn sortLayersByDependencies(self: *Self) ![][]const u8
```

Returns layers in dependency order:
- Performs topological sort
- Ensures base layers come first
- Returns array of layer digests in order

### LayerFS

#### Initialize LayerFS
```zig
pub fn init(allocator: std.mem.Allocator, base_path: []const u8) !*LayerFS
```

Creates a new LayerFS instance:
- `allocator`: Memory allocator
- `base_path`: Base directory for layer storage
Returns a pointer to the LayerFS.

#### Initialize with ZFS
```zig
pub fn initWithZFS(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    zfs_pool: []const u8,
    zfs_dataset: []const u8,
) !*LayerFS
```

Creates LayerFS with ZFS support:
- `zfs_pool`: ZFS pool name
- `zfs_dataset`: ZFS dataset name
Returns a pointer to the LayerFS with ZFS capabilities.

#### Add Layer
```zig
pub fn addLayer(self: *Self, layer: *Layer) !void
```

Adds a layer to the filesystem:
- `layer`: Layer to add
- Mounts layer in the filesystem
- Updates internal tracking

#### Create Mount Point
```zig
pub fn createMountPoint(self: *Self, path: []const u8) !void
```

Creates a mount point for layers:
- `path`: Mount point path
- Sets up overlay mount structure
- Configures namespace isolation

#### Garbage Collection
```zig
pub fn garbageCollect(self: *Self, allocator: std.mem.Allocator, force: bool) !GarbageCollectionResult
```

Performs garbage collection:
- `allocator`: Memory allocator
- `force`: Force cleanup of all unused resources
Returns result with cleanup statistics.

### Metadata Cache

#### Initialize Cache
```zig
pub fn init(allocator: std.mem.Allocator, max_entries: usize) MetadataCache
```

Creates a new metadata cache:
- `allocator`: Memory allocator
- `max_entries`: Maximum number of cache entries
Returns a new MetadataCache instance.

#### Get Entry
```zig
pub fn get(self: *Self, digest: []const u8) ?*MetadataCacheEntry
```

Retrieves a cache entry:
- `digest`: Layer digest
Returns optional pointer to cache entry.

#### Put Entry
```zig
pub fn put(self: *Self, digest: []const u8, entry: *MetadataCacheEntry) !void
```

Stores a cache entry:
- `digest`: Layer digest
- `entry`: Cache entry to store
- Automatically evicts LRU entries if needed

### Layer Object Pool

#### Initialize Pool
```zig
pub fn init(allocator: std.mem.Allocator, max_pool_size: u32) LayerObjectPool
```

Creates a new object pool:
- `allocator`: Memory allocator
- `max_pool_size`: Maximum number of objects in pool
Returns a new LayerObjectPool instance.

#### Get Layer
```zig
pub fn getLayer(self: *Self) !*Layer
```

Retrieves a layer from the pool:
- Creates new layer if pool is empty
- Returns pointer to Layer

#### Return Layer
```zig
pub fn returnLayer(self: *Self, layer: *Layer) void
```

Returns a layer to the pool:
- `layer`: Layer to return
- Resets layer state
- Adds to available pool

### Parallel Processing Context

#### Initialize Context
```zig
pub fn init(allocator: std.mem.Allocator, max_workers: u32) ParallelProcessingContext
```

Creates a parallel processing context:
- `allocator`: Memory allocator
- `max_workers`: Maximum number of worker threads
Returns a new ParallelProcessingContext instance.

#### Process Layers in Parallel
```zig
pub fn processLayersParallel(
    self: *Self,
    layers: [][]const u8,
    processor: fn([]const u8) anyerror!void,
) !void
```

Processes layers using multiple threads:
- `layers`: Array of layer digests
- `processor`: Function to process each layer
- Automatically distributes work across workers

### Image Manager

#### Initialize Image Manager
```zig
pub fn init(
    allocator: std.mem.Allocator,
    umoci_path: []const u8,
    images_dir: []const u8,
) !*ImageManager
```

Creates a new Image Manager instance:
- `allocator`: Memory allocator
- `umoci_path`: Path to umoci tool
- `images_dir`: Directory for image storage
Returns a pointer to the ImageManager.

#### Create Container from Image
```zig
pub fn createContainerFromImage(
    self: *Self,
    image_name: []const u8,
    image_tag: []const u8,
    container_id: []const u8,
    bundle_path: []const u8,
) !void
```

Creates a container from an OCI image:
- `image_name`: Name of the image
- `image_tag`: Image tag/version
- `container_id`: ID for the new container
- `bundle_path`: Path for container bundle
- Automatically validates image and sets up LayerFS

### Error Types

#### Layer Errors
```zig
pub const LayerError = error{
    InvalidMediaType,
    InvalidDigest,
    InvalidSize,
    InvalidAnnotations,
    ValidationFailed,
    IntegrityCheckFailed,
    DependencyError,
    StorageError,
};
```

#### LayerFS Errors
```zig
pub const LayerFSError = error{
    InitializationFailed,
    MountFailed,
    UnmountFailed,
    StorageError,
    ZFSError,
    NamespaceError,
    GarbageCollectionFailed,
};
```

### Usage Examples

#### Creating and Managing Layers
```zig
// Create a basic layer
var layer = try Layer.createLayer(
    allocator,
    "application/vnd.oci.image.layer.v1.tar",
    "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
    1024,
    null,
);
defer layer.deinit(allocator);

// Validate the layer
try layer.validate(allocator);

// Add to layer manager
var manager = try LayerManager.init(allocator);
defer manager.deinit();
try manager.addLayer(layer);
```

#### Using LayerFS
```zig
// Initialize LayerFS
var layerfs = try LayerFS.init(allocator, "/var/lib/containers");
defer layerfs.deinit();

// Add layers
try layerfs.addLayer(layer);

// Create mount points
try layerfs.createMountPoint("/mnt/container");

// Run garbage collection
const gc_result = try layerfs.garbageCollect(allocator, false);
defer gc_result.deinit(allocator);
```

#### Using Metadata Cache
```zig
// Initialize cache
var cache = MetadataCache.init(allocator, 100);

// Store entry
const entry = try allocator.create(MetadataCacheEntry);
entry.* = .{ /* ... */ };
try cache.put("sha256:...", entry);

// Retrieve entry
const cached = cache.get("sha256:...");
```

#### Container Creation from Image
```zig
// Initialize image manager
var manager = try ImageManager.init(allocator, "/usr/bin/umoci", "/var/lib/images");
defer manager.deinit();

// Create container from image
try manager.createContainerFromImage(
    "ubuntu",
    "22.04",
    "my-container",
    "/var/lib/containers/my-container"
);
```