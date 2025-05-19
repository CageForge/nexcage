const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const os = std.os;
const linux = os.linux;
const logger = std.log.scoped(.oci_raw_image);
const types = @import("types.zig");

pub const RawImageError = error{
    InvalidFormat,
    ReadError,
    WriteError,
};

/// Raw image format handler
pub const RawImage = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    size: u64,

    const Self = @This();

    /// Initialize a new raw image handler
    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        size: u64,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .path = try allocator.dupe(u8, path),
            .size = size,
        };
        return self;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.path);
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self) !void {
        logger.info("Creating raw image at {s}", .{self.path});

        // Створюємо файл
        const file = try fs.cwd().createFile(self.path, .{});
        defer file.close();

        // Встановлюємо розмір файлу
        try file.setEndPos(self.size);

        // Створюємо loop device
        self.loop_device = try self.createLoopDevice();

        // Форматуємо файлову систему
        try self.formatFilesystem();

        // Монтуємо файлову систему
        try self.mountFilesystem();

        // Копіюємо дані з OCI образу
        try self.copyImageData();

        // Відмонтовуємо файлову систему
        try self.unmountFilesystem();

        logger.info("Raw image created successfully", .{});
    }

    fn createLoopDevice(self: *Self) ![]const u8 {
        const output = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "losetup", "-f", self.path },
        });
        defer {
            self.allocator.free(output.stdout);
            self.allocator.free(output.stderr);
        }

        if (output.term.Exited != 0) {
            return RawError.LoopError;
        }

        // Видаляємо новий рядок з кінця
        const device = output.stdout[0 .. output.stdout.len - 1];
        return try self.allocator.dupe(u8, device);
    }

    fn formatFilesystem(self: *Self) !void {
        const output = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "mkfs.ext4", self.loop_device.? },
        });
        defer {
            self.allocator.free(output.stdout);
            self.allocator.free(output.stderr);
        }

        if (output.term.Exited != 0) {
            return RawError.FileError;
        }
    }

    fn mountFilesystem(self: *Self) !void {
        const mount_point = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ "/tmp", "oci-raw-mount" },
        );
        defer self.allocator.free(mount_point);

        try fs.cwd().makePath(mount_point);

        const output = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "mount", self.loop_device.?, mount_point },
        });
        defer {
            self.allocator.free(output.stdout);
            self.allocator.free(output.stderr);
        }

        if (output.term.Exited != 0) {
            return RawError.MountError;
        }
    }

    fn copyImageData(self: *Self) !void {
        const mount_point = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ "/tmp", "oci-raw-mount" },
        );
        defer self.allocator.free(mount_point);

        const rootfs = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.path, "rootfs" },
        );
        defer self.allocator.free(rootfs);

        const output = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "cp", "-a", rootfs, mount_point },
        });
        defer {
            self.allocator.free(output.stdout);
            self.allocator.free(output.stderr);
        }

        if (output.term.Exited != 0) {
            return RawError.FileError;
        }
    }

    fn unmountFilesystem(self: *Self) !void {
        const mount_point = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ "/tmp", "oci-raw-mount" },
        );
        defer self.allocator.free(mount_point);

        const output = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "umount", mount_point },
        });
        defer {
            self.allocator.free(output.stdout);
            self.allocator.free(output.stderr);
        }

        if (output.term.Exited != 0) {
            return RawError.MountError;
        }

        try fs.cwd().deleteDir(mount_point);
    }
};
