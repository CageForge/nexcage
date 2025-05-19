const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const mem = std.mem;
const logger = std.log.scoped(.image_manager_test);

const ImageManager = @import("../../../src/oci/image/manager.zig").ImageManager;

// Функція для перевірки витоку пам'яті
fn checkMemoryLeaks(allocator: *std.mem.Allocator) !void {
    const info = try allocator.detectLeaks();
    if (info.leak_count > 0) {
        logger.err("Memory leak detected: {d} allocations not freed", .{info.leak_count});
        return error.MemoryLeak;
    }
}

test "Image manager memory management" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try ImageManager.init(allocator);
    defer manager.deinit();

    const image_name = "test-image";
    const image_path = "/tmp/image-test/test.raw";

    // Створюємо темпову директорію для образу
    try fs.cwd().makePath("/tmp/image-test");
    defer fs.cwd().deleteTree("/tmp/image-test") catch {};

    // Створюємо тестовий образ
    try fs.cwd().writeFile(image_path, "test data");
    defer fs.cwd().deleteFile(image_path) catch {};

    // Завантажуємо образ
    try manager.loadImage(image_name, image_path);

    // Перевіряємо чи образ завантажений
    try testing.expect(try manager.imageExists(image_name));

    // Видаляємо образ
    try manager.deleteImage(image_name);

    // Перевіряємо чи образ видалений
    try testing.expect(!try manager.imageExists(image_name));
}

test "Image manager registry operations" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try ImageManager.init(allocator);
    defer manager.deinit();

    const image_name = "test-registry-image";
    const registry_url = "https://registry.example.com";
    const username = "test";
    const password = "test";

    // Завантажуємо образ з реєстру
    try manager.loadImageFromRegistry(image_name, registry_url, username, password);

    // Перевіряємо чи образ завантажений
    try testing.expect(try manager.imageExists(image_name));

    // Отримуємо інформацію про образ
    const image_info = try manager.getImageInfo(image_name);
    defer allocator.free(image_info);
    try testing.expect(image_info.len > 0);

    // Видаляємо образ
    try manager.deleteImage(image_name);

    // Перевіряємо чи образ видалений
    try testing.expect(!try manager.imageExists(image_name));
}

test "Image manager multiple images" {
    const allocator = testing.allocator;
    defer try checkMemoryLeaks(allocator);

    var manager = try ImageManager.init(allocator);
    defer manager.deinit();

    const image_names = [_][]const u8{ "test-image-1", "test-image-2", "test-image-3" };
    const image_path = "/tmp/image-test/test.raw";

    // Створюємо темпову директорію для образів
    try fs.cwd().makePath("/tmp/image-test");
    defer fs.cwd().deleteTree("/tmp/image-test") catch {};

    // Створюємо тестовий образ
    try fs.cwd().writeFile(image_path, "test data");
    defer fs.cwd().deleteFile(image_path) catch {};

    // Завантажуємо кілька образів
    for (image_names) |name| {
        try manager.loadImage(name, image_path);
    }

    // Перевіряємо чи всі образи завантажені
    for (image_names) |name| {
        try testing.expect(try manager.imageExists(name));
    }

    // Отримуємо список образів
    const images = try manager.listImages();
    defer {
        for (images) |image| {
            allocator.free(image);
        }
        allocator.free(images);
    }

    // Перевіряємо чи всі образи присутні в списку
    try testing.expect(images.len >= image_names.len);

    // Видаляємо всі образи
    for (image_names) |name| {
        try manager.deleteImage(name);
    }

    // Перевіряємо чи всі образи видалені
    for (image_names) |name| {
        try testing.expect(!try manager.imageExists(name));
    }
}
