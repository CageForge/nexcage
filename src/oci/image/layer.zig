const std = @import("std");
const types = @import("types");
const crypto = std.crypto;
const hash = crypto.hash;
const mem = std.mem;
const fs = std.fs;
const path = std.fs.path;

pub const LayerError = error{
    InvalidLayer,
    InvalidDigest,
    InvalidSize,
    InvalidMediaType,
    InvalidDigestFormat,
    InvalidDigestLength,
    InvalidAnnotations,
    LayerNotFound,
    LayerCorrupted,
    UnsupportedMediaType,
    InvalidLayerOrder,
    DependencyNotFound,
    IntegrityCheckFailed,
    MetadataError,
    StorageError,
    FileReadError,
    FileWriteError,
    InvalidPath,
    CompressionError,
    DecompressionError,
    HashMismatch,
    InvalidDependency,
    CircularDependency,
    OrderConflict,
};

/// OCI image layer with comprehensive management capabilities
pub const Layer = struct {
    // Basic layer information
    media_type: []const u8,
    digest: []const u8,
    size: u64,
    annotations: ?std.StringHashMap([]const u8),
    
    // Layer metadata
    created: ?[]const u8,
    author: ?[]const u8,
    comment: ?[]const u8,
    
    // Layer dependencies and ordering
    dependencies: ?[][]const u8, // Array of dependency digests
    order: u32, // Layer order in the image
    
    // Storage information
    storage_path: ?[]const u8, // Path to layer data
    compressed: bool, // Whether layer is compressed
    compression_type: ?[]const u8, // Type of compression if any
    
    // Validation state
    validated: bool, // Whether layer has been validated
    last_validated: ?[]const u8, // Timestamp of last validation
    
    const Self = @This();
    
    /// Create a new layer with basic information
    pub fn createLayer(
        allocator: std.mem.Allocator,
        media_type: []const u8,
        digest: []const u8,
        size: u64,
        annotations: ?std.StringHashMap([]const u8),
    ) !*Self {
        const layer = try allocator.create(Self);
        layer.* = .{
            .media_type = try allocator.dupe(u8, media_type),
            .digest = try allocator.dupe(u8, digest),
            .size = size,
            .annotations = annotations,
            .created = null,
            .author = null,
            .comment = null,
            .dependencies = null,
            .order = 0,
            .storage_path = null,
            .compressed = false,
            .compression_type = null,
            .validated = false,
            .last_validated = null,
        };
        
        return layer;
    }
    
    /// Create a new layer with full metadata
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
    ) !*Self {
        const layer = try allocator.create(Self);
        layer.* = .{
            .media_type = try allocator.dupe(u8, media_type),
            .digest = try allocator.dupe(u8, digest),
            .size = size,
            .annotations = annotations,
            .created = if (created) |c| try allocator.dupe(u8, c) else null,
            .author = if (author) |a| try allocator.dupe(u8, a) else null,
            .comment = if (comment) |cmt| try allocator.dupe(u8, cmt) else null,
            .dependencies = if (dependencies) |deps| try cloneStringArray(allocator, deps) else null,
            .order = order,
            .storage_path = if (storage_path) |sp| try allocator.dupe(u8, sp) else null,
            .compressed = compressed,
            .compression_type = if (compression_type) |ct| try allocator.dupe(u8, ct) else null,
            .validated = false,
            .last_validated = null,
        };
        
        return layer;
    }
    
    /// Clean up resources
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.media_type);
        allocator.free(self.digest);
        
        if (self.created) |created| allocator.free(created);
        if (self.author) |author| allocator.free(author);
        if (self.comment) |comment| allocator.free(comment);
        
        if (self.dependencies) |deps| {
            for (deps) |dep| {
                allocator.free(dep);
            }
            allocator.free(deps);
        }
        
        if (self.storage_path) |sp| allocator.free(sp);
        if (self.compression_type) |ct| allocator.free(ct);
        
        if (self.last_validated) |timestamp| allocator.free(timestamp);
        
        if (self.annotations) |annotations| {
            var it = annotations.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.value_ptr.*);
            }
            var mutable_annotations = annotations;
            mutable_annotations.deinit();
        }
        
        allocator.destroy(self);
    }
    
    /// Create a descriptor for this layer
    pub fn createDescriptor(self: *const Self) types.Descriptor {
        return types.Descriptor{
            .media_type = self.media_type,
            .size = self.size,
            .digest = self.digest,
            .urls = null,
            .annotations = self.annotations,
            .platform = null,
        };
    }
    
    /// Validate layer integrity
    pub fn validate(self: *Self, allocator: std.mem.Allocator) !void {
        // Validate media type
        if (self.media_type.len == 0) {
            return LayerError.InvalidMediaType;
        }
        
        // Validate digest format
        if (!mem.startsWith(u8, self.digest, "sha256:")) {
            return LayerError.InvalidDigestFormat;
        }
        
        // Validate digest length (sha256: + 64 hex chars)
        if (self.digest.len != 71) {
            return LayerError.InvalidDigestLength;
        }
        
        // Validate size
        if (self.size == 0) {
            return LayerError.InvalidSize;
        }
        
        // Validate annotations if present
        if (self.annotations) |annotations| {
            try self.validateAnnotations(&annotations);
        }
        
        // Mark as validated
        self.validated = true;
        
        // Free previous timestamp if it exists
        if (self.last_validated) |prev_timestamp| {
            allocator.free(prev_timestamp);
        }
        
        self.last_validated = try self.getCurrentTimestamp(allocator);
    }
    
    /// Validate layer annotations
    fn validateAnnotations(_: *Self, annotations: *const std.StringHashMap([]const u8)) !void {
        var it = annotations.iterator();
        while (it.next()) |entry| {
            if (entry.key_ptr.*.len == 0 or entry.value_ptr.*.len == 0) {
                return LayerError.InvalidAnnotations;
            }
        }
    }
    
    /// Get current timestamp
    fn getCurrentTimestamp(_: *Self, allocator: std.mem.Allocator) ![]const u8 {
        const timestamp = std.time.timestamp();
        return try std.fmt.allocPrint(allocator, "{d}", .{timestamp});
    }
    
    /// Check if layer has dependencies
    pub fn hasDependencies(self: *const Self) bool {
        return if (self.dependencies) |deps| deps.len > 0 else false;
    }
    
    /// Get dependency count
    pub fn getDependencyCount(self: *const Self) usize {
        return if (self.dependencies) |deps| deps.len else 0;
    }
    
    /// Check if layer is compressed
    pub fn isCompressed(self: *const Self) bool {
        return self.compressed;
    }
    
    /// Get compression type
    pub fn getCompressionType(self: *const Self) ?[]const u8 {
        return self.compression_type;
    }
    
    /// Get layer order
    pub fn getOrder(self: *const Self) u32 {
        return self.order;
    }
    
    /// Set layer order
    pub fn setOrder(self: *Self, order: u32) void {
        self.order = order;
    }
    
    /// Check if layer is validated
    pub fn isValidated(self: *const Self) bool {
        return self.validated;
    }
    
    /// Get last validation timestamp
    pub fn getLastValidated(self: *const Self) ?[]const u8 {
        return self.last_validated;
    }
    
    /// Verify layer integrity by checking file hash
    pub fn verifyIntegrity(self: *Self, allocator: std.mem.Allocator) !void {
        if (self.storage_path == null) {
            return LayerError.InvalidPath;
        }
        
        const file = try fs.cwd().openFile(self.storage_path.?, .{});
        defer file.close();
        
        const file_size = try file.getEndPos();
        if (file_size != self.size) {
            return LayerError.IntegrityCheckFailed;
        }
        
        // Calculate SHA256 hash
        var hasher = hash.sha2.Sha256.init(.{});
        var buffer: [4096]u8 = undefined;
        
        var offset: u64 = 0;
        while (offset < file_size) {
            const bytes_read = try file.reader().read(&buffer);
            if (bytes_read == 0) break;
            
            hasher.update(buffer[0..bytes_read]);
            offset += bytes_read;
        }
        
        const calculated_hash = hasher.finalResult();
        const expected_hash = self.digest[7..]; // Remove "sha256:" prefix
        
        if (!mem.eql(u8, &calculated_hash, expected_hash)) {
            return LayerError.HashMismatch;
        }
        
        self.validated = true;
        
        // Free previous timestamp if it exists
        if (self.last_validated) |prev_timestamp| {
            allocator.free(prev_timestamp);
        }
        
        self.last_validated = try self.getCurrentTimestamp(allocator);
    }
    
    /// Add dependency to layer
    pub fn addDependency(self: *Self, allocator: std.mem.Allocator, dependency_digest: []const u8) !void {
        if (self.dependencies == null) {
            self.dependencies = try allocator.alloc([]const u8, 1);
            self.dependencies.?[0] = try allocator.dupe(u8, dependency_digest);
        } else {
            const new_deps = try allocator.realloc(self.dependencies.?, self.dependencies.?.len + 1);
            new_deps[self.dependencies.?.len] = try allocator.dupe(u8, dependency_digest);
            self.dependencies = new_deps;
        }
    }
    
    /// Remove dependency from layer
    pub fn removeDependency(self: *Self, allocator: std.mem.Allocator, dependency_digest: []const u8) !void {
        if (self.dependencies) |deps| {
            for (deps, 0..) |dep, i| {
                if (mem.eql(u8, dep, dependency_digest)) {
                    allocator.free(dep);
                    if (i < deps.len - 1) {
                        deps[i] = deps[deps.len - 1];
                    }
                    self.dependencies = try allocator.realloc(deps, deps.len - 1);
                    break;
                }
            }
        }
    }
    
    /// Check if layer depends on specific digest
    pub fn dependsOn(self: *const Self, digest: []const u8) bool {
        if (self.dependencies) |deps| {
            for (deps) |dep| {
                if (mem.eql(u8, dep, digest)) {
                    return true;
                }
            }
        }
        return false;
    }
    
    /// Clone layer with new allocator
    pub fn clone(self: *const Self, allocator: std.mem.Allocator) !*Self {
        return createLayerWithMetadata(
            allocator,
            self.media_type,
            self.digest,
            self.size,
            if (self.annotations) |annotations| try cloneAnnotations(allocator, annotations) else null,
            if (self.created) |created| try allocator.dupe(u8, created) else null,
            if (self.author) |author| try allocator.dupe(u8, author) else null,
            if (self.comment) |comment| try allocator.dupe(u8, comment) else null,
            if (self.dependencies) |deps| try cloneStringArray(allocator, deps) else null,
            self.order,
            if (self.storage_path) |sp| try allocator.dupe(u8, sp) else null,
            self.compressed,
            if (self.compression_type) |ct| try allocator.dupe(u8, ct) else null,
        );
    }
};

