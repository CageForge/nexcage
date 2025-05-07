const std = @import("std");
const http = std.http;
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const crypto = std.crypto;
const base64 = std.base64;
const Sha256 = crypto.hash.sha2.Sha256;
const logger = std.log.scoped(.oci_registry);

pub const RegistryError = error{
    InvalidImage,
    InvalidTag,
    InvalidManifest,
    InvalidConfig,
    InvalidLayer,
    DownloadFailed,
    AuthenticationFailed,
    InvalidResponse,
    OutOfMemory,
};

pub const Registry = struct {
    allocator: mem.Allocator,
    base_url: []const u8,
    username: ?[]const u8,
    password: ?[]const u8,
    client: http.Client,

    const Self = @This();

    pub fn init(
        allocator: mem.Allocator,
        base_url: []const u8,
        username: ?[]const u8,
        password: ?[]const u8,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .base_url = try allocator.dupe(u8, base_url),
            .username = if (username) |u| try allocator.dupe(u8, u) else null,
            .password = if (password) |p| try allocator.dupe(u8, p) else null,
            .client = http.Client{ .allocator = allocator },
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
        self.allocator.free(self.base_url);
        if (self.username) |u| self.allocator.free(u);
        if (self.password) |p| self.allocator.free(p);
        self.allocator.destroy(self);
    }

    pub fn downloadImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        output_dir: []const u8,
    ) !void {
        logger.info("Downloading image {s}:{s}", .{ image_name, tag });

        // Get image manifest
        const manifest = try self.getManifest(image_name, tag);
        defer manifest.deinit();

        // Create directory for the image
        const image_dir = try fs.path.join(self.allocator, &[_][]const u8{ output_dir, image_name });
        defer self.allocator.free(image_dir);
        try fs.cwd().makePath(image_dir);

        // Download configuration
        const config = try self.downloadBlob(
            image_name,
            manifest.value.config.digest,
            image_dir,
        );

        // Download layers
        for (manifest.value.layers) |layer| {
            try self.downloadBlob(image_name, layer.digest, image_dir);
        }

        logger.info("Image {s}:{s} downloaded successfully", .{ image_name, tag });
    }

    fn getManifest(self: *Self, image_name: []const u8, tag: []const u8) !json.Parsed(json.Value) {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v2/{s}/manifests/{s}",
            .{ self.base_url, image_name, tag },
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();

        try headers.append("Accept", "application/vnd.oci.image.manifest.v1+json");
        if (self.username != null and self.password != null) {
            try self.addAuthHeader(&headers);
        }

        var response = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .headers = headers,
        });
        defer response.deinit();

        if (response.status != .ok) {
            return RegistryError.InvalidResponse;
        }

        const body = try response.body.readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(body);

        return json.parseFromSlice(json.Value, self.allocator, body, .{});
    }

    fn downloadBlob(
        self: *Self,
        image_name: []const u8,
        digest: []const u8,
        output_dir: []const u8,
    ) !void {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}/v2/{s}/blobs/{s}",
            .{ self.base_url, image_name, digest },
        );
        defer self.allocator.free(url);

        var headers = http.Headers.init(self.allocator);
        defer headers.deinit();

        if (self.username != null and self.password != null) {
            try self.addAuthHeader(&headers);
        }

        var response = try self.client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .headers = headers,
        });
        defer response.deinit();

        if (response.status != .ok) {
            return RegistryError.DownloadFailed;
        }

        const output_path = try fs.path.join(
            self.allocator,
            &[_][]const u8{ output_dir, digest[7..] }, // Skip "sha256:" prefix
        );
        defer self.allocator.free(output_path);

        const file = try fs.cwd().createFile(output_path, .{});
        defer file.close();

        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try response.body.read(&buffer);
            if (bytes_read == 0) break;
            try file.writeAll(buffer[0..bytes_read]);
        }
    }

    fn addAuthHeader(self: *Self, headers: *http.Headers) !void {
        const auth = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{s}",
            .{ self.username.?, self.password.? },
        );
        defer self.allocator.free(auth);

        const encoded = try base64.standard.Encoder.encode(
            self.allocator,
            auth,
        );
        defer self.allocator.free(encoded);

        try headers.append("Authorization", try std.fmt.allocPrint(
            self.allocator,
            "Basic {s}",
            .{encoded},
        ));
    }
}; 