# BFC OCI Image Integration

BFC (Binary File Container) інтегровано як OCI image storage format для зберігання контейнерних образів на ZFS.

## Огляд

BFC - це легка, append-only файлова система контейнерів в одному файлі, написана на чистому C. Вона інтегрована як додатковий шар для зберігання OCI образів на ZFS.

## Архітектура

```
OCI Image Manifest
        ↓
   BFC Image Handler
        ↓
   ZFS Dataset (tank/images/<image>)
        ↓
   BFC Container File (<image>.bfc)
```

## Основні компоненти

### BFCImageHandler

Основний клас для роботи з BFC як OCI image storage:

```zig
const bfc_handler = oci_image.BFCImageHandler.init(allocator, logger, zfs_manager);
```

#### Методи:

- `createImage(image_name, manifest_path)` - створює BFC образ з OCI manifest
- `createImageFromDirectory(image_name, source_dir)` - створює BFC образ з директорії
- `extractImage(image_name, target_path)` - витягує BFC образ до ZFS dataset
- `listImages()` - список доступних BFC образів
- `deleteImage(image_name)` - видаляє BFC образ
- `getImageInfo(image_name)` - отримує інформацію про образ

### BFCImageInfo

Структура з інформацією про BFC образ:

```zig
pub const BFCImageInfo = struct {
    name: []const u8,
    size: u64,
    created: u64,
    compression: []const u8,
    encryption: []const u8,
};
```

## Використання

### Створення BFC образу з директорії

```zig
try bfc_handler.createImageFromDirectory("ubuntu:20.04", "/tmp/ubuntu-rootfs");
```

### Створення BFC образу з OCI manifest

```zig
try bfc_handler.createImage("nginx:latest", "/path/to/manifest.json");
```

### Витягування BFC образу

```zig
try bfc_handler.extractImage("ubuntu:20.04", "tank/containers/ubuntu-20.04");
```

### Отримання списку образів

```zig
const images = try bfc_handler.listImages();
defer allocator.free(images);

for (images) |image| {
    std.log.info("Image: {s}", .{image});
}
```

### Отримання інформації про образ

```zig
const image_info = try bfc_handler.getImageInfo("ubuntu:20.04");
defer image_info.deinit(allocator);

std.log.info("Size: {d} bytes", .{image_info.size});
std.log.info("Compression: {s}", .{image_info.compression});
```

## ZFS Integration

BFC образи зберігаються в ZFS datasets:

- **Шлях**: `tank/images/<image_name>/`
- **BFC файл**: `tank/images/<image_name>/<image_name>.bfc`
- **Метадані**: зберігаються в ZFS properties

## Переваги BFC для OCI образів

1. **Компактність**: Один файл для всього образу
2. **Швидкість**: Швидкий доступ до файлів
3. **Цілісність**: Вбудована перевірка CRC32c
4. **Стиснення**: Підтримка zstd стиснення
5. **Шифрування**: Підтримка ChaCha20-Poly1305
6. **ZFS сумісність**: Інтеграція з ZFS snapshots та clones

## Майбутні покращення

1. **OCI Manifest Parsing**: Повна підтримка OCI manifest format
2. **Layer Management**: Управління OCI layers в BFC
3. **Registry Integration**: Синхронізація з OCI registries
4. **Compression Optimization**: Автоматичне вибор стиснення
5. **Encryption Support**: Шифрування образів

## Приклад використання

Дивіться `examples/bfc_image_example.zig` для повного прикладу використання BFC OCI image handler.
