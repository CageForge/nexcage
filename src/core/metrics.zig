const std = @import("std");

/// Prometheus-style metrics exporter
pub const MetricsRegistry = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    counters: std.StringHashMap(Counter),
    gauges: std.StringHashMap(Gauge),
    histograms: std.StringHashMap(Histogram),
    
    /// Initialize metrics registry
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .counters = std.StringHashMap(Counter).init(allocator),
            .gauges = std.StringHashMap(Gauge).init(allocator),
            .histograms = std.StringHashMap(Histogram).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var counter_it = self.counters.iterator();
        while (counter_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.counters.deinit();
        
        var gauge_it = self.gauges.iterator();
        while (gauge_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.gauges.deinit();
        
        var histogram_it = self.histograms.iterator();
        while (histogram_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.histograms.deinit();
    }
    
    /// Create or get counter
    pub fn counter(self: *Self, name: []const u8, help: []const u8) !*Counter {
        if (self.counters.get(name)) |existing| {
            return existing;
        }
        
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        
        const help_owned = try self.allocator.dupe(u8, help);
        errdefer self.allocator.free(help_owned);
        
        var counter = Counter.init(self.allocator, name_owned, help_owned);
        errdefer counter.deinit(self.allocator);
        
        try self.counters.put(name_owned, counter);
        return self.counters.getPtr(name_owned).?;
    }
    
    /// Create or get gauge
    pub fn gauge(self: *Self, name: []const u8, help: []const u8) !*Gauge {
        if (self.gauges.get(name)) |existing| {
            return existing;
        }
        
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        
        const help_owned = try self.allocator.dupe(u8, help);
        errdefer self.allocator.free(help_owned);
        
        var gauge = Gauge.init(self.allocator, name_owned, help_owned);
        errdefer gauge.deinit(self.allocator);
        
        try self.gauges.put(name_owned, gauge);
        return self.gauges.getPtr(name_owned).?;
    }
    
    /// Export metrics in Prometheus format
    pub fn exportMetrics(self: *Self, writer: anytype) !void {
        // Export counters
        var counter_it = self.counters.iterator();
        while (counter_it.next()) |entry| {
            try entry.value_ptr.exportMetric(writer);
        }
        
        // Export gauges
        var gauge_it = self.gauges.iterator();
        while (gauge_it.next()) |entry| {
            try entry.value_ptr.exportMetric(writer);
        }
        
        // Export histograms
        var histogram_it = self.histograms.iterator();
        while (histogram_it.next()) |entry| {
            try entry.value_ptr.exportMetric(writer);
        }
    }
};

/// Counter metric
pub const Counter = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    name: []const u8,
    help: []const u8,
    value: f64 = 0.0,
    labels: std.StringHashMap([]const u8),
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, help: []const u8) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .help = help,
            .value = 0.0,
            .labels = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        var it = self.labels.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.labels.deinit();
        allocator.free(self.name);
        allocator.free(self.help);
    }
    
    pub fn inc(self: *Self, delta: f64) void {
        self.value += delta;
    }
    
    pub fn exportMetric(self: *Self, writer: anytype) !void {
        // Write help
        try writer.print("# HELP {s} {s}\n", .{ self.name, self.help });
        
        // Write type
        try writer.print("# TYPE {s} counter\n", .{self.name});
        
        // Write value with labels
        if (self.labels.count() > 0) {
            try writer.print("{s}{{", .{self.name});
            var first = true;
            var it = self.labels.iterator();
            while (it.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;
                try writer.print("{s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try writer.print("}} {d}\n", .{self.value});
        } else {
            try writer.print("{s} {d}\n", .{ self.name, self.value });
        }
    }
};

/// Gauge metric
pub const Gauge = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    name: []const u8,
    help: []const u8,
    value: f64 = 0.0,
    labels: std.StringHashMap([]const u8),
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, help: []const u8) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .help = help,
            .value = 0.0,
            .labels = std.StringHashMap([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        var it = self.labels.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.labels.deinit();
        allocator.free(self.name);
        allocator.free(self.help);
    }
    
    pub fn set(self: *Self, value: f64) void {
        self.value = value;
    }
    
    pub fn inc(self: *Self, delta: f64) void {
        self.value += delta;
    }
    
    pub fn dec(self: *Self, delta: f64) void {
        self.value -= delta;
    }
    
    pub fn exportMetric(self: *Self, writer: anytype) !void {
        try writer.print("# HELP {s} {s}\n", .{ self.name, self.help });
        try writer.print("# TYPE {s} gauge\n", .{self.name});
        
        if (self.labels.count() > 0) {
            try writer.print("{s}{{", .{self.name});
            var first = true;
            var it = self.labels.iterator();
            while (it.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;
                try writer.print("{s}=\"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try writer.print("}} {d}\n", .{self.value});
        } else {
            try writer.print("{s} {d}\n", .{ self.name, self.value });
        }
    }
};

/// Histogram metric (simplified)
pub const Histogram = struct {
    const Self = @This();
    
    allocator: std.mem.Allocator,
    name: []const u8,
    help: []const u8,
    buckets: std.ArrayList(f64),
    counts: std.ArrayList(u64),
    sum: f64 = 0.0,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, help: []const u8) Self {
        return Self{
            .allocator = allocator,
            .name = name,
            .help = help,
            .buckets = std.ArrayList(f64).init(allocator),
            .counts = std.ArrayList(u64).init(allocator),
            .sum = 0.0,
        };
    }
    
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.buckets.deinit();
        self.counts.deinit();
        allocator.free(self.name);
        allocator.free(self.help);
    }
    
    pub fn observe(self: *Self, value: f64) !void {
        self.sum += value;
        // Simplified histogram - just track sum and count
        // Full implementation would bucket values
    }
    
    pub fn exportMetric(self: *Self, writer: anytype) !void {
        try writer.print("# HELP {s} {s}\n", .{ self.name, self.help });
        try writer.print("# TYPE {s} histogram\n", .{self.name});
        try writer.print("{s}_sum {d}\n", .{ self.name, self.sum });
        // Additional histogram metrics would go here
    }
};

