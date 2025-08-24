const std = @import("std");
const zig_json = @import("zig_json");

pub const ImageError = error{
    InvalidSchemaVersion,
    InvalidMediaType,
    InvalidSize,
    InvalidDigest,
    InvalidDigestFormat,
    InvalidArchitecture,
    InvalidOS,
    InvalidManifest,
    InvalidDescriptor,
    InvalidPlatform,
};

pub const ImageManifest = struct {
    schemaVersion: u32, // OCI v1.0.2 uses u32 for schema version
    config: Descriptor,
    layers: []Descriptor,
    annotations: ?std.StringHashMap([]const u8),
    
    pub fn deinit(self: *ImageManifest, allocator: std.mem.Allocator) void {
        // Free config
        self.config.deinit(allocator);
        
        // Free layers
        for (self.layers) |*layer| {
            layer.deinit(allocator);
        }
        allocator.free(self.layers);
        
        // Free annotations
        if (self.annotations) |annotations| {
            var it = annotations.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.value);
            }
            annotations.deinit();
        }
    }
    
    pub fn validate(self: *const ImageManifest) !void {
        if (self.schemaVersion != 2) {
            return error.InvalidSchemaVersion;
        }
        
        try self.config.validate();
        
        for (self.layers) |layer| {
            try layer.validate();
        }
    }
};

pub const ImageConfig = struct {
    created: ?[]const u8,
    author: ?[]const u8,
    architecture: []const u8,
    os: []const u8,
    os_version: ?[]const u8,
    config: Config,
    rootfs: Rootfs,
    history: ?[]History,
};

pub const Config = struct {
    user: ?[]const u8,
    exposed_ports: ?std.StringHashMap(zig_json.JsonValue),
    env: ?[][]const u8,
    entrypoint: ?[][]const u8,
    cmd: ?[][]const u8,
    volumes: ?std.StringHashMap(zig_json.JsonValue),
    working_dir: ?[]const u8,
    labels: ?std.StringHashMap([]const u8),
    stop_signal: ?[]const u8,
};

pub const Rootfs = struct {
    type: []const u8,
    diff_ids: [][]const u8,
};

pub const History = struct {
    created: ?[]const u8,
    author: ?[]const u8,
    created_by: ?[]const u8,
    comment: ?[]const u8,
    empty_layer: ?bool,
};

pub const Descriptor = struct {
    mediaType: []const u8,
    size: u64, // OCI v1.0.2 uses u64 for size
    digest: []const u8,
    urls: ?[][]const u8,
    annotations: ?std.StringHashMap([]const u8),
    platform: ?Platform,
    
    pub fn deinit(self: *Descriptor, allocator: std.mem.Allocator) void {
        // Free urls
        if (self.urls) |urls| {
            for (urls) |url| {
                allocator.free(url);
            }
            allocator.free(urls);
        }
        
        // Free annotations
        if (self.annotations) |annotations| {
            var it = annotations.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.value);
            }
            annotations.deinit();
        }
        
        // Free platform
        if (self.platform) |*platform| {
            platform.deinit(allocator);
        }
    }
    
    pub fn validate(self: *const Descriptor) !void {
        if (self.mediaType.len == 0) {
            return error.InvalidMediaType;
        }
        
        if (self.size == 0) {
            return error.InvalidSize;
        }
        
        if (self.digest.len == 0) {
            return error.InvalidDigest;
        }
        
        // Validate digest format (should be "sha256:...")
        if (!std.mem.startsWith(u8, self.digest, "sha256:")) {
            return error.InvalidDigestFormat;
        }
        
        if (self.platform) |platform| {
            try platform.validate();
        }
    }
};

pub const Platform = struct {
    architecture: []const u8,
    os: []const u8,
    os_version: ?[]const u8,
    os_features: ?[][]const u8,
    variant: ?[]const u8,
    features: ?[][]const u8,
    
    pub fn deinit(self: *Platform, allocator: std.mem.Allocator) void {
        // Free os_features
        if (self.os_features) |features| {
            for (features) |feature| {
                allocator.free(feature);
            }
            allocator.free(features);
        }
        
        // Free features
        if (self.features) |features| {
            for (features) |feature| {
                allocator.free(feature);
            }
            allocator.free(features);
        }
    }
    
    pub fn validate(self: *const Platform) !void {
        if (self.architecture.len == 0) {
            return error.InvalidArchitecture;
        }
        
        if (self.os.len == 0) {
            return error.InvalidOS;
        }
        
        // Validate architecture (common values: amd64, arm64, 386, etc.)
        const valid_architectures = [_][]const u8{ "amd64", "arm64", "386", "arm", "ppc64le", "s390x" };
        var valid = false;
        for (valid_architectures) |arch| {
            if (std.mem.eql(u8, self.architecture, arch)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidArchitecture;
        }
        
        // Validate OS (common values: linux, windows, darwin, etc.)
        const valid_os = [_][]const u8{ "linux", "windows", "darwin", "freebsd", "openbsd", "solaris" };
        valid = false;
        for (valid_os) |os_name| {
            if (std.mem.eql(u8, self.os, os_name)) {
                valid = true;
                break;
            }
        }
        if (!valid) {
            return error.InvalidOS;
        }
    }
};

pub const ImageIndex = struct {
    schemaVersion: i64,
    manifests: []ManifestDescriptor,
};

pub const ManifestDescriptor = struct {
    mediaType: []const u8,
    size: i64,
    digest: []const u8,
    platform: ?Platform,
};
