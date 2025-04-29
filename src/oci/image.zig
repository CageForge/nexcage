const std = @import("std");
const types = @import("image/types.zig");
const manifest = @import("image/manifest.zig");
const config = @import("image/config.zig");
const layer = @import("image/layer.zig");

pub const Image = struct {
    manifest: types.ImageManifest,
    config: types.ImageConfig,
    layers: []layer.Layer,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        architecture: []const u8,
        os: []const u8,
    ) !*Self {
        const empty_rootfs = types.RootFS{
            .type = "layers",
            .diff_ids = &[_][]const u8{},
        };

        const img_config = try config.createConfig(
            allocator,
            architecture,
            os,
            null,
            empty_rootfs,
            null,
        );

        const self = try allocator.create(Self);
        self.* = .{
            .manifest = undefined,
            .config = img_config,
            .layers = &[_]layer.Layer{},
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.layers);
        self.allocator.destroy(self);
    }

    pub fn addLayer(self: *Self, path: []const u8, media_type: []const u8) !void {
        const new_layer = try layer.createLayer(self.allocator, path, media_type);
        try layer.validateLayer(new_layer);

        const new_layers = try self.allocator.alloc(layer.Layer, self.layers.len + 1);
        std.mem.copy(layer.Layer, new_layers[0..self.layers.len], self.layers);
        new_layers[self.layers.len] = new_layer;

        self.allocator.free(self.layers);
        self.layers = new_layers;

        // Update config rootfs
        var diff_ids = try self.allocator.alloc([]const u8, self.layers.len);
        for (self.layers, 0..) |l, i| {
            diff_ids[i] = l.diff_id;
        }

        self.config.rootfs.diff_ids = diff_ids;
    }

    pub fn build(self: *Self) !types.ImageManifest {
        // Create config descriptor
        const config_json = try config.serializeConfig(self.allocator, self.config);
        const config_descriptor = types.Descriptor{
            .mediaType = "application/vnd.oci.image.config.v1+json",
            .size = @intCast(config_json.len),
            .digest = try calculateDigest(self.allocator, config_json),
        };

        // Create layer descriptors
        var layer_descriptors = try self.allocator.alloc(types.Descriptor, self.layers.len);
        for (self.layers, 0..) |l, i| {
            layer_descriptors[i] = layer.createDescriptor(l);
        }

        // Create and validate manifest
        self.manifest = try manifest.createManifest(
            self.allocator,
            config_descriptor,
            layer_descriptors,
            null,
        );

        return self.manifest;
    }

    fn calculateDigest(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(data);
        
        var hash: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        hasher.final(&hash);
        
        return try std.fmt.allocPrint(allocator, "sha256:{s}", .{std.fmt.fmtSliceHexLower(&hash)});
    }
}; 