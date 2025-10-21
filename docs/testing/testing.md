# Testing Documentation

## Overview

Nexcage includes a comprehensive testing suite that covers all major components of the OCI Image System. The testing framework is designed to ensure code quality, performance, and reliability across different scenarios.

## Test Structure

### Test Categories

#### 1. Unit Tests
- **Location**: `tests/oci/image/`
- **Purpose**: Test individual functions and data structures
- **Coverage**: Core functionality of each component
- **Files**:
  - `layer_test.zig` - Layer management tests
  - `layerfs_test.zig` - LayerFS functionality tests
  - `config_test.zig` - Image configuration tests
  - `manifest_test.zig` - Image manifest tests
  - `manager_test.zig` - Image manager tests

#### 2. Performance Tests
- **Location**: `tests/performance/`
- **Purpose**: Measure performance and identify bottlenecks
- **Coverage**: LayerFS operations, caching, parallel processing
- **Files**:
  - `layerfs_performance_test.zig` - LayerFS performance metrics

#### 3. Memory Tests
- **Location**: `tests/memory/`
- **Purpose**: Detect memory leaks and resource management issues
- **Coverage**: Memory allocation, cleanup, and resource tracking
- **Files**:
  - `memory_leak_test.zig` - Memory leak detection

#### 4. Integration Tests
- **Location**: `tests/integration/`
- **Purpose**: Test component interactions and end-to-end workflows
- **Coverage**: Complete container creation process
- **Files**:
  - `end_to_end_test.zig` - End-to-end workflow tests

#### 5. Comprehensive Tests
- **Location**: `tests/`
- **Purpose**: Combined testing of multiple components
- **Coverage**: Cross-component functionality
- **Files**:
  - `simple_comprehensive_test.zig` - Simplified comprehensive tests
  - `comprehensive_test.zig` - Full comprehensive test suite

## Running Tests

### Prerequisites
- Zig 0.15.1 or later
- All project dependencies installed
- Sufficient disk space for test artifacts

### Basic Test Commands

#### Run All Tests
```bash
./zig-linux-x86_64-0.15.1/zig build test
```

#### Run Specific Test Categories
```bash
# Performance tests
./zig-linux-x86_64-0.15.1/zig build test-performance

# Memory leak tests
./zig-linux-x86_64-0.15.1/zig build test-memory

# Integration tests
./zig-linux-x86_64-0.15.1/zig build test-integration

# Comprehensive tests
./zig-linux-x86_64-0.15.1/zig build test-comprehensive
```

#### Run Individual Test Files
```bash
# Test specific component
./zig-linux-x86_64-0.15.1/zig test tests/oci/image/layerfs_test.zig

# Test with specific target
./zig-linux-x86_64-0.15.1/zig test tests/oci/image/layerfs_test.zig -target native
```

### Test Environment Setup

#### Temporary Directories
Tests create temporary directories in `/tmp/` for testing:
- `/tmp/test-layers-*` - LayerFS tests
- `/tmp/test-e2e-*` - End-to-end tests
- `/tmp/test-*` - Other component tests

#### Cleanup
Tests automatically clean up temporary files using `defer` statements:
```zig
const test_dir = "/tmp/test-example";
defer std.fs.cwd().deleteTree(test_dir) catch {};
```

## Test Components

### Layer Testing

#### Basic Layer Operations
```zig
test "Layer creation and basic properties" {
    const allocator = testing.allocator;
    
    var layer = try image.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        "sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
        1024,
        null,
    );
    defer layer.deinit(allocator);
    
    // Test properties
    try testing.expectEqualStrings("application/vnd.oci.image.layer.v1.tar", layer.media_type);
    try testing.expectEqual(@as(u64, 1024), layer.size);
}
```

#### Layer Validation
```zig
test "Layer validation" {
    var layer = try createTestLayer(1);
    defer layer.deinit(allocator);
    
    // Test validation
    try layer.validate(allocator);
    try testing.expectEqual(true, layer.validated);
    try testing.expect(layer.last_validated != null);
}
```

### LayerFS Testing

#### Initialization
```zig
test "LayerFS initialization" {
    const layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    try testing.expectEqualStrings("/tmp/test-layers", layerfs.base_path);
    try testing.expectEqual(false, layerfs.readonly);
    try testing.expectEqual(@as(usize, 0), layerfs.layers.count());
}
```

