const std = @import("std");
const types = @import("../../types.zig");
const Client = @import("../../proxmox/client.zig").Client;
const templates = @import("../../proxmox/lxc/templates.zig");
const fmt = std.fmt;

pub const ImageError = error{
    ImageNotFound,
    InvalidImageRef,
    PullError,
    StorageError,
    NetworkError,
};

pub const ImageService = struct {
    client: *Client,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, client: *Client) Self {
        return Self{
            .client = client,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    // PullImage pulls an image with authentication config.
    pub fn PullImage(self: *Self, image: types.ImageSpec, auth: ?types.AuthConfig) !types.Image {
        try self.client.logger.info("Pulling image {s}", .{image.image});

        // Перевіряємо чи це Proxmox LXC template
        if (!std.mem.startsWith(u8, image.image, "local:vztmpl/")) {
            try self.client.logger.err("Invalid image reference: {s}, must be a Proxmox template", .{image.image});
            return error.InvalidImageRef;
        }

        // Перевіряємо чи шаблон вже існує
        const existing_templates = try templates.listTemplates(self.client);
        defer {
            for (existing_templates) |*template| {
                template.deinit(self.allocator);
            }
            self.allocator.free(existing_templates);
        }

        for (existing_templates) |template| {
            if (std.mem.eql(u8, template.volid, image.image)) {
                return types.Image{
                    .id = try self.allocator.dupe(u8, template.volid),
                    .spec = image,
                    .size_bytes = template.size,
                    .uid = try self.allocator.dupe(u8, "0"),
                    .username = try self.allocator.dupe(u8, "root"),
                };
            }
        }

        // Якщо шаблон не знайдено, завантажуємо його
        if (image.url) |url| {
            const template = try templates.downloadTemplate(self.client, url);
            defer template.deinit(self.allocator);

            return types.Image{
                .id = try self.allocator.dupe(u8, template.volid),
                .spec = image,
                .size_bytes = template.size,
                .uid = try self.allocator.dupe(u8, "0"),
                .username = try self.allocator.dupe(u8, "root"),
            };
        } else {
            try self.client.logger.err("Image URL not provided for pulling new template", .{});
            return error.PullError;
        }
    }

    // ListImages lists existing images.
    pub fn ListImages(self: *Self, filter: ?types.ImageFilter) ![]types.Image {
        try self.client.logger.info("Listing images with filter: {?}", .{filter});
        
        const template_list = try templates.listTemplates(self.client);
        defer {
            for (template_list) |*template| {
                template.deinit(self.allocator);
            }
            self.allocator.free(template_list);
        }

        var images = std.ArrayList(types.Image).init(self.allocator);
        errdefer {
            for (images.items) |*image| {
                self.allocator.free(image.id);
                self.allocator.free(image.uid);
                self.allocator.free(image.username);
            }
            images.deinit();
        }

        for (template_list) |template| {
            // Якщо є фільтр, перевіряємо відповідність
            if (filter) |f| {
                if (f.image) |filter_image| {
                    if (!std.mem.eql(u8, template.volid, filter_image.image)) {
                        continue;
                    }
                }
            }

            try images.append(types.Image{
                .id = try self.allocator.dupe(u8, template.volid),
                .spec = types.ImageSpec{
                    .image = try self.allocator.dupe(u8, template.volid),
                    .url = null,
                },
                .size_bytes = template.size,
                .uid = try self.allocator.dupe(u8, "0"),
                .username = try self.allocator.dupe(u8, "root"),
            });
        }

        return images.toOwnedSlice();
    }

    // ImageStatus returns the status of the image.
    pub fn ImageStatus(self: *Self, image: types.ImageSpec) !types.ImageStatus {
        try self.client.logger.info("Getting status for image {s}", .{image.image});

        const template_list = try templates.listTemplates(self.client);
        defer {
            for (template_list) |*template| {
                template.deinit(self.allocator);
            }
            self.allocator.free(template_list);
        }

        for (template_list) |template| {
            if (std.mem.eql(u8, template.volid, image.image)) {
                return types.ImageStatus{
                    .image = image,
                    .present = true,
                    .size_bytes = template.size,
                };
            }
        }

        return types.ImageStatus{
            .image = image,
            .present = false,
            .size_bytes = 0,
        };
    }

    // RemoveImage removes the image.
    pub fn RemoveImage(self: *Self, image: types.ImageSpec) !void {
        try self.client.logger.info("Removing image {s}", .{image.image});

        try templates.deleteTemplate(self.client, image.image);
    }
}; 