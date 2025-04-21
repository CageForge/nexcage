# Pod Lifecycle Management

## Overview

This document describes the complete lifecycle of a Pod in the Proxmox LXC Container Runtime Interface, with a detailed focus on the Pod deletion process.

## Pod States

```
Created -> Running -> Stopped -> Deleted
```

### State Descriptions

1. **Created**
   - Initial state after Pod creation
   - Resources allocated
   - Network configured
   - Container created but not started

2. **Running**
   - Container is active
   - Network is operational
   - Resources are in use
   - Monitoring active

3. **Stopped**
   - Container is inactive
   - Resources still allocated
   - Network rules maintained
   - Can be restarted

4. **Deleted**
   - Resources released
   - Network rules removed
   - Storage cleaned up
   - Pod removed from manager

## Pod Deletion Process

### 1. Deletion Request Flow
```
CRI-O -> Runtime Service -> Pod Manager -> Proxmox API -> Resource Cleanup
```

### 2. Pre-deletion Checks
```zig
pub fn deletePod(self: *Self, id: []const u8) !void {
    // Verify Pod exists
    const pod = self.pods.get(id) orelse return error.PodNotFound;
    
    // Check Pod state
    if (pod.state == .Running) {
        try pod.stop();
    }
}
```

### 3. Resource Cleanup Sequence

#### a. Network Cleanup
```zig
// Remove port forwarding rules
for (self.config.network.port_mappings) |mapping| {
    try self.proxmox_client.removePortForward(self.config.id, .{
        .proto = mapping.protocol,
        .dport = mapping.host_port,
    });
}

// Clean up DNS configuration
try self.network_manager.cleanupDNS(self.config.id);

// Remove network namespace
try self.network_manager.removeNamespace(self.config.id);
```

#### b. Storage Management
```zig
// Unmount container rootfs
try self.image_manager.unmountImage(self.config.id);

// Note: Storage is not immediately cleaned up
// Images are cached and reused for future Pods with the same image and version
// Actual cleanup is handled by the garbage collector when:
// 1. Disk space is low
// 2. Image is no longer referenced
// 3. New version of the image is available
```

#### c. Container Cleanup
```zig
// Remove LXC container via Proxmox API
try self.proxmox_client.deleteContainer(self.config.id);
```

### 4. Manager State Update
```zig
// Remove Pod from manager's state
_ = self.pods.remove(id);
```

## Storage Management Strategy

### 1. Image Caching
- Images are preserved after Pod deletion
- Cached images are reused for new Pods
- Cache key: image name + version
- Reduces disk I/O and network bandwidth

### 2. Garbage Collection
The garbage collector runs independently and handles:
- Monitoring disk space usage
- Tracking image reference counts
- Cleaning unused images when space is needed
- Version management of cached images

### 3. Storage Cleanup Triggers
Storage cleanup occurs only when:
```zig
pub const StorageCleanupTrigger = enum {
    LowDiskSpace,      // Available space below threshold
    NewImageVersion,   // Old version can be removed
    ManualCleanup,     // Explicit cleanup request
};
```

### 4. Cache Management
```zig
pub const ImageCache = struct {
    // Track image usage
    pub fn incrementReferenceCount(image_id: []const u8) void {
        // Increment number of Pods using this image
    }

    pub fn decrementReferenceCount(image_id: []const u8) void {
        // Decrement number of Pods using this image
        // Note: Image is not immediately removed when count reaches 0
    }

    // Check if image exists in cache
    pub fn hasImage(name: []const u8, version: []const u8) bool {
        // Return true if image is cached
    }
};
```

## Error Handling During Deletion

### 1. Common Errors
```zig
pub const DeletionError = error{
    PodNotFound,
    PodStillRunning,
    NetworkCleanupFailed,
    UnmountFailed,
    ContainerRemovalFailed,
};

pub const CacheError = error{
    ImageNotFound,
    CacheCorrupted,
    ReferenceCountError,
};
```

### 2. Error Recovery Strategies

#### Network Cleanup Failure
```zig
fn cleanupNetwork(self: *Self) !void {
    // Attempt to remove port forwarding rules
    for (self.port_rules) |rule| {
        self.removePortForward(rule) catch |err| {
            log.warn("Failed to remove port forward rule: {}", .{err});
            // Continue cleanup despite error
        };
    }
    
    // Attempt to remove network namespace
    self.removeNamespace() catch |err| {
        log.err("Failed to remove network namespace: {}", .{err});
        return error.NetworkCleanupFailed;
    };
}
```