/// Clone a string array
fn cloneStringArray(allocator: std.mem.Allocator, strings: [][]const u8) ![][]const u8 {
    const cloned = try allocator.alloc([]const u8, strings.len);
    for (cloned, 0..) |*cloned_str, i| {
        cloned_str.* = try allocator.dupe(u8, strings[i]);
    }
    return cloned;
}

/// Clone annotations hash map
fn cloneAnnotations(allocator: std.mem.Allocator, annotations: std.StringHashMap([]const u8)) !std.StringHashMap([]const u8) {
    var cloned = std.StringHashMap([]const u8).init(allocator);
    var it = annotations.iterator();
    while (it.next()) |entry| {
        try cloned.put(
            try allocator.dupe(u8, entry.key),
            try allocator.dupe(u8, entry.value)
        );
    }
    return cloned;
}

/// Layer manager for handling multiple layers
pub const LayerManager = struct {
    allocator: std.mem.Allocator,
    layers: std.StringHashMap(*Layer),
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .layers = std.StringHashMap(*Layer).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.layers.deinit();
    }
    
    /// Add layer to manager
    pub fn addLayer(self: *Self, layer: *Layer) !void {
        try self.layers.put(layer.digest, layer);
    }
    
    /// Get layer by digest
    pub fn getLayer(self: *Self, digest: []const u8) ?*Layer {
        return self.layers.get(digest);
    }
    
    /// Remove layer from manager
    pub fn removeLayer(self: *Self, digest: []const u8) !void {
        if (self.layers.get(digest)) |layer| {
            layer.deinit(self.allocator);
            _ = self.layers.remove(digest);
        }
    }
    
    /// Get all layers
    pub fn getAllLayers(self: *Self) []*Layer {
        var result = std.ArrayList(*Layer).init(self.allocator);
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            result.append(entry.value) catch continue;
        }
        return result.toOwnedSlice();
    }
    
    /// Validate all layers
    pub fn validateAllLayers(self: *Self) !void {
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            try entry.value.validate(self.allocator);
        }
    }
    
    /// Check for circular dependencies
    pub fn checkCircularDependencies(self: *Self) !void {
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            if (!visited.contains(entry.key)) {
                try self.dfsCheck(entry.value, &visited);
            }
        }
    }
    
    /// Depth-first search for circular dependencies
    fn dfsCheck(self: *Self, layer: *Layer, visited: *std.StringHashMap(bool)) !void {
        try visited.put(layer.digest, true);
        
        if (layer.dependencies) |deps| {
            for (deps) |dep| {
                if (visited.contains(dep)) {
                    return LayerError.CircularDependency;
                }
                
                if (self.layers.get(dep)) |dep_layer| {
                    try self.dfsCheck(dep_layer, visited);
                }
            }
        }
        
        _ = visited.remove(layer.digest);
    }
    
    /// Sort layers by dependency order
    pub fn sortLayersByDependencies(self: *Self) ![]*Layer {
        var sorted = std.ArrayList(*Layer).init(self.allocator);
        var visited = std.StringHashMap(bool).init(self.allocator);
        defer visited.deinit();
        
        var it = self.layers.iterator();
        while (it.next()) |entry| {
            if (!visited.contains(entry.key)) {
                try self.topologicalSort(entry.value, &visited, &sorted);
            }
        }
        
        return sorted.toOwnedSlice();
    }
    
    /// Topological sort for dependency ordering
    fn topologicalSort(self: *Self, layer: *Layer, visited: *std.StringHashMap(bool), sorted: *std.ArrayList(*Layer)) !void {
        try visited.put(layer.digest, true);
        
        if (layer.dependencies) |deps| {
            for (deps) |dep| {
                if (!visited.contains(dep)) {
                    if (self.layers.get(dep)) |dep_layer| {
                        try self.topologicalSort(dep_layer, visited, sorted);
                    }
                }
            }
        }
        
        try sorted.append(layer);
    }
};
