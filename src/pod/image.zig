const std = @import("std");
const fs = std.fs;
const os = std.os;
const proxmox = @import("../proxmox/client.zig");

pub const ImageError = error{
    DownloadFailed,
    ExtractFailed,
    ConversionFailed,
    MountFailed,
    InvalidFormat,
    StorageError,
    ZFSError,
};

pub const ImageFormat = enum {
    raw,
    zfs,
};

pub const ImageConfig = struct {
    /// Шлях до образу
    path: []const u8,
    /// Формат образу (raw або zfs)
    format: ImageFormat,
    /// Розмір образу в байтах
    size: u64,
    /// Тип файлової системи
    fs_type: []const u8,
    /// Додаткові опції монтування
    mount_options: ?[]const u8,
};

pub const ImageManager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    proxmox_client: *proxmox.Client,
    storage_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, proxmox_client: *proxmox.Client, storage_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .proxmox_client = proxmox_client,
            .storage_path = try allocator.dupe(u8, storage_path),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.storage_path);
        self.allocator.destroy(self);
    }

    /// Завантажує LXC образ та конвертує його у потрібний формат
    pub fn prepareImage(self: *Self, url: []const u8, config: ImageConfig) ![]const u8 {
        // Створюємо тимчасову директорію для завантаження
        var tmp_dir = try std.fs.makeDirTemp(self.allocator, "lxc_image_");
        defer std.fs.deleteTree(tmp_dir) catch {};

        // Завантажуємо образ
        const downloaded_path = try self.downloadImage(url, tmp_dir);
        defer self.allocator.free(downloaded_path);

        // Перевіряємо формат та конвертуємо якщо потрібно
        const converted_path = try self.convertImage(downloaded_path, config);
        defer self.allocator.free(converted_path);

        // Створюємо фінальний шлях для образу
        const image_name = try std.fs.path.basename(url);
        const final_path = try std.fs.path.join(self.allocator, 
            &[_][]const u8{self.storage_path, image_name});

        // Копіюємо образ у фінальну локацію
        try std.fs.copyFileAbsolute(converted_path, final_path, .{});

        return final_path;
    }

    /// Монтує образ у вказану директорію
    pub fn mountImage(self: *Self, image_path: []const u8, mount_point: []const u8, config: ImageConfig) !void {
        switch (config.format) {
            .raw => try self.mountRawImage(image_path, mount_point, config),
            .zfs => try self.mountZfsDataset(image_path, mount_point, config),
        }
    }

    /// Завантажує образ з URL
    fn downloadImage(self: *Self, url: []const u8, dir: []const u8) ![]const u8 {
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "curl",
                "-L",
                "-o",
                try std.fs.path.join(self.allocator, &[_][]const u8{
                    dir,
                    try std.fs.path.basename(url),
                }),
                url,
            },
        });
        
        if (result.term.Exited != 0) {
            return error.DownloadFailed;
        }

        return try std.fs.path.join(self.allocator, &[_][]const u8{
            dir,
            try std.fs.path.basename(url),
        });
    }

    /// Конвертує образ у потрібний формат
    fn convertImage(self: *Self, input_path: []const u8, config: ImageConfig) ![]const u8 {
        const output_path = try std.fs.path.join(self.allocator, &[_][]const u8{
            std.fs.path.dirname(input_path).?,
            "converted_image",
        });

        switch (config.format) {
            .raw => {
                // Конвертуємо в raw формат якщо потрібно
                const result = try std.ChildProcess.exec(.{
                    .allocator = self.allocator,
                    .argv = &[_][]const u8{
                        "qemu-img",
                        "convert",
                        "-O",
                        "raw",
                        input_path,
                        output_path,
                    },
                });

                if (result.term.Exited != 0) {
                    return error.ConversionFailed;
                }
            },
            .zfs => {
                // Створюємо ZFS dataset
                const dataset_name = try std.fs.path.basename(output_path);
                const result = try std.ChildProcess.exec(.{
                    .allocator = self.allocator,
                    .argv = &[_][]const u8{
                        "zfs",
                        "create",
                        "-V",
                        try std.fmt.allocPrint(self.allocator, "{d}", .{config.size}),
                        dataset_name,
                    },
                });

                if (result.term.Exited != 0) {
                    return error.ZFSError;
                }

                // Копіюємо дані в dataset
                try std.fs.copyFileAbsolute(input_path, output_path, .{});
            },
        }

        return output_path;
    }

    /// Монтує raw образ
    fn mountRawImage(self: *Self, image_path: []const u8, mount_point: []const u8, config: ImageConfig) !void {
        // Створюємо loop пристрій
        const loop_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "losetup",
                "--find",
                "--show",
                image_path,
            },
        });

        if (loop_result.term.Exited != 0) {
            return error.MountFailed;
        }

        const loop_device = std.mem.trim(u8, loop_result.stdout, "\n");
        defer {
            _ = std.ChildProcess.exec(.{
                .allocator = self.allocator,
                .argv = &[_][]const u8{"losetup", "-d", loop_device},
            }) catch {};
        }

        // Монтуємо файлову систему
        const mount_result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "mount",
                "-t",
                config.fs_type,
                if (config.mount_options) |opts|
                    try std.fmt.allocPrint(self.allocator, "-o{s}", .{opts})
                else
                    "",
                loop_device,
                mount_point,
            },
        });

        if (mount_result.term.Exited != 0) {
            return error.MountFailed;
        }
    }

    /// Монтує ZFS dataset
    fn mountZfsDataset(self: *Self, dataset_path: []const u8, mount_point: []const u8, config: ImageConfig) !void {
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "zfs",
                "set",
                try std.fmt.allocPrint(self.allocator, "mountpoint={s}", .{mount_point}),
                dataset_path,
            },
        });

        if (result.term.Exited != 0) {
            return error.MountFailed;
        }
    }
}; 