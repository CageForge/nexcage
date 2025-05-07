const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const os = std.os;
const linux = os.linux;
const logger = std.log.scoped(.oci_raw);

pub const RawError = error{
    InvalidImage,
    InvalidLayer,
    InvalidConfig,
    FileError,
    OutOfMemory,
    MountError,
    LoopError,
};

pub const RawImage = struct {
    allocator: mem.Allocator,
    image_dir: []const u8,
    output_path: []const u8,
    size: u64,
    loop_device: ?[]const u8,

    const Self = @This();

    pub fn init(
        allocator: mem.Allocator,
        image_dir: []const u8,
        output_path: []const u8,
        size: u64,
    ) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .image_dir = try allocator.dupe(u8, image_dir),
            .output_path = try allocator.dupe(u8, output_path),
            .size = size,
            .loop_device = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.loop_device) |device| {
            self.allocator.free(device);
        }
        self.allocator.free(self.image_dir);
        self.allocator.free(self.output_path);
        self.allocator.destroy(self);
    }

    pub fn create(self: *Self) !void {
        logger.info("Creating raw image at {s}", .{self.output_path});

        // Створюємо файл
        const file = try fs.cwd().createFile(self.output_path, .{});
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
            .argv = &[_][]const u8{ "losetup", "-f", self.output_path },
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
            &[_][]const u8{ self.image_dir, "rootfs" },
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