#### Image Unmount Failure
```zig
fn unmountImage(self: *Self) !void {
    // Unmount container rootfs
    os.unmount(self.mount_path) catch |err| {
        log.err("Failed to unmount container rootfs: {}", .{err});
        return error.UnmountFailed;
    };
    
    // Update image reference count
    self.image_cache.decrementReferenceCount(self.image_id) catch |err| {
        log.warn("Failed to update image reference count: {}", .{err});
        // Continue despite reference count error
    };
}
```

#### Storage Cleanup Failure
```
```

## Image Caching and Garbage Collection

### 1. Image Caching Strategy
- Images are cached and reused for Pods with matching image name and version
- Reference counting tracks image usage
- Cache entries include:
  - Image metadata (name, version, hash)
  - Reference count
  - Last access time
  - Size on disk

### 2. Garbage Collection Process
- Runs periodically or when disk space is low
- Cleanup criteria:
  - Zero reference count
  - Not accessed for configured time period
  - Disk space usage above threshold
- Cleanup order:
  1. Unreferenced images
  2. Oldest accessed images
  3. Largest images

### 3. Cache Management Example
```zig
pub fn prepareImage(self: *ImageCache, image_info: ImageInfo) !ImageId {
    // Check if image exists in cache
    if (self.findImage(image_info)) |cached_image| {
        try self.incrementReferenceCount(cached_image.id);
        return cached_image.id;
    }
    
    // Download and cache new image
    const image_id = try self.downloadAndCache(image_info);
    try self.incrementReferenceCount(image_id);
    
    // Run garbage collection if needed
    if (try self.shouldRunGC()) {
        self.runGarbageCollection() catch |err| {
            log.warn("Garbage collection failed: {}", .{err});
            // Continue despite GC failure
        };
    }
    
    return image_id;
}
```

## Best Practices

### 1. Pre-deletion Verification
- Always verify Pod exists
- Check Pod state
- Validate resource status

### 2. Graceful Shutdown
- Stop containers before deletion
- Allow time for processes to terminate
- Save any necessary state

### 3. Resource Cleanup Order
1. Stop running processes
2. Remove network configuration
3. Unmount filesystems
4. Update reference counts
5. Update manager state

### 4. Error Handling
- Log all cleanup attempts
- Continue cleanup despite partial failures
- Report final status

## Usage Example

```zig
// Delete a Pod with proper error handling
pub fn deletePodSafely(pod_id: []const u8) !void {
    // Get Pod
    var pod = pod_manager.getPod(pod_id) orelse {
        log.warn("Pod {s} not found", .{pod_id});
        return error.PodNotFound;
    };
    
    // Stop if running
    if (pod.state == .Running) {
        pod.stop() catch |err| {
            log.err("Failed to stop pod: {}", .{err});
            return error.PodStopFailed;
        };
    }
    
    // Cleanup resources
    pod.cleanup() catch |err| {
        log.err("Failed to cleanup pod: {}", .{err});
        return error.CleanupFailed;
    };
    
    // Delete Pod
    try pod_manager.deletePod(pod_id);
    
    log.info("Pod {s} successfully deleted", .{pod_id});
}
```

## Image Storage and Conversion

### 1. Image Format Conversion
```zig
pub const ImageFormat = enum {
    ZFS,    // ZFS dataset format
    Raw,    // Raw filesystem format for LXC
};

pub fn convertImage(self: *ImageManager, source: []const u8, format: ImageFormat) !void {
    switch (format) {
        .ZFS => try self.convertToZFS(source),
        .Raw => try self.convertToRaw(source),
    }
}

fn convertToZFS(self: *Self, source: []const u8) !void {
    // Create new ZFS dataset
    const dataset_name = try std.fmt.allocPrint(
        self.allocator,
        "rpool/lxc/{}",
        .{self.image_id}
    );
    defer self.allocator.free(dataset_name);

    try self.zfs.createDataset(dataset_name);
    
    // Mount dataset temporarily
    const mount_path = try self.getMountPath();
    try self.zfs.mount(dataset_name, mount_path);
    defer self.zfs.unmount(dataset_name) catch {};
    
    // Copy image content to dataset
    try self.copyImageContent(source, mount_path);
}

fn convertToRaw(self: *Self, source: []const u8) !void {
    // Create sparse file for raw filesystem
    const raw_path = try std.fmt.allocPrint(
        self.allocator,
        "/var/lib/lxc/images/{}.raw",
        .{self.image_id}
    );
    defer self.allocator.free(raw_path);
    
    // Create filesystem in raw file
    try self.createFilesystem(raw_path);
    
    // Mount raw file
    const mount_path = try self.getMountPath();
    try self.mountRaw(raw_path, mount_path);
    defer self.unmountRaw(mount_path) catch {};
    
    // Copy image content
    try self.copyImageContent(source, mount_path);
}
```

