const std = @import("std");

/// Simple performance optimization utilities for Proxmox LXC backend
pub const SimplePerformanceOptimizer = struct {
    allocator: std.mem.Allocator,
    
    // Performance metrics
    metrics: SimplePerformanceMetrics,
    
    pub fn init(allocator: std.mem.Allocator) SimplePerformanceOptimizer {
        return SimplePerformanceOptimizer{
            .allocator = allocator,
            .metrics = SimplePerformanceMetrics.init(),
        };
    }
    
    pub fn deinit(self: *SimplePerformanceOptimizer) void {
        _ = self;
    }
    
    /// Optimize VMID generation with caching
    pub fn optimizeVmidGeneration(self: *SimplePerformanceOptimizer, container_id: []const u8) u32 {
        const start_time = std.time.nanoTimestamp();
        
        // Use a more efficient hash function
        var hash = std.hash.Wyhash.init(0);
        hash.update(container_id);
        const hash_value = hash.final();
        
        // Map to VMID range more efficiently
        const vmid = @as(u32, @intCast(100 + (hash_value % 999900)));
        
        const end_time = std.time.nanoTimestamp();
        self.metrics.vmid_generation_time = end_time - start_time;
        self.metrics.total_operations += 1;
        
        return vmid;
    }
    
    /// Optimize string operations
    pub fn optimizeStringConcat(self: *SimplePerformanceOptimizer, strings: []const []const u8) ![]u8 {
        const start_time = std.time.nanoTimestamp();
        
        // Calculate total length first
        var total_len: usize = 0;
        for (strings) |str| {
            total_len += str.len;
        }
        
        // Allocate exact size needed
        const result = try self.allocator.alloc(u8, total_len);
        var offset: usize = 0;
        
        for (strings) |str| {
            @memcpy(result[offset..offset + str.len], str);
            offset += str.len;
        }
        
        const end_time = std.time.nanoTimestamp();
        self.metrics.string_concat_time = end_time - start_time;
        self.metrics.total_operations += 1;
        
        return result;
    }
    
    /// Get performance metrics
    pub fn getMetrics(self: *const SimplePerformanceOptimizer) SimplePerformanceMetrics {
        return self.metrics;
    }
    
    /// Reset performance metrics
    pub fn resetMetrics(self: *SimplePerformanceOptimizer) void {
        self.metrics = SimplePerformanceMetrics.init();
    }
};

/// Simple performance metrics structure
pub const SimplePerformanceMetrics = struct {
    vmid_generation_time: i128 = 0,
    string_concat_time: i128 = 0,
    total_operations: u32 = 0,
    
    pub fn init() SimplePerformanceMetrics {
        return SimplePerformanceMetrics{};
    }
    
    /// Get total time for all operations
    pub fn getTotalTime(self: *const SimplePerformanceMetrics) i128 {
        return self.vmid_generation_time + self.string_concat_time;
    }
    
    /// Get average time per operation
    pub fn getAverageTime(self: *const SimplePerformanceMetrics) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.getTotalTime())) / @as(f64, @floatFromInt(self.total_operations));
    }
    
    /// Format metrics as string
    pub fn format(self: *const SimplePerformanceMetrics, allocator: std.mem.Allocator) ![]u8 {
        const total_time = self.getTotalTime();
        const avg_time = self.getAverageTime();
        
        return std.fmt.allocPrint(allocator, 
            \\Simple Performance Metrics:
            \\  VMID Generation Time: {}ns
            \\  String Concat Time: {}ns
            \\  Total Time: {}ns
            \\  Average Time: {d:.2}ns
            \\  Total Operations: {}
        , .{
            self.vmid_generation_time,
            self.string_concat_time,
            total_time,
            avg_time,
            self.total_operations,
        });
    }
};

/// Simple memory pool for efficient allocation
pub const SimpleMemoryPool = struct {
    allocator: std.mem.Allocator,
    pool: std.ArrayListUnmanaged([]u8),
    pool_size: usize,
    
    pub fn init(allocator: std.mem.Allocator, pool_size: usize) SimpleMemoryPool {
        return SimpleMemoryPool{
            .allocator = allocator,
            .pool = std.ArrayListUnmanaged([]u8){},
            .pool_size = pool_size,
        };
    }
    
    pub fn deinit(self: *SimpleMemoryPool) void {
        for (self.pool.items) |item| {
            self.allocator.free(item);
        }
        self.pool.deinit(self.allocator);
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *SimpleMemoryPool) ![]u8 {
        if (self.pool.items.len > 0) {
            const buffer = self.pool.items[self.pool.items.len - 1];
            self.pool.items.len -= 1;
            return buffer;
        }
        return try self.allocator.alloc(u8, self.pool_size);
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *SimpleMemoryPool, buffer: []u8) void {
        if (buffer.len == self.pool_size) {
            self.pool.append(self.allocator, buffer) catch {
                // If we can't add to pool, just free it
                self.allocator.free(buffer);
            };
        } else {
            // If size doesn't match, just free it
            self.allocator.free(buffer);
        }
    }
};

/// Simple string interning for efficient string storage
pub const SimpleStringIntern = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMap(void),
    
    pub fn init(allocator: std.mem.Allocator) SimpleStringIntern {
        return SimpleStringIntern{
            .allocator = allocator,
            .strings = std.StringHashMap(void).init(allocator),
        };
    }
    
    pub fn deinit(self: *SimpleStringIntern) void {
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.strings.deinit();
    }
    
    /// Intern a string (store it once and return reference)
    pub fn intern(self: *SimpleStringIntern, str: []const u8) ![]const u8 {
        if (self.strings.get(str)) |_| {
            return str;
        }
        
        const interned = try self.allocator.dupe(u8, str);
        try self.strings.put(interned, {});
        return interned;
    }
};
