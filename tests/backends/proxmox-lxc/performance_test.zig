const std = @import("std");
const testing = std.testing;
const performance = @import("performance.zig");

test "PerformanceOptimizer init" {
    const optimizer = performance.PerformanceOptimizer.init(testing.allocator, null);
    try testing.expect(optimizer.allocator == testing.allocator);
    try testing.expect(optimizer.logger == null);
}

test "PerformanceOptimizer optimizeVmidGeneration" {
    var optimizer = performance.PerformanceOptimizer.init(testing.allocator, null);
    defer optimizer.deinit();
    
    const container_id = "test-container";
    const vmid = optimizer.optimizeVmidGeneration(container_id);
    
    // VMID should be in valid range
    try testing.expect(vmid >= 100);
    try testing.expect(vmid <= 999999);
    
    // Should be consistent
    const vmid2 = optimizer.optimizeVmidGeneration(container_id);
    try testing.expectEqual(vmid, vmid2);
}

test "PerformanceOptimizer optimizeStringConcat" {
    var optimizer = performance.PerformanceOptimizer.init(testing.allocator, null);
    defer optimizer.deinit();
    
    const strings = [_][]const u8{ "hello", " ", "world", "!" };
    const result = try optimizer.optimizeStringConcat(&strings);
    defer testing.allocator.free(result);
    
    try testing.expectEqualStrings("hello world!", result);
}

test "PerformanceMetrics init" {
    const metrics = performance.PerformanceMetrics.init();
    try testing.expectEqual(@as(i128, 0), metrics.json_parse_time);
    try testing.expectEqual(@as(i128, 0), metrics.file_read_time);
    try testing.expectEqual(@as(i128, 0), metrics.vmid_generation_time);
    try testing.expectEqual(@as(i128, 0), metrics.string_concat_time);
    try testing.expectEqual(@as(u32, 0), metrics.total_operations);
}

test "PerformanceMetrics getTotalTime" {
    var metrics = performance.PerformanceMetrics.init();
    metrics.json_parse_time = 100;
    metrics.file_read_time = 200;
    metrics.vmid_generation_time = 50;
    metrics.string_concat_time = 25;
    
    const total_time = metrics.getTotalTime();
    try testing.expectEqual(@as(i128, 375), total_time);
}

test "PerformanceMetrics getAverageTime" {
    var metrics = performance.PerformanceMetrics.init();
    metrics.json_parse_time = 100;
    metrics.file_read_time = 200;
    metrics.vmid_generation_time = 50;
    metrics.string_concat_time = 25;
    metrics.total_operations = 4;
    
    const avg_time = metrics.getAverageTime();
    try testing.expectEqual(@as(f64, 93.75), avg_time);
}

test "MemoryPool init and deinit" {
    var pool = performance.MemoryPool.init(testing.allocator, 1024);
    defer pool.deinit();
    
    try testing.expectEqual(@as(usize, 1024), pool.pool_size);
    try testing.expectEqual(@as(usize, 0), pool.pool.items.len);
}

test "MemoryPool getBuffer and returnBuffer" {
    var pool = performance.MemoryPool.init(testing.allocator, 1024);
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

test "StringIntern init and deinit" {
    var intern = performance.StringIntern.init(testing.allocator);
    defer intern.deinit();
    
    try testing.expectEqual(@as(usize, 0), intern.strings.count());
}

test "StringIntern intern" {
    var intern = performance.StringIntern.init(testing.allocator);
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
    try testing.expect(interned1.ptr == interned3.ptr);
}