### 2. Storage Strategy Selection
```zig
pub const StorageConfig = struct {
    format: ImageFormat,
    options: union(ImageFormat) {
        ZFS: struct {
            pool_name: []const u8,
            dataset_options: struct {
                compression: bool = true,
                dedup: bool = false,
            },
        },
        Raw: struct {
            size_mb: u32,
            fs_type: []const u8 = "ext4",
        },
    },
};

pub fn selectStorageStrategy(self: *Self, config: StorageConfig) !void {
    // Configure storage based on format
    switch (config.format) {
        .ZFS => {
            const opts = config.options.ZFS;
            try self.setupZFSStorage(opts);
        },
        .Raw => {
            const opts = config.options.Raw;
            try self.setupRawStorage(opts);
        },
    }
}
```

### 3. Mount Management
```zig
pub fn mountImage(self: *Self, image_id: []const u8, target: []const u8) !void {
    const image = try self.getImage(image_id);
    
    switch (image.format) {
        .ZFS => {
            // Mount ZFS dataset
            const dataset = try self.getDatasetPath(image_id);
            try self.zfs.mount(dataset, target);
        },
        .Raw => {
            // Mount raw filesystem
            const raw_path = try self.getRawPath(image_id);
            try self.mountRaw(raw_path, target);
        },
    }
}

pub fn unmountImage(self: *Self, image_id: []const u8) !void {
    const image = try self.getImage(image_id);
    
    switch (image.format) {
        .ZFS => try self.zfs.unmount(try self.getDatasetPath(image_id)),
        .Raw => try self.unmountRaw(try self.getMountPath(image_id)),
    }
}
```

## Network Configuration During Pod Creation

### 1. Network Initialization Process
```zig
pub const NetworkConfig = struct {
    ip_config: IpConfig,
    bridge: []const u8,
    veth_pair: VethPair,
    dns: DnsConfig,
    mtu: u32 = 1500,
};

pub const IpConfig = union(enum) {
    Static: struct {
        address: []const u8,
        netmask: []const u8,
        gateway: []const u8,
    },
    DHCP: struct {
        hostname: ?[]const u8 = null,
        client_id: ?[]const u8 = null,
    },
};

pub fn setupNetworking(self: *NetworkManager, pod_id: []const u8, config: NetworkConfig) !void {
    // Create network namespace for the Pod
    try self.createNetworkNamespace(pod_id);
    
    // Setup veth pair
    try self.setupVethPair(pod_id, config.veth_pair);
    
    // Attach to bridge
    try self.attachToBridge(config.veth_pair.host, config.bridge);
    
    // Configure IP based on method
    switch (config.ip_config) {
        .Static => |static| try self.configureStaticIP(pod_id, static),
        .DHCP => |dhcp| try self.configureDHCP(pod_id, dhcp),
    }
    
    // Setup DNS
    try self.configureDNS(pod_id, config.dns);
}
```

### 2. Static IP Configuration
```zig
fn configureStaticIP(self: *Self, pod_id: []const u8, config: IpConfig.Static) !void {
    // Configure container-side veth interface
    try self.proxmox_client.configureNetwork(pod_id, .{
        .name = "eth0",
        .address = config.address,
        .netmask = config.netmask,
        .gateway = config.gateway,
        .type = .STATIC,
    });
    
    // Setup routes in network namespace
    try self.setupStaticRoutes(pod_id, config);
    
    // Apply network configuration
    try self.proxmox_client.applyNetworkConfig(pod_id);
}

fn setupStaticRoutes(self: *Self, pod_id: []const u8, config: IpConfig.Static) !void {
    // Add default route via gateway
    try self.addRoute(pod_id, .{
        .destination = "default",
        .gateway = config.gateway,
        .interface = "eth0",
    });
}
```

