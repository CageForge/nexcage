# ADR-002: Memory Management Strategy

## Status
**ACCEPTED** - 2024-12-01

## Context

Proxmox LXCRI requires robust memory management to handle:
- Multiple concurrent container operations
- Large configuration structures and metadata
- Network buffers and I/O operations
- Temporary allocations for container state
- Long-running daemon processes
- Error recovery and cleanup scenarios

Memory safety is critical for a container runtime, as memory leaks or corruption can affect all containers on the system.

### Requirements

1. **Memory Safety**: Zero buffer overflows, use-after-free, or double-free errors
2. **Performance**: Minimal allocation overhead and fragmentation
3. **Resource Tracking**: Clear ownership and lifetime management
4. **Error Handling**: Graceful degradation under memory pressure
5. **Debugging**: Tools for identifying memory leaks and usage patterns

## Decision

**We implement a multi-tier memory management strategy using Zig's allocator system with arena allocators for bounded operations and careful RAII patterns.**

### Architecture

```zig
// Memory Management Hierarchy
pub const MemoryManager = struct {
    // Global allocators
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    
    // Arena allocators for bounded operations
    container_arena: ArenaAllocator,
    network_arena: ArenaAllocator,
    config_arena: ArenaAllocator,
    
    // Pool allocators for frequent small allocations
    string_pool: PoolAllocator([]u8),
    buffer_pool: PoolAllocator([4096]u8),
    
    // Memory tracking
    allocation_tracker: AllocationTracker,
    memory_limits: MemoryLimits,
};

// RAII wrapper for automatic cleanup
pub fn ManagedResource(comptime T: type) type {
    return struct {
        const Self = @This();
        
        resource: T,
        allocator: Allocator,
        cleanup_fn: ?*const fn(*T) void,
        
        pub fn init(allocator: Allocator, resource: T, cleanup_fn: ?*const fn(*T) void) Self {
            return Self{
                .resource = resource,
                .allocator = allocator,
                .cleanup_fn = cleanup_fn,
            };
        }
        
        pub fn deinit(self: *Self) void {
            if (self.cleanup_fn) |cleanup| {
                cleanup(&self.resource);
            }
        }
    };
}
```

### Core Principles

1. **Arena Allocators for Bounded Operations**
   - Container lifecycle operations use dedicated arenas
   - Arena is freed when operation completes
   - Prevents memory leaks from early returns or errors

2. **Pool Allocators for Frequent Allocations**
   - String pools for container IDs and names
   - Buffer pools for network I/O
   - Reduces allocation overhead and fragmentation

3. **RAII Pattern Implementation**
   - Automatic resource cleanup using `defer` statements
   - Managed resource wrappers for complex objects
   - Clear ownership transfer semantics

4. **Memory Pressure Handling**
   - Graceful degradation under low memory conditions
   - Cache eviction strategies
   - Emergency cleanup procedures

## Implementation Strategy

### 1. Container Operation Memory Management

```zig
pub fn createContainer(allocator: Allocator, spec: ContainerSpec) !Container {
    // Create arena for this operation
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit(); // Automatic cleanup
    
    const arena_allocator = arena.allocator();
    
    // All temporary allocations use arena
    const temp_config = try parseConfig(arena_allocator, spec.config_path);
    const validation_errors = try validateSpec(arena_allocator, temp_config);
    
    // Only persist final container structure
    var container = try Container.init(allocator, spec);
    errdefer container.deinit(); // Cleanup on error
    
    return container;
}
```

### 2. Memory Tracking and Limits

```zig
pub const AllocationTracker = struct {
    total_allocated: std.atomic.Atomic(u64),
    peak_allocation: std.atomic.Atomic(u64),
    active_allocations: std.HashMap(usize, AllocationInfo),
    mutex: std.Thread.Mutex,
    
    pub fn trackAllocation(self: *AllocationTracker, ptr: usize, size: u64) void {
        const current = self.total_allocated.fetchAdd(size, .SeqCst) + size;
        _ = self.peak_allocation.fetchMax(current, .SeqCst);
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        self.active_allocations.put(ptr, AllocationInfo{
            .size = size,
            .timestamp = std.time.nanoTimestamp(),
            .stack_trace = captureStackTrace(),
        }) catch {};
    }
    
    pub fn trackDeallocation(self: *AllocationTracker, ptr: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.active_allocations.fetchRemove(ptr)) |entry| {
            _ = self.total_allocated.fetchSub(entry.value.size, .SeqCst);
        }
    }
};
```

### 3. Memory Pool Management

```zig
pub const StringPool = struct {
    const PoolSize = 1024;
    const StringBlock = struct {
        data: [256]u8,
        len: u8,
        in_use: bool,
    };
    
    blocks: [PoolSize]StringBlock,
    free_list: std.ArrayList(u32),
    allocator: Allocator,
    
    pub fn acquire(self: *StringPool, required_size: usize) ![]u8 {
        if (required_size > 256) {
            // Fall back to direct allocation for large strings
            return try self.allocator.alloc(u8, required_size);
        }
        
        for (self.free_list.items, 0..) |block_idx, i| {
            const block = &self.blocks[block_idx];
            if (!block.in_use) {
                block.in_use = true;
                _ = self.free_list.swapRemove(i);
                return block.data[0..required_size];
            }
        }
        
        return error.PoolExhausted;
    }
    
    pub fn release(self: *StringPool, str: []u8) void {
        // Check if string is from pool
        for (&self.blocks, 0..) |*block, i| {
            if (str.ptr == block.data.ptr) {
                block.in_use = false;
                self.free_list.append(@intCast(i)) catch {};
                return;
            }
        }
        
        // String was directly allocated
        self.allocator.free(str);
    }
};
```

