const std = @import("std");
const Allocator = std.mem.Allocator;
const logger_mod = @import("logger");
const errors = @import("error");

pub const ImageManager = struct {
    allocator: Allocator,
    images_dir: []const u8,
    logger: *logger_mod.Logger,

    const Self = @This();

    pub fn init(allocator: Allocator, images_dir: []const u8, log: *logger_mod.Logger) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .images_dir = try allocator.dupe(u8, images_dir),
            .logger = log,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.images_dir);
        self.allocator.destroy(self);
    }

    pub fn imageExists(self: *Self, image_name: []const u8) !bool {
        const image_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.images_dir, image_name });
        defer self.allocator.free(image_path);

        std.fs.accessAbsolute(image_path, .{}) catch |err| {
            if (err == error.FileNotFound) return false;
            return err;
        };
        return true;
    }

    pub fn downloadImage(self: *Self, image_name: []const u8, image_tag: []const u8) !void {
        try self.logger.info("Downloading image {s}:{s}", .{ image_name, image_tag });
        // TODO: Implement image download
    }
};
