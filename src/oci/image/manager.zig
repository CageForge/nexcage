const std = @import("std");
const types = @import("types.zig");
const umoci = @import("umoci.zig");

pub const ImageError = error{
    ImageNotFound,
    InvalidImage,
    InvalidTag,
    BundleError,
};

pub const ImageManager = struct {
    allocator: std.mem.Allocator,
    umoci_tool: *umoci.Umoci,
    images_dir: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, umoci_path: []const u8, images_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .umoci_tool = try umoci.Umoci.init(allocator, umoci_path),
            .images_dir = try allocator.dupe(u8, images_dir),
        };

        // Створюємо директорію для образів якщо вона не існує
        try std.fs.cwd().makePath(images_dir);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.umoci_tool.deinit();
        self.allocator.free(self.images_dir);
        self.allocator.destroy(self);
    }

    pub fn unpackImage(self: *Self, image_name: []const u8, tag: []const u8, bundle_path: []const u8) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        // Перевіряємо чи існує образ
        const image_dir = std.fs.openDirAbsolute(image_path, .{}) catch {
            return ImageError.ImageNotFound;
        };
        image_dir.close();

        try self.umoci_tool.unpack(image_path, tag, bundle_path);
    }

    pub fn repackImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.repack(image_path, tag, bundle_path);

        if (config) |cfg| {
            try self.umoci_tool.config(image_path, tag, cfg);
        }
    }

    pub fn configureImage(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        config: types.ImageConfig,
    ) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.config(image_path, tag, config);
    }

    pub fn garbageCollect(self: *Self, image_name: []const u8) !void {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        try self.umoci_tool.gc(image_path);
    }

    pub fn createBundle(
        self: *Self,
        image_name: []const u8,
        tag: []const u8,
        bundle_path: []const u8,
        config: ?types.ImageConfig,
    ) !void {
        // Створюємо bundle директорію
        try std.fs.cwd().makePath(bundle_path);

        // Розпаковуємо образ
        try self.unpackImage(image_name, tag, bundle_path);

        // Конфігуруємо якщо потрібно
        if (config) |cfg| {
            try self.configureImage(image_name, tag, cfg);
        }
    }
};