### 4. Error Recovery and Cleanup

```zig
pub const ErrorContext = struct {
    allocations: std.ArrayList([]u8),
    resources: std.ArrayList(Resource),
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) ErrorContext {
        return ErrorContext{
            .allocations = std.ArrayList([]u8).init(allocator),
            .resources = std.ArrayList(Resource).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn trackAllocation(self: *ErrorContext, allocation: []u8) !void {
        try self.allocations.append(allocation);
    }
    
    pub fn trackResource(self: *ErrorContext, resource: Resource) !void {
        try self.resources.append(resource);
    }
    
    pub fn cleanup(self: *ErrorContext) void {
        // Clean up resources in reverse order
        while (self.resources.popOrNull()) |resource| {
            resource.deinit();
        }
        
        // Free all tracked allocations
        for (self.allocations.items) |allocation| {
            self.allocator.free(allocation);
        }
        
        self.allocations.deinit();
        self.resources.deinit();
    }
};

// Usage pattern for error-safe operations
pub fn riskyOperation(allocator: Allocator) !Result {
    var error_context = ErrorContext.init(allocator);
    defer error_context.cleanup(); // Always cleanup on exit
    
    const buffer = try allocator.alloc(u8, 1024);
    try error_context.trackAllocation(buffer);
    
    const resource = try Resource.init(allocator);
    try error_context.trackResource(resource);
    
    // Perform operations that might fail
    const result = try processData(buffer, resource);
    
    // Success - transfer ownership out of error context
    _ = error_context.allocations.pop(); // Remove from cleanup list
    _ = error_context.resources.pop();
    
    return result;
}
```

## Consequences

### Positive
- **Memory Safety**: Zig's compile-time checks + runtime tracking prevent common errors
- **Performance**: Arena allocators eliminate allocation overhead for temporary operations
- **Debugging**: Comprehensive tracking helps identify leaks and usage patterns
- **Reliability**: RAII patterns ensure cleanup even during error conditions
- **Scalability**: Pool allocators reduce fragmentation under high load

### Negative
- **Complexity**: Multiple allocator types increase cognitive overhead
- **Memory Overhead**: Tracking structures consume additional memory
- **Runtime Cost**: Allocation tracking adds performance overhead
- **Learning Curve**: Team needs training on memory management patterns

### Mitigation Strategies

1. **Documentation**: Clear guidelines for allocator selection and usage patterns
2. **Tooling**: Memory profiling tools and leak detection utilities
3. **Testing**: Memory stress tests and leak detection in CI/CD
4. **Monitoring**: Runtime memory usage metrics and alerting

## Performance Characteristics

### Allocation Patterns
- **Small strings (< 256 bytes)**: Pool allocator - O(1) allocation/deallocation
- **Temporary operations**: Arena allocator - Bulk deallocation
- **Long-lived objects**: General purpose allocator - Standard malloc/free
- **I/O buffers**: Pool allocator with size classes

### Memory Usage Targets
- **Baseline memory**: < 50MB for daemon process
- **Per-container overhead**: < 1MB metadata and tracking
- **Peak usage**: < 200MB during intensive operations
- **Fragmentation**: < 10% under normal load

### Monitoring Metrics
```zig
pub const MemoryMetrics = struct {
    total_allocated: u64,
    peak_allocation: u64,
    active_containers: u32,
    pool_utilization: f32,
    fragmentation_ratio: f32,
    allocation_rate: f32, // allocations/second
    deallocation_rate: f32,
    
    pub fn log(self: MemoryMetrics) void {
        logger.info("Memory Metrics:");
        logger.info("  Total allocated: {d}MB", .{self.total_allocated / 1024 / 1024});
        logger.info("  Peak allocation: {d}MB", .{self.peak_allocation / 1024 / 1024});
        logger.info("  Active containers: {d}", .{self.active_containers});
        logger.info("  Pool utilization: {d:.1}%", .{self.pool_utilization * 100});
        logger.info("  Fragmentation: {d:.1}%", .{self.fragmentation_ratio * 100});
    }
};
```

## Review Schedule

This ADR will be reviewed:
- **Next review**: 2025-06-01 (6 months)
- **Trigger events**:
  - Memory-related production incidents
  - Significant performance regressions
  - New Zig allocator features
  - Memory usage exceeding targets

## References

- [Zig Memory Management Guide](https://ziglang.org/documentation/master/#Memory)
- [Arena Allocator Pattern](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/)
- [RAII in Systems Programming](https://doc.rust-lang.org/book/ch15-03-drop.html)
- [Memory Pool Design Patterns](https://gameprogrammingpatterns.com/object-pool.html)
- [Container Runtime Memory Requirements](https://kubernetes.io/docs/concepts/architecture/cri/)

---
**Author**: Proxmox LXCRI Team  
**Reviewers**: Performance Team, Security Team  
**Last Updated**: 2024-12-01
