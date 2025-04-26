const std = @import("std");
const http = std.http;
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const crypto = std.crypto;
const Allocator = std.mem.Allocator;
const logger = @import("logger");
const types = @import("types");
const fmt = std.fmt;
const Uri = std.Uri;
const Headers = http.Headers;
const json_helper = @import("json_helper.zig");

pub const ImageManager = struct {
    allocator: Allocator,
    logger: *logger.Logger,
    image_store_path: []const u8,
    layer_cache_path: []const u8,

    const Self = @This();

    pub const Image = struct {
        id: []const u8,
        name: []const u8,
        tag: []const u8,
        digest: []const u8,
        size: u64,
        created: i64,
        rootfs_path: []const u8,
    };

    pub const ImageConfig = struct {
        architecture: []const u8,
        os: []const u8,
        config: struct {
            env: [][]const u8,
            cmd: [][]const u8,
            entrypoint: [][]const u8,
            working_dir: []const u8,
            user: []const u8,
        },
    };

    pub const Layer = struct {
        digest: []const u8,
        size: u64,
        media_type: []const u8,
        urls: [][]const u8,
    };

    pub const Manifest = struct {
        schema_version: u32,
        media_type: []const u8,
        config: struct {
            digest: []const u8,
            media_type: []const u8,
            size: u64,
        },
        layers: []Layer,
    };

    pub fn init(allocator: Allocator, logger_instance: *logger.Logger) !Self {
        const image_store_path = try fs.path.join(allocator, &.{"/var/lib/lxc-runtime/images"});
        const layer_cache_path = try fs.path.join(allocator, &.{"/var/lib/lxc-runtime/layers"});

        // Create directories if they don't exist
        fs.cwd().makePath(image_store_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        fs.cwd().makePath(layer_cache_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return Self{
            .allocator = allocator,
            .logger = logger_instance,
            .image_store_path = image_store_path,
            .layer_cache_path = layer_cache_path,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.image_store_path);
        self.allocator.free(self.layer_cache_path);
    }

    pub fn pullImage(self: *Self, image_ref: []const u8) !Image {
        // Parse image reference (e.g., "ubuntu:20.04" or "docker.io/library/ubuntu:20.04")
        const ref = try self.parseImageReference(image_ref);
        const name = ref.name;
        const tag = ref.tag;

        // Get image manifest
        const manifest = try self.fetchManifest(name, tag);
        defer self.allocator.free(manifest);

        // Download and verify image config
        const config = try self.fetchImageConfig(manifest.config.digest);
        defer self.allocator.free(config);

        // Create image directory
        const image_id = try self.generateImageId(manifest);
        const image_path = try fs.path.join(self.allocator, &.{ self.image_store_path, image_id });
        defer self.allocator.free(image_path);

        try fs.cwd().makePath(image_path);

        // Download and extract layers
        const rootfs_path = try fs.path.join(self.allocator, &.{ image_path, "rootfs" });
        defer self.allocator.free(rootfs_path);

        try fs.cwd().makePath(rootfs_path);
        try self.extractLayers(manifest.layers, rootfs_path);

        // Create and return image metadata
        return Image{
            .id = image_id,
            .name = name,
            .tag = tag,
            .digest = manifest.config.digest,
            .size = blk: {
                var total: u64 = 0;
                for (manifest.layers) |layer| {
                    total += layer.size;
                }
                break :blk total;
            },
            .created = std.time.timestamp(),
            .rootfs_path = rootfs_path,
        };
    }

    fn parseImageReference(self: *Self, ref: []const u8) !struct { name: []const u8, tag: []const u8 } {
        // Default to latest if no tag is specified
        const default_tag = "latest";

        // Split on last colon to separate name and tag
        if (mem.lastIndexOf(u8, ref, ":")) |colon_index| {
            const name = ref[0..colon_index];
            const tag = ref[colon_index + 1 ..];

            // Validate tag format
            if (tag.len == 0) {
                return error.InvalidImageReference;
            }

            return .{
                .name = try self.allocator.dupe(u8, name),
                .tag = try self.allocator.dupe(u8, tag),
            };
        }

        // No tag specified, use default
        return .{
            .name = try self.allocator.dupe(u8, ref),
            .tag = try self.allocator.dupe(u8, default_tag),
        };
    }

    fn fetchManifest(self: *Self, name: []const u8, tag: []const u8) !Manifest {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Construct registry URL
        const registry = "https://registry-1.docker.io";
        const path = try fmt.allocPrint(self.allocator, "/v2/{s}/manifests/{s}", .{ name, tag });
        defer self.allocator.free(path);

        var uri = try Uri.parse(registry);
        uri.path = path;

        // Set up request
        var headers = Headers.init(self.allocator);
        defer headers.deinit();
        try headers.append("Accept", "application/vnd.docker.distribution.manifest.v2+json");

        // Make request
        var req = try client.request(.GET, uri, headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        if (req.response.status != .ok) {
            return error.ManifestFetchFailed;
        }

        // Read response body
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        try req.reader().readAllArrayList(&body, 1024 * 1024); // 1MB limit

        // Parse manifest
        var scanner = try json_helper.createScanner(self.allocator, body.items);
        defer scanner.deinit();

        try json_helper.expectToken(&scanner, .object_begin);

        var schema_version: ?i64 = null;
        var media_type: ?[]const u8 = null;
        var config_digest: ?[]const u8 = null;
        var config_media_type: ?[]const u8 = null;
        var config_size: ?i64 = null;
        var layers = std.ArrayList(Layer).init(self.allocator);
        errdefer {
            for (layers.items) |layer| {
                self.allocator.free(layer.digest);
                self.allocator.free(layer.media_type);
            }
            layers.deinit();
        }

        while (true) {
            const token = try scanner.next();
            if (token == .object_end) break;
            if (token != .string) return error.InvalidManifest;

            const key = token.string;

            if (std.mem.eql(u8, key, "schemaVersion")) {
                schema_version = try json_helper.parseNumber(scanner, i64);
            } else if (std.mem.eql(u8, key, "mediaType")) {
                media_type = try json_helper.parseString(self.allocator, scanner);
            } else if (std.mem.eql(u8, key, "config")) {
                try json_helper.expectToken(&scanner, .object_begin);
                
                while (true) {
                    const token = try scanner.next();
                    if (token == .object_end) break;
                    if (token != .string) return error.InvalidManifest;

                    const config_key = token.string;

                    if (std.mem.eql(u8, config_key, "digest")) {
                        config_digest = try json_helper.parseString(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "mediaType")) {
                        config_media_type = try json_helper.parseString(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "size")) {
                        config_size = try json_helper.parseNumber(scanner, i64);
                    } else {
                        try json_helper.skipValue(&scanner);
                    }
                }
            } else if (std.mem.eql(u8, key, "layers")) {
                try json_helper.expectToken(&scanner, .array_begin);

                while (true) {
                    const layer_token = try scanner.next();
                    if (layer_token == .array_end) break;
                    if (layer_token != .object_begin) return error.InvalidManifest;

                    var layer_digest: ?[]const u8 = null;
                    var layer_media_type: ?[]const u8 = null;
                    var layer_size: ?i64 = null;

                    while (true) {
                        const layer_field_token = try scanner.next();
                        if (layer_field_token == .object_end) break;
                        if (layer_field_token != .string) return error.InvalidManifest;

                        const layer_key = layer_field_token.string;

                        if (std.mem.eql(u8, layer_key, "digest")) {
                            layer_digest = try json_helper.parseString(self.allocator, scanner);
                        } else if (std.mem.eql(u8, layer_key, "mediaType")) {
                            layer_media_type = try json_helper.parseString(self.allocator, scanner);
                        } else if (std.mem.eql(u8, layer_key, "size")) {
                            layer_size = try json_helper.parseNumber(scanner, i64);
                        } else {
                            try json_helper.skipValue(&scanner);
                        }
                    }

                    if (layer_digest == null or layer_media_type == null or layer_size == null) {
                        return error.InvalidManifest;
                    }

                    try layers.append(Layer{
                        .digest = layer_digest.?,
                        .media_type = layer_media_type.?,
                        .size = @intCast(layer_size.?),
                        .urls = &.{},
                    });
                }
            } else {
                try json_helper.skipValue(&scanner);
            }
        }

        if (schema_version == null or media_type == null or config_digest == null or 
            config_media_type == null or config_size == null) {
            return error.InvalidManifest;
        }

        return Manifest{
            .schema_version = @intCast(schema_version.?),
            .media_type = media_type.?,
            .config = .{
                .digest = config_digest.?,
                .media_type = config_media_type.?,
                .size = @intCast(config_size.?),
            },
            .layers = try layers.toOwnedSlice(),
        };
    }

    fn fetchImageConfig(self: *Self, digest: []const u8) !ImageConfig {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Construct registry URL
        const registry = "https://registry-1.docker.io";
        const path = try fmt.allocPrint(self.allocator, "/v2/blobs/{s}", .{digest});
        defer self.allocator.free(path);

        var uri = try Uri.parse(registry);
        uri.path = path;

        // Set up request
        var headers = Headers.init(self.allocator);
        defer headers.deinit();

        // Make request
        var req = try client.request(.GET, uri, headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        if (req.response.status != .ok) {
            return error.ConfigFetchFailed;
        }

        // Read response body
        var body = std.ArrayList(u8).init(self.allocator);
        defer body.deinit();
        try req.reader().readAllArrayList(&body, 1024 * 1024); // 1MB limit

        // Parse config
        var scanner = try json_helper.createScanner(self.allocator, body.items);
        defer scanner.deinit();

        try json_helper.expectToken(&scanner, .object_begin);

        var architecture: ?[]const u8 = null;
        var os: ?[]const u8 = null;
        var env_list = std.ArrayList([]const u8).init(self.allocator);
        var cmd_list = std.ArrayList([]const u8).init(self.allocator);
        var entrypoint_list = std.ArrayList([]const u8).init(self.allocator);
        var working_dir: ?[]const u8 = null;
        var user: ?[]const u8 = null;

        errdefer {
            if (architecture) |a| self.allocator.free(a);
            if (os) |o| self.allocator.free(o);
            for (env_list.items) |e| self.allocator.free(e);
            env_list.deinit();
            for (cmd_list.items) |c| self.allocator.free(c);
            cmd_list.deinit();
            for (entrypoint_list.items) |e| self.allocator.free(e);
            entrypoint_list.deinit();
            if (working_dir) |w| self.allocator.free(w);
            if (user) |u| self.allocator.free(u);
        }

        while (true) {
            const token = try scanner.next();
            if (token == .object_end) break;
            if (token != .string) return error.InvalidConfig;

            const key = token.string;

            if (std.mem.eql(u8, key, "architecture")) {
                architecture = try json_helper.parseString(self.allocator, scanner);
            } else if (std.mem.eql(u8, key, "os")) {
                os = try json_helper.parseString(self.allocator, scanner);
            } else if (std.mem.eql(u8, key, "config")) {
                try json_helper.expectToken(&scanner, .object_begin);

                while (true) {
                    const token = try scanner.next();
                    if (token == .object_end) break;
                    if (token != .string) return error.InvalidConfig;

                    const config_key = token.string;

                    if (std.mem.eql(u8, config_key, "Env")) {
                        env_list = try json_helper.parseStringArray(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "Cmd")) {
                        cmd_list = try json_helper.parseStringArray(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "Entrypoint")) {
                        entrypoint_list = try json_helper.parseStringArray(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "WorkingDir")) {
                        working_dir = try json_helper.parseString(self.allocator, scanner);
                    } else if (std.mem.eql(u8, config_key, "User")) {
                        user = try json_helper.parseString(self.allocator, scanner);
                    } else {
                        try json_helper.skipValue(&scanner);
                    }
                }
            } else {
                try json_helper.skipValue(&scanner);
            }
        }

        if (architecture == null or os == null) {
            return error.InvalidConfig;
        }

        return ImageConfig{
            .architecture = architecture.?,
            .os = os.?,
            .config = .{
                .env = try env_list.toOwnedSlice(),
                .cmd = try cmd_list.toOwnedSlice(),
                .entrypoint = try entrypoint_list.toOwnedSlice(),
                .working_dir = working_dir orelse try self.allocator.dupe(u8, "/"),
                .user = user orelse try self.allocator.dupe(u8, ""),
            },
        };
    }

    fn generateImageId(self: *Self, manifest: Manifest) ![]const u8 {
        // Create a hash of the manifest config digest and layers
        var hasher = crypto.hash.sha256.init(.{});

        // Hash the config digest
        hasher.update(manifest.config.digest);

        // Hash each layer digest
        for (manifest.layers) |layer| {
            hasher.update(layer.digest);
        }

        // Finalize the hash
        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        // Convert to hex string
        const hex = try self.allocator.alloc(u8, 64);
        _ = try fmt.bufPrint(hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});

        return hex;
    }

    fn extractLayers(self: *Self, layers: []Layer, rootfs_path: []const u8) !void {
        // Create a temporary directory for layer extraction
        const tmp_dir = try fs.path.join(self.allocator, &.{ self.layer_cache_path, "tmp" });
        defer self.allocator.free(tmp_dir);

        try fs.cwd().makePath(tmp_dir);
        defer fs.cwd().deleteTree(tmp_dir) catch |err| {
            self.logger.warn("Failed to clean up temporary directory: {}", .{err});
        };

        // Process each layer in order
        for (layers) |layer| {
            // Check if layer is already cached
            const layer_path = try fs.path.join(self.allocator, &.{ self.layer_cache_path, layer.digest });
            defer self.allocator.free(layer_path);

            if (fs.cwd().statFile(layer_path)) |_| {
                // Layer is cached, extract directly to rootfs
                try self.extractLayer(layer_path, rootfs_path);
            } else |_| {
                // Download and cache the layer
                const layer_tmp = try fs.path.join(self.allocator, &.{ tmp_dir, layer.digest });
                defer self.allocator.free(layer_tmp);

                try self.downloadLayer(layer, layer_tmp);
                try self.cacheLayer(layer_tmp, layer_path);
                try self.extractLayer(layer_path, rootfs_path);
            }
        }
    }

    fn downloadLayer(self: *Self, layer: Layer, dest_path: []const u8) !void {
        var client = http.Client{ .allocator = self.allocator };
        defer client.deinit();

        // Construct registry URL
        const registry = "https://registry-1.docker.io";
        const path = try fmt.allocPrint(self.allocator, "/v2/blobs/{s}", .{layer.digest});
        defer self.allocator.free(path);

        var uri = try Uri.parse(registry);
        uri.path = path;

        // Set up request
        var headers = Headers.init(self.allocator);
        defer headers.deinit();

        // Make request
        var req = try client.request(.GET, uri, headers, .{});
        defer req.deinit();

        try req.start();
        try req.wait();

        if (req.response.status != .ok) {
            return error.LayerDownloadFailed;
        }

        // Create destination file
        const file = try fs.cwd().createFile(dest_path, .{});
        defer file.close();

        // Stream response to file
        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try req.reader().read(&buffer);
            if (bytes_read == 0) break;
            try file.writeAll(buffer[0..bytes_read]);
        }
    }

    fn cacheLayer(self: *const Self, src_path: []const u8, dest_path: []const u8) !void {
        try fs.cwd().rename(src_path, dest_path);
    }

    fn extractLayer(self: *Self, layer_path: []const u8, rootfs_path: []const u8) !void {
        // Open the layer file
        const file = try fs.cwd().openFile(layer_path, .{});
        defer file.close();

        // Create a temporary directory for extraction
        const tmp_extract = try fs.path.join(self.allocator, &.{ self.layer_cache_path, "extract" });
        defer self.allocator.free(tmp_extract);

        try fs.cwd().makePath(tmp_extract);
        defer fs.cwd().deleteTree(tmp_extract) catch |err| {
            self.logger.warn("Failed to clean up extraction directory: {}", .{err});
        };

        // Extract the layer
        var gzip_stream = try std.compress.gzip.decompress(self.allocator, file.reader());
        defer gzip_stream.deinit();

        var tar = std.tar.Reader.init(gzip_stream.reader());
        try tar.extractToFileSystem(tmp_extract);

        // Apply the layer to rootfs
        try self.applyLayer(tmp_extract, rootfs_path);
    }

    fn applyLayer(self: *Self, layer_path: []const u8, rootfs_path: []const u8) !void {
        var dir = try fs.cwd().openDir(layer_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            const src_path = try fs.path.join(self.allocator, &.{ layer_path, entry.path });
            defer self.allocator.free(src_path);

            const dest_path = try fs.path.join(self.allocator, &.{ rootfs_path, entry.path });
            defer self.allocator.free(dest_path);

            switch (entry.kind) {
                .file => {
                    try fs.cwd().copyFile(src_path, fs.cwd(), dest_path, .{});
                },
                .directory => {
                    try fs.cwd().makePath(dest_path);
                },
                .sym_link => {
                    const target = try fs.cwd().readLinkAlloc(self.allocator, src_path);
                    defer self.allocator.free(target);
                    try fs.cwd().symLink(target, dest_path, .{});
                },
                else => continue,
            }
        }
    }

    pub fn listImages(self: *Self) ![]Image {
        var images = std.ArrayList(Image).init(self.allocator);
        errdefer images.deinit();

        var dir = try fs.cwd().openDir(self.image_store_path, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .directory) continue;

            const image_id = entry.basename;
            const image_path = try fs.path.join(self.allocator, &.{ self.image_store_path, image_id });
            defer self.allocator.free(image_path);

            // Check if this is a valid image directory
            if (fs.cwd().statFile(try fs.path.join(self.allocator, &.{ image_path, "rootfs" }))) |_| {
                // Read image metadata
                const metadata_path = try fs.path.join(self.allocator, &.{ image_path, "metadata.json" });
                defer self.allocator.free(metadata_path);

                if (fs.cwd().statFile(metadata_path)) |_| {
                    const file = try fs.cwd().openFile(metadata_path, .{});
                    defer file.close();

                    var parser = json.Parser.init(self.allocator, false);
                    defer parser.deinit();

                    const parsed = try parser.parse(try file.reader().readAllAlloc(self.allocator, 1024 * 1024));
                    defer parsed.deinit();

                    const root = parsed.root;
                    if (root != .object) continue;

                    const name = root.object.get("name") orelse continue;
                    const tag = root.object.get("tag") orelse continue;
                    const digest = root.object.get("digest") orelse continue;
                    const size = root.object.get("size") orelse continue;
                    const created = root.object.get("created") orelse continue;

                    if (name != .string or tag != .string or digest != .string or
                        size != .integer or created != .integer) continue;

                    try images.append(Image{
                        .id = try self.allocator.dupe(u8, image_id),
                        .name = try self.allocator.dupe(u8, name.string),
                        .tag = try self.allocator.dupe(u8, tag.string),
                        .digest = try self.allocator.dupe(u8, digest.string),
                        .size = @intCast(size.integer),
                        .created = @intCast(created.integer),
                        .rootfs_path = try fs.path.join(self.allocator, &.{ image_path, "rootfs" }),
                    });
                }
            }
        }

        return images.toOwnedSlice();
    }

    pub fn removeImage(self: *Self, image_id: []const u8) !void {
        const image_path = try fs.path.join(self.allocator, &.{ self.image_store_path, image_id });
        defer self.allocator.free(image_path);

        // Check if image exists
        if (fs.cwd().statFile(try fs.path.join(self.allocator, &.{ image_path, "rootfs" }))) |_| {
            // Remove image directory
            try fs.cwd().deleteTree(image_path);
        } else |err| {
            if (err != error.FileNotFound) return err;
            return error.ImageNotFound;
        }
    }

    pub fn getImage(self: *Self, image_id: []const u8) !Image {
        // Implementation for getting image details
        _ = self;
        _ = image_id;
        return error.NotImplemented;
    }

    pub fn getImageIdByName(self: *Self, name: []const u8, tag: []const u8) ![]const u8 {
        const images = try self.listImages();
        defer {
            for (images) |img| {
                self.allocator.free(img.id);
                self.allocator.free(img.name);
                self.allocator.free(img.tag);
                self.allocator.free(img.digest);
                self.allocator.free(img.rootfs_path);
            }
            self.allocator.free(images);
        }

        for (images) |img| {
            if (std.mem.eql(u8, img.name, name) and std.mem.eql(u8, img.tag, tag)) {
                return try self.allocator.dupe(u8, img.id);
            }
        }

        return error.ImageNotFound;
    }

    fn verifyLayer(self: *Self, layer_path: []const u8, expected_digest: []const u8) !void {
        const file = try fs.cwd().openFile(layer_path, .{});
        defer file.close();

        var hasher = crypto.hash.sha256.init(.{});
        var buffer: [8192]u8 = undefined;

        while (true) {
            const bytes_read = try file.reader().read(&buffer);
            if (bytes_read == 0) break;
            hasher.update(buffer[0..bytes_read]);
        }

        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        const hex = try self.allocator.alloc(u8, 64);
        defer self.allocator.free(hex);
        _ = try fmt.bufPrint(hex, "{x}", .{std.fmt.fmtSliceHexLower(&hash)});

        if (!std.mem.eql(u8, hex, expected_digest)) {
            return error.LayerVerificationFailed;
        }
    }

    pub fn getRootfsPath(self: *Self, image_id: []const u8) ![]const u8 {
        const image_path = try fs.path.join(self.allocator, &.{ self.image_store_path, image_id });
        defer self.allocator.free(image_path);

        if (fs.cwd().statFile(try fs.path.join(self.allocator, &.{ image_path, "rootfs" }))) |_| {
            return try fs.path.join(self.allocator, &.{ image_path, "rootfs" });
        } else |err| {
            if (err != error.FileNotFound) return err;
            return error.ImageNotFound;
        }
    }
};
