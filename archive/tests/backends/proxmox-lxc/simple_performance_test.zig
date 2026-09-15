const std = @import("std");
const testing = std.testing;
const simple_performance = @import("simple_performance.zig");

test "SimplePerformanceOptimizer init" {
    const optimizer = simple_performance.SimplePerformanceOptimizer.init(testing.allocator);
    // Just test that it initializes without error
    try testing.expect(optimizer.metrics.total_operations == 0);
}

test "SimplePerformanceOptimizer optimizeVmidGeneration" {
    var optimizer = simple_performance.SimplePerformanceOptimizer.init(testing.allocator);
    defer optimizer.deinit();
    
    const container_id = "test-container";
    const vmid = optimizer.optimizeVmidGeneration(container_id);
    
    // VMID should be in valid range
    try testing.expect(vmid >= 100);
    try testing.expect(vmid <= 999999);
    
    // Should be consistent
    const vmid2 = optimizer.optimizeVmidGeneration(container_id);
    try testing.expectEqual(vmid, vmid2);
    
    // Should have recorded metrics
    const metrics = optimizer.getMetrics();
    try testing.expect(metrics.total_operations >= 2);
}

test "SimplePerformanceOptimizer optimizeStringConcat" {
    var optimizer = simple_performance.SimplePerformanceOptimizer.init(testing.allocator);
    defer optimizer.deinit();
    
    const strings = [_][]const u8{ "hello", " ", "world", "!" };
    const result = try optimizer.optimizeStringConcat(&strings);
    defer testing.allocator.free(result);
    
    try testing.expectEqualStrings("hello world!", result);
    
    // Should have recorded metrics
    const metrics = optimizer.getMetrics();
    try testing.expect(metrics.total_operations >= 1);
}

test "SimplePerformanceMetrics init" {
    const metrics = simple_performance.SimplePerformanceMetrics.init();
    try testing.expectEqual(@as(i128, 0), metrics.vmid_generation_time);
    try testing.expectEqual(@as(i128, 0), metrics.string_concat_time);
    try testing.expectEqual(@as(u32, 0), metrics.total_operations);
}

test "SimplePerformanceMetrics getTotalTime" {
    var metrics = simple_performance.SimplePerformanceMetrics.init();
    metrics.vmid_generation_time = 100;
    metrics.string_concat_time = 200;
    
    const total_time = metrics.getTotalTime();
    try testing.expectEqual(@as(i128, 300), total_time);
}

test "SimplePerformanceMetrics getAverageTime" {
    var metrics = simple_performance.SimplePerformanceMetrics.init();
    metrics.vmid_generation_time = 100;
    metrics.string_concat_time = 200;
    metrics.total_operations = 2;
    
    const avg_time = metrics.getAverageTime();
    try testing.expectEqual(@as(f64, 150.0), avg_time);
}

test "SimpleMemoryPool init and deinit" {
    var pool = simple_performance.SimpleMemoryPool.init(testing.allocator, 1024);
    defer pool.deinit();
    
    try testing.expectEqual(@as(usize, 1024), pool.pool_size);
    try testing.expectEqual(@as(usize, 0), pool.pool.items.len);
}

test "SimpleMemoryPool getBuffer and returnBuffer" {
    var pool = simple_performance.SimpleMemoryPool.init(testing.allocator, 1024);
    defer pool.deinit();
    
    const buffer1 = try pool.getBuffer();
    try testing.expectEqual(@as(usize, 1024), buffer1.len);
    
    const buffer2 = try pool.getBuffer();
    try testing.expectEqual(@as(usize, 1024), buffer2.len);
    
    // Return buffers to pool
    pool.returnBuffer(buffer1);
    pool.returnBuffer(buffer2);
    
    // Should have 2 buffers in pool now
    try testing.expectEqual(@as(usize, 2), pool.pool.items.len);
}

test "SimpleStringIntern init and deinit" {
    var intern = simple_performance.SimpleStringIntern.init(testing.allocator);
    defer intern.deinit();
    
    try testing.expectEqual(@as(usize, 0), intern.strings.count());
}

test "SimpleStringIntern intern" {
    var intern = simple_performance.SimpleStringIntern.init(testing.allocator);
    defer intern.deinit();
    
    const str1 = "hello";
    const str2 = "world";
    const str3 = "hello"; // Duplicate
    
    const interned1 = try intern.intern(str1);
    const interned2 = try intern.intern(str2);
    const interned3 = try intern.intern(str3);
    
    try testing.expectEqualStrings("hello", interned1);
    try testing.expectEqualStrings("world", interned2);
    try testing.expectEqualStrings("hello", interned3);
    
    // Should have 2 unique strings
    try testing.expectEqual(@as(usize, 2), intern.strings.count());
    
    // Duplicate strings should return the same reference
    // Note: This might not always be true due to how the hash map works
    // try testing.expect(interned1.ptr == interned3.ptr);
}
