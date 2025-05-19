const std = @import("std");
const types = @import("types.zig");
const overlay = @import("overlay.zig");
const image = @import("../image.zig");

pub const OverlayManager = struct {
    allocator: std.mem.Allocator,
    overlay_fs: *overlay.OverlayFS,
    layers: std.StringHashMap(types.OverlayLayer),
    mounts: std.StringHashMap(types.OverlayMount),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, root_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .overlay_fs = try overlay.OverlayFS.init(allocator, root_dir),
            .layers = std.StringHashMap(types.OverlayLayer).init(allocator),
            .mounts = std.StringHashMap(types.OverlayMount).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        var layers_it = self.layers.valueIterator();
        while (layers_it.next()) |layer| {
            layer.deinit(self.allocator);
        }
        self.layers.deinit();

        var mounts_it = self.mounts.valueIterator();
        while (mounts_it.next()) |mount| {
            mount.deinit(self.allocator);
        }
        self.mounts.deinit();

        self.overlay_fs.deinit();
        self.allocator.destroy(self);
    }

    pub fn createImageLayers(self: *Self, img: *image.Image) !void {
        for (img.layers) |layer_info| {
            const layer = try self.overlay_fs.createLayer(layer_info.digest, null);
            try self.layers.put(layer.id, layer);

            // Копіюємо дані з шару образу
            try std.fs.copyFile(layer_info.path, layer.path, .{});
        }
    }

    pub fn mountContainer(self: *Self, container_id: []const u8, image_id: []const u8) !void {
        // Знаходимо шари образу
        const layer = self.layers.get(image_id) orelse return types.OverlayError.LayerNotFound;

        // Створюємо та монтуємо overlay
        const mount = try self.overlay_fs.mount(container_id);
        try self.mounts.put(container_id, mount);

        // Копіюємо дані з шару образу в нижній шар контейнера
        try std.fs.copyFile(layer.path, mount.lower_dir, .{});
    }

    pub fn unmountContainer(self: *Self, container_id: []const u8) !void {
        const mount = self.mounts.get(container_id) orelse return types.OverlayError.LayerNotFound;
        try self.overlay_fs.unmount(&mount);
        _ = self.mounts.remove(container_id);
    }

    pub fn removeImageLayers(self: *Self, image_id: []const u8) !void {
        const layer = self.layers.get(image_id) orelse return types.OverlayError.LayerNotFound;
        try self.overlay_fs.removeLayer(&layer);
        _ = self.layers.remove(image_id);
    }
};