### 3. DHCP Configuration
```zig
fn configureDHCP(self: *Self, pod_id: []const u8, config: IpConfig.DHCP) !void {
    // Configure DHCP client in container
    try self.proxmox_client.configureNetwork(pod_id, .{
        .name = "eth0",
        .type = .DHCP,
        .hostname = config.hostname,
        .client_id = config.client_id,
    });
    
    // Start DHCP client
    try self.startDHCPClient(pod_id);
    
    // Wait for IP assignment
    try self.waitForIPAssignment(pod_id);
}

fn startDHCPClient(self: *Self, pod_id: []const u8) !void {
    try self.proxmox_client.executeInContainer(pod_id, .{
        .command = "dhclient",
        .args = &[_][]const u8{"eth0"},
    });
}

fn waitForIPAssignment(self: *Self, pod_id: []const u8) !void {
    var attempts: u32 = 0;
    const max_attempts = 30;
    
    while (attempts < max_attempts) : (attempts += 1) {
        if (try self.hasIPAddress(pod_id)) {
            return;
        }
        std.time.sleep(std.time.ns_per_s);
    }
    
    return error.DHCPTimeout;
}
```

### 4. Network Validation
```zig
pub fn validateNetworkSetup(self: *Self, pod_id: []const u8) !void {
    // Check interface status
    try self.checkInterfaceStatus(pod_id);
    
    // Verify IP configuration
    try self.verifyIPConfig(pod_id);
    
    // Test network connectivity
    try self.testConnectivity(pod_id);
}

fn testConnectivity(self: *Self, pod_id: []const u8) !void {
    // Test DNS resolution
    try self.proxmox_client.executeInContainer(pod_id, .{
        .command = "ping",
        .args = &[_][]const u8{"-c", "1", "8.8.8.8"},
    });
    
    // Test external connectivity
    try self.proxmox_client.executeInContainer(pod_id, .{
        .command = "ping",
        .args = &[_][]const u8{"-c", "1", "google.com"},
    });
}
```

### 5. Error Handling
```zig
pub const NetworkError = error{
    NamespaceCreationFailed,
    VethSetupFailed,
    BridgeAttachFailed,
    StaticIPConfigFailed,
    DHCPConfigFailed,
    DHCPTimeout,
    ConnectivityTestFailed,
};

fn handleNetworkError(self: *Self, pod_id: []const u8, err: NetworkError) !void {
    log.err("Network setup failed for pod {s}: {}", .{pod_id, err});
    
    switch (err) {
        .DHCPTimeout => {
            // Retry DHCP configuration
            try self.retryDHCP(pod_id);
        },
        .ConnectivityTestFailed => {
            // Verify routes and DNS
            try self.verifyNetworkStack(pod_id);
        },
        else => {
            // Cleanup and return error
            try self.cleanupNetworkSetup(pod_id);
            return err;
        },
    }
}
```

## Deployment Bridge Management

### 1. Bridge Creation and Configuration
```zig
pub const BridgeConfig = struct {
    name: []const u8,
    deployment_id: []const u8,
    mtu: u32 = 1500,
    vlan: ?u16 = null,
    stp: bool = true,
};

pub fn createDeploymentBridge(self: *NetworkManager, config: BridgeConfig) !void {
    // Generate unique bridge name for deployment
    const bridge_name = try std.fmt.allocPrint(
        self.allocator,
        "br-{s}",
        .{config.deployment_id}
    );
    defer self.allocator.free(bridge_name);
    
    // Create bridge via Proxmox API
    try self.proxmox_client.createBridge(.{
        .name = bridge_name,
        .stp = config.stp,
        .mtu = config.mtu,
        .vlan_aware = config.vlan != null,
        .vlan_id = config.vlan,
    });
    
    // Store bridge metadata
    try self.bridges.put(config.deployment_id, .{
        .name = bridge_name,
        .pods = std.ArrayList([]const u8).init(self.allocator),
    });
}
```

### 2. Pod to Bridge Assignment
```zig
pub const BridgeAssignment = struct {
    deployment_id: []const u8,
    pod_id: []const u8,
    network_config: NetworkConfig,
};

pub fn assignPodToBridge(self: *Self, assignment: BridgeAssignment) !void {
    // Get deployment bridge
    const bridge = self.bridges.get(assignment.deployment_id) orelse {
        return error.BridgeNotFound;
    };
    
    // Update network config with bridge name
    var network_config = assignment.network_config;
    network_config.bridge = bridge.name;
    
    // Setup pod networking with deployment bridge
    try self.setupNetworking(assignment.pod_id, network_config);
    
    // Track pod in bridge metadata
    try bridge.pods.append(assignment.pod_id);
}
```