#### Layer Management
```zig
test "LayerFS add and get layer" {
    var layerfs = try LayerFS.init(allocator, "/tmp/test-layers");
    defer layerfs.deinit();
    
    const layer = try createTestLayer(1);
    defer layer.deinit(allocator);
    
    try layerfs.addLayer(layer);
    
    const retrieved_layer = layerfs.getLayer(layer.digest);
    try testing.expect(retrieved_layer != null);
}
```

### Performance Testing

#### LayerFS Performance
```zig
test "LayerFS performance: adding multiple layers" {
    const num_layers = 50;
    const test_dir = "/tmp/test-layers-performance";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    var layerfs = try LayerFS.init(allocator, test_dir);
    defer layerfs.deinit();
    
    const start_time = std.time.milliTimestamp();
    
    // Add multiple layers
    for (0..num_layers) |i| {
        var layer = try createTestLayer(@intCast(i));
        defer layer.deinit(allocator);
        
        try layerfs.addLayer(layer);
    }
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    try testing.expectEqual(@as(usize, num_layers), layerfs.layers.count());
    try testing.expect(duration < 2000); // Should complete in less than 2 seconds
    
    std.debug.print("Added {d} layers in {d}ms\n", .{ num_layers, duration });
}
```

#### Cache Performance
```zig
test "MetadataCache performance" {
    const num_entries = 100;
    var cache = MetadataCache.init(allocator, num_entries);
    defer cache.deinit();
    
    const start_time = std.time.milliTimestamp();
    
    // Add cache entries
    for (0..num_entries) |i| {
        const entry = try createTestCacheEntry(i);
        try cache.put(entry.digest, entry);
    }
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    try testing.expectEqual(@as(usize, num_entries), cache.entries.count());
    try testing.expect(duration < 1000); // Should complete in less than 1 second
}
```

### Memory Testing

#### Memory Leak Detection
```zig
test "Memory leak detection: LayerFS operations" {
    const test_dir = "/tmp/test-memory-leak-layerfs";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    // Create and destroy LayerFS multiple times
    for (0..100) |_| {
        var layerfs = try LayerFS.init(allocator, test_dir);
        
        // Add some layers
        for (0..10) |i| {
            var layer = try createTestLayer(i);
            defer layer.deinit(allocator);
            
            try layerfs.addLayer(layer);
        }
        
        // This should clean up all resources
        layerfs.deinit();
    }
    
    // If we reach here without memory issues, the test passes
    try testing.expect(true);
}
```

### Integration Testing

#### End-to-End Workflow
```zig
test "End-to-end: complete container creation workflow" {
    const test_dir = "/tmp/test-e2e-workflow";
    defer std.fs.cwd().deleteTree(test_dir) catch {};
    
    try std.fs.cwd().makePath(test_dir);
    
    // Create mock image structure
    try createMockImageStructure(test_dir, "test-image", "latest");
    
    // Initialize ImageManager
    var manager = try ImageManager.init(allocator, "/usr/bin/umoci", test_dir);
    defer manager.deinit();
    
    // Verify image exists
    try testing.expectEqual(true, manager.hasImage("test-image", "latest"));
    
    // Create container from image
    try manager.createContainerFromImage("test-image", "latest", "test-container", test_dir);
    
    // Verify container was created
    const container_rootfs = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, "test-container", "rootfs" });
    defer allocator.free(container_rootfs);
    
    try testing.expect(std.fs.accessAbsolute(container_rootfs, .{}) == .{});
}
```

## Test Utilities

### Helper Functions

#### Create Test Digest
```zig
fn createTestDigest(index: u32) []const u8 {
    var buffer: [128]u8 = undefined;
    const digest = std.fmt.bufPrint(&buffer, "sha256:testdigest{:0>10}abcdef1234567890abcdef1234567890abcdef1234567890", .{index}) catch "sha256:default";
    return allocator.dupe(u8, digest) catch "sha256:default";
}
```

#### Create Test Layer
```zig
fn createTestLayer(index: u32) !*Layer {
    const digest = createTestDigest(index);
    defer allocator.free(digest);
    
    return try Layer.createLayer(
        allocator,
        "application/vnd.oci.image.layer.v1.tar",
        try allocator.dupe(u8, digest),
        1024 + index * 100,
        null
    );
}
```

