const std = @import("std");

/// Performance optimization utilities for Proxmox LXC backend
pub const PerformanceOptimizer = struct {
    allocator: std.mem.Allocator,
    logger: ?*std.log.Logger,
    
    // Performance metrics
    metrics: PerformanceMetrics,
    
    pub fn init(allocator: std.mem.Allocator, logger: ?*std.log.Logger) PerformanceOptimizer {
        return PerformanceOptimizer{
            .allocator = allocator,
            .logger = logger,
            .metrics = PerformanceMetrics.init(),
        };
    }
    
    pub fn deinit(self: *PerformanceOptimizer) void {
        _ = self;
    }
    
    /// Optimize JSON parsing by using a more efficient parser
    pub fn optimizeJsonParsing(self: *PerformanceOptimizer, content: []const u8) !std.json.Value {
        const start_time = std.time.nanoTimestamp();
        
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
            .max_value_len = 10 * 1024 * 1024, // 10MB max
        });
        
        const end_time = std.time.nanoTimestamp();
        self.metrics.json_parse_time = end_time - start_time;
        
        if (self.logger) |log| {
            try log.debug("JSON parsing took {}ns", .{self.metrics.json_parse_time});
        }
        
        return parsed.value;
    }
    
    /// Optimize file I/O operations
    pub fn optimizeFileRead(self: *PerformanceOptimizer, file_path: []const u8) ![]u8 {
        const start_time = std.time.nanoTimestamp();
        
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();
        
        // Use a buffer for efficient reading
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        
        const bytes_read = try file.readAll(content);
        if (bytes_read != file_size) {
            return error.UnexpectedEndOfFile;
        }
        
        const end_time = std.time.nanoTimestamp();
        self.metrics.file_read_time = end_time - start_time;
        
        if (self.logger) |log| {
            try log.debug("File read took {}ns, size: {} bytes", .{ self.metrics.file_read_time, file_size });
        }
        
        return content;
    }
    
    /// Optimize VMID generation with caching
    pub fn optimizeVmidGeneration(self: *PerformanceOptimizer, container_id: []const u8) u32 {
        const start_time = std.time.nanoTimestamp();
        
        // Use a more efficient hash function
        var hash = std.hash.Wyhash.init(0);
        hash.update(container_id);
        const hash_value = hash.final();
        
        // Map to VMID range more efficiently
        const vmid = @as(u32, @intCast(100 + (hash_value % 999900)));
        
        const end_time = std.time.nanoTimestamp();
        self.metrics.vmid_generation_time = end_time - start_time;
        
        if (self.logger) |log| {
            try log.debug("VMID generation took {}ns", .{self.metrics.vmid_generation_time});
        }
        
        return vmid;
    }
    
    /// Optimize string operations
    pub fn optimizeStringConcat(self: *PerformanceOptimizer, strings: []const []const u8) ![]u8 {
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
        
        if (self.logger) |log| {
            try log.debug("String concatenation took {}ns, {} strings", .{ self.metrics.string_concat_time, strings.len });
        }
        
        return result;
    }
    
    /// Get performance metrics
    pub fn getMetrics(self: *const PerformanceOptimizer) PerformanceMetrics {
        return self.metrics;
    }
    
    /// Reset performance metrics
    pub fn resetMetrics(self: *PerformanceOptimizer) void {
        self.metrics = PerformanceMetrics.init();
    }
};

/// Performance metrics structure
pub const PerformanceMetrics = struct {
    json_parse_time: i128 = 0,
    file_read_time: i128 = 0,
    vmid_generation_time: i128 = 0,
    string_concat_time: i128 = 0,
    total_operations: u32 = 0,
    
    pub fn init() PerformanceMetrics {
        return PerformanceMetrics{};
    }
    
    /// Get total time for all operations
    pub fn getTotalTime(self: *const PerformanceMetrics) i128 {
        return self.json_parse_time + self.file_read_time + self.vmid_generation_time + self.string_concat_time;
    }
    
    /// Get average time per operation
    pub fn getAverageTime(self: *const PerformanceMetrics) f64 {
        if (self.total_operations == 0) return 0.0;
        return @as(f64, @floatFromInt(self.getTotalTime())) / @as(f64, @floatFromInt(self.total_operations));
    }
    
    /// Format metrics as string
    pub fn format(self: *const PerformanceMetrics, allocator: std.mem.Allocator) ![]u8 {
        const total_time = self.getTotalTime();
        const avg_time = self.getAverageTime();
        
        return std.fmt.allocPrint(allocator, 
            \\Performance Metrics:
            \\  JSON Parse Time: {}ns
            \\  File Read Time: {}ns
            \\  VMID Generation Time: {}ns
            \\  String Concat Time: {}ns
            \\  Total Time: {}ns
            \\  Average Time: {d:.2}ns
            \\  Total Operations: {}
        , .{
            self.json_parse_time,
            self.file_read_time,
            self.vmid_generation_time,
            self.string_concat_time,
            total_time,
            avg_time,
            self.total_operations,
        });
    }
};

/// Memory pool for efficient allocation
pub const MemoryPool = struct {
    allocator: std.mem.Allocator,
    pool: std.ArrayListUnmanaged([]u8),
    pool_size: usize,
    
    pub fn init(allocator: std.mem.Allocator, pool_size: usize) MemoryPool {
        return MemoryPool{
            .allocator = allocator,
            .pool = std.ArrayListUnmanaged([]u8){},
            .pool_size = pool_size,
        };
    }
    
    pub fn deinit(self: *MemoryPool) void {
        for (self.pool.items) |item| {
            self.allocator.free(item);
        }
        self.pool.deinit(self.allocator);
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *MemoryPool) ![]u8 {
        if (self.pool.items.len > 0) {
            return self.pool.popOrNull() orelse try self.allocator.alloc(u8, self.pool_size);
        }
        return try self.allocator.alloc(u8, self.pool_size);
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *MemoryPool, buffer: []u8) void {
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

/// String interning for efficient string storage
pub const StringIntern = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMap(void),
    
    pub fn init(allocator: std.mem.Allocator) StringIntern {
        return StringIntern{
            .allocator = allocator,
            .strings = std.StringHashMap(void).init(allocator),
        };
    }
    
    pub fn deinit(self: *StringIntern) void {
        var it = self.strings.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.strings.deinit();
    }
    
    /// Intern a string (store it once and return reference)
    pub fn intern(self: *StringIntern, str: []const u8) ![]const u8 {
        if (self.strings.get(str)) |_| {
            return str;
        }
        
        const interned = try self.allocator.dupe(u8, str);
        try self.strings.put(interned, {});
        return interned;
    }
};