### 3. Bridge Isolation and Security
```zig
pub fn configureBridgeSecurity(self: *Self, deployment_id: []const u8) !void {
    const bridge = self.bridges.get(deployment_id) orelse {
        return error.BridgeNotFound;
    };
    
    // Enable bridge isolation
    try self.proxmox_client.setBridgeSettings(bridge.name, .{
        .vlan_filtering = true,
        .multicast_snooping = true,
        .isolation = true,
    });
    
    // Configure firewall rules for bridge
    try self.setupBridgeFirewall(bridge.name, .{
        .allow_internal = true,  // Allow communication between pods
        .allow_external = true,  // Allow external network access
        .block_spoofing = true,  // Prevent MAC/IP spoofing
    });
}
```

### 4. Bridge Lifecycle Management
```zig
pub fn cleanupDeploymentBridge(self: *Self, deployment_id: []const u8) !void {
    const bridge = self.bridges.get(deployment_id) orelse {
        return error.BridgeNotFound;
    };
    
    // Ensure all pods are disconnected
    for (bridge.pods.items) |pod_id| {
        self.disconnectPodFromBridge(pod_id) catch |err| {
            log.warn("Failed to disconnect pod {s} from bridge: {}", .{pod_id, err});
            // Continue cleanup despite errors
        };
    }
    
    // Remove bridge via Proxmox API
    try self.proxmox_client.deleteBridge(bridge.name);
    
    // Cleanup bridge metadata
    if (self.bridges.remove(deployment_id)) |removed| {
        removed.value.pods.deinit();
    }
}

fn disconnectPodFromBridge(self: *Self, pod_id: []const u8) !void {
    // Remove veth pair
    try self.removeVethPair(pod_id);
    
    // Cleanup any remaining bridge port configuration
    try self.cleanupBridgePort(pod_id);
}
```

### 5. Bridge Monitoring and Maintenance
```zig
pub const BridgeStats = struct {
    rx_bytes: u64,
    tx_bytes: u64,
    rx_packets: u64,
    tx_packets: u64,
    errors: u64,
};

pub fn monitorBridge(self: *Self, deployment_id: []const u8) !BridgeStats {
    const bridge = self.bridges.get(deployment_id) orelse {
        return error.BridgeNotFound;
    };
    
    // Collect bridge statistics
    const stats = try self.proxmox_client.getBridgeStats(bridge.name);
    
    // Check bridge health
    try self.checkBridgeHealth(bridge.name);
    
    return stats;
}

fn checkBridgeHealth(self: *Self, bridge_name: []const u8) !void {
    // Verify bridge interface is up
    try self.verifyBridgeStatus(bridge_name);
    
    // Check for port errors
    try self.checkBridgePorts(bridge_name);
    
    // Verify STP status if enabled
    try self.verifySTPStatus(bridge_name);
}
```

## StatefulSet Pod Management

### 1. StatefulSet Network Configuration
```zig
pub const StatefulSetConfig = struct {
    name: []const u8,
    service_name: []const u8,
    replicas: u32,
    pod_prefix: []const u8,
    network: StatefulSetNetwork,
};

pub const StatefulSetNetwork = struct {
    headless_service: bool = true,
    persistent_addresses: bool = true,
    dns_policy: DNSPolicy = .ClusterFirst,
    hostname_pattern: []const u8 = "$(pod_prefix)-$(ordinal)",
    subdomain: ?[]const u8 = null,
};

pub fn setupStatefulSetNetworking(self: *NetworkManager, config: StatefulSetConfig) !void {
    // Create dedicated bridge for StatefulSet
    try self.createDeploymentBridge(.{
        .name = config.name,
        .deployment_id = config.name,
        .stp = true,
    });
    
    // Setup DNS for headless service if enabled
    if (config.network.headless_service) {
        try self.setupHeadlessService(config);
    }
    
    // Allocate persistent IP addresses if enabled
    if (config.network.persistent_addresses) {
        try self.allocatePersistentAddresses(config);
    }
}
```