#### Create Mock Image Structure
```zig
fn createMockImageStructure(test_dir: []const u8, image_name: []const u8, image_tag: []const u8) !void {
    // Create image directory structure
    const image_dir = try std.fs.path.join(allocator, &[_][]const u8{ test_dir, image_name, image_tag });
    defer allocator.free(image_dir);
    
    try std.fs.cwd().makePath(image_dir);
    
    // Create mock files (manifest.json, config.json, layers)
    // ... implementation details
}
```

## Test Configuration

### Build System Integration

The testing framework is integrated with the Zig build system through `build.zig`:

```zig
// Performance tests
const performance_test = b.addTest(.{
    .root_source_file = b.path("tests/performance/layerfs_performance_test.zig"),
    .target = target,
    .optimize = optimize,
});

// Memory leak tests
const memory_test = b.addTest(.{
    .root_source_file = b.path("tests/memory/memory_leak_test.zig"),
    .target = target,
    .optimize = optimize,
});

// Integration tests
const integration_test = b.addTest(.{
    .root_source_file = b.path("tests/integration/end_to_end_test.zig"),
    .target = target,
    .optimize = optimize,
});
```

### Test Dependencies

Tests import required modules through the build system:
```zig
performance_test.root_module.addImport("types", types_mod);
performance_test.root_module.addImport("error", error_mod);
performance_test.root_module.addImport("logger", logger_mod);
performance_test.root_module.addImport("image", image_mod);
performance_test.root_module.addImport("layer", layer_mod);
```

## Best Practices

### Test Design

1. **Isolation**: Each test should be independent and not affect others
2. **Cleanup**: Always clean up resources using `defer` statements
3. **Naming**: Use descriptive test names that explain the scenario
4. **Assertions**: Use specific assertions that provide clear failure information

### Performance Testing

1. **Baseline**: Establish performance baselines for comparison
2. **Thresholds**: Set reasonable performance thresholds
3. **Metrics**: Measure specific metrics (time, memory, throughput)
4. **Reproducibility**: Ensure tests produce consistent results

### Memory Testing

1. **Stress Testing**: Test with high load and repeated operations
2. **Resource Tracking**: Monitor memory allocation and deallocation
3. **Cleanup Verification**: Ensure all resources are properly cleaned up
4. **Leak Detection**: Use tools and patterns to detect memory leaks

### Integration Testing

1. **Real Scenarios**: Test realistic use cases and workflows
2. **Error Handling**: Test error conditions and edge cases
3. **Component Interaction**: Verify proper communication between components
4. **End-to-End**: Test complete user workflows

## Troubleshooting

### Common Issues

#### Test Failures
- Check test environment setup
- Verify dependencies are installed
- Review test output for specific error messages
- Ensure sufficient disk space and permissions

#### Performance Issues
- Monitor system resources during tests
- Check for background processes affecting performance
- Verify test isolation and cleanup
- Review performance thresholds and baselines

#### Memory Issues
- Use memory profiling tools
- Check for resource leaks in test setup
- Verify proper cleanup in test teardown
- Monitor system memory usage

### Debugging

#### Verbose Output
```bash
# Enable verbose test output
./zig-linux-x86_64-0.15.1/zig test tests/oci/image/layerfs_test.zig --verbose
```

#### Individual Test Execution
```bash
# Run specific test by name
./zig-linux-x86_64-0.15.1/zig test tests/oci/image/layerfs_test.zig --test-filter "LayerFS initialization"
```

#### Test Coverage
```bash
# Generate test coverage report (if supported)
./zig-linux-x86_64-0.15.1/zig test tests/oci/image/layerfs_test.zig --test-coverage
```

## Future Enhancements

### Planned Improvements

1. **Continuous Integration**: Automated test execution on code changes
2. **Coverage Reporting**: Detailed code coverage analysis
3. **Performance Benchmarking**: Automated performance regression detection
4. **Test Parallelization**: Parallel test execution for faster feedback
5. **Mock Services**: Enhanced mocking for external dependencies

### Testing Tools

1. **Test Runners**: Specialized test execution frameworks
2. **Mocking Libraries**: Advanced mocking and stubbing capabilities
3. **Performance Profilers**: Detailed performance analysis tools
4. **Memory Analyzers**: Advanced memory leak detection

## Conclusion

The testing framework provides comprehensive coverage of the OCI Image System components, ensuring code quality, performance, and reliability. Regular test execution helps maintain system stability and catch issues early in the development process.

For questions or issues with the testing framework, please refer to the project documentation or create an issue in the project repository.