### 2. Pod Identity and Persistence
```zig
pub const StatefulPodIdentity = struct {
    set_name: []const u8,
    ordinal: u32,
    hostname: []const u8,
    network_identity: NetworkIdentity,
};

pub const NetworkIdentity = struct {
    ip_address: ?[]const u8,
    mac_address: ?[]const u8,
    dns_records: std.ArrayList(DNSRecord),
};

pub fn createStatefulPod(self: *PodManager, config: StatefulSetConfig, ordinal: u32) !StatefulPodIdentity {
    // Generate deterministic pod identity
    const identity = try self.generatePodIdentity(config, ordinal);
    
    // Create pod with stable network configuration
    try self.createPodWithIdentity(identity);
    
    // Setup persistent storage (if configured)
    try self.setupPersistentStorage(identity);
    
    return identity;
}

fn generatePodIdentity(self: *Self, config: StatefulSetConfig, ordinal: u32) !StatefulPodIdentity {
    const hostname = try std.fmt.allocPrint(
        self.allocator,
        config.network.hostname_pattern,
        .{
            .pod_prefix = config.pod_prefix,
            .ordinal = ordinal,
        }
    );
    
    // Generate stable MAC address based on pod identity
    const mac = try self.generateStableMac(config.name, ordinal);
    
    // Allocate stable IP if persistent addressing is enabled
    const ip = if (config.network.persistent_addresses)
        try self.getOrAllocatePersistentIP(config.name, ordinal)
    else
        null;
        
    return StatefulPodIdentity{
        .set_name = config.name,
        .ordinal = ordinal,
        .hostname = hostname,
        .network_identity = .{
            .ip_address = ip,
            .mac_address = mac,
            .dns_records = try self.createDNSRecords(config, hostname),
        },
    };
}
```

### 3. Headless Service Management
```zig
pub fn setupHeadlessService(self: *Self, config: StatefulSetConfig) !void {
    // Create DNS zone for headless service
    try self.dns_manager.createZone(.{
        .name = config.service_name,
        .type = .Headless,
        .ttl = 30,
    });
    
    // Setup service discovery
    try self.setupServiceDiscovery(config);
}

fn setupServiceDiscovery(self: *Self, config: StatefulSetConfig) !void {
    // Configure DNS for pod-to-pod communication
    try self.dns_manager.configurePodDNS(.{
        .search_domains = &[_][]const u8{
            try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}.svc.cluster.local",
                .{config.service_name, config.name}
            ),
        },
        .ndots = 5,
        .timeout = 1,
        .attempts = 3,
    });
}
```

### 4. Network State Recovery
```zig
pub fn recoverStatefulSetNetwork(self: *Self, config: StatefulSetConfig) !void {
    // Verify existing network state
    try self.verifyNetworkState(config);
    
    // Recover persistent IP assignments
    try self.recoverPersistentIPs(config);
    
    // Rebuild DNS records
    try self.rebuildDNSRecords(config);
    
    // Verify pod connectivity
    try self.verifyPodConnectivity(config);
}

fn verifyNetworkState(self: *Self, config: StatefulSetConfig) !void {
    // Check bridge existence and configuration
    try self.verifyBridgeConfig(config.name);
    
    // Verify IP allocations
    try self.verifyIPAllocations(config);
    
    // Check DNS records
    try self.verifyDNSRecords(config);
}
```

### 5. Scaling Operations
```zig
pub fn scaleStatefulSet(self: *Self, config: StatefulSetConfig, new_replicas: u32) !void {
    const current_replicas = self.getReplicaCount(config.name);
    
    if (new_replicas > current_replicas) {
        // Scale up: Create new pods with deterministic identities
        var i = current_replicas;
        while (i < new_replicas) : (i += 1) {
            try self.createStatefulPod(config, i);
        }
    } else if (new_replicas < current_replicas) {
        // Scale down: Remove pods in reverse order
        var i = current_replicas - 1;
        while (i >= new_replicas) : (i -= 1) {
            try self.removeStatefulPod(config, i);
        }
    }
}

fn removeStatefulPod(self: *Self, config: StatefulSetConfig, ordinal: u32) !void {
    // Preserve network identity for future scaling
    if (config.network.persistent_addresses) {
        try self.preserveNetworkIdentity(config.name, ordinal);
    }
    
    // Remove pod while maintaining stable network state
    try self.removePodSafely(config, ordinal);
}
```