const std = @import("std");
const Allocator = std.mem.Allocator;

/// Тип сховища
pub const StorageType = enum {
    /// Локальне сховище
    local,
    /// NFS сховище
    nfs,
    /// ZFS пул
    zfs,
    /// LVM група томів
    lvm,
};

/// Конфігурація сховища
pub const StorageConfig = struct {
    /// Ідентифікатор сховища
    id: []const u8,
    /// Тип сховища
    storage_type: StorageType,
    /// Шлях до сховища
    path: []const u8,
    /// Розмір диску за замовчуванням (в GB)
    default_size: u32,

    pub fn deinit(self: *StorageConfig, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.path);
    }
};

/// Конфігурація диску контейнера
pub const DiskConfig = struct {
    /// Ідентифікатор сховища
    storage_id: []const u8,
    /// Розмір диску (в GB)
    size: u32,
    /// Формат диску (raw, qcow2, тощо)
    format: []const u8,

    pub fn deinit(self: *DiskConfig, allocator: Allocator) void {
        allocator.free(self.storage_id);
        allocator.free(self.format);
    }
};

/// Тип образу контейнера
pub const ImageType = enum {
    /// Базовий образ
    base,
    /// Шаблон
    template,
    /// Знімок
    snapshot,
};

/// Конфігурація образу
pub const ImageConfig = struct {
    /// Ідентифікатор образу
    id: []const u8,
    /// Назва образу
    name: []const u8,
    /// Тип образу
    image_type: ImageType,
    /// Версія образу
    version: []const u8,
    /// Шлях до образу
    path: []const u8,
    /// Розмір образу (в байтах)
    size: u64,
    /// Хеш образу
    hash: []const u8,

    pub fn deinit(self: *ImageConfig, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.path);
        allocator.free(self.hash);
    }
};

/// Менеджер сховища
pub const StorageManager = struct {
    allocator: Allocator,
    storages: std.StringHashMap(StorageConfig),
    images: std.StringHashMap(ImageConfig),

    const Self = @This();

    /// Створює новий менеджер сховища
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .storages = std.StringHashMap(StorageConfig).init(allocator),
            .images = std.StringHashMap(ImageConfig).init(allocator),
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var storages_it = self.storages.iterator();
        while (storages_it.next()) |entry| {
            var storage = entry.value_ptr;
            storage.deinit(self.allocator);
        }
        self.storages.deinit();

        var images_it = self.images.iterator();
        while (images_it.next()) |entry| {
            var image = entry.value_ptr;
            image.deinit(self.allocator);
        }
        self.images.deinit();
    }

    /// Додає нове сховище
    pub fn addStorage(self: *Self, config: StorageConfig) !void {
        const id = try self.allocator.dupe(u8, config.id);
        errdefer self.allocator.free(id);

        try self.storages.put(id, config);
    }

    /// Отримує конфігурацію сховища за ID
    pub fn getStorage(self: Self, id: []const u8) ?StorageConfig {
        return self.storages.get(id);
    }

    /// Додає новий образ
    pub fn addImage(self: *Self, config: ImageConfig) !void {
        const id = try self.allocator.dupe(u8, config.id);
        errdefer self.allocator.free(id);

        try self.images.put(id, config);
    }

    /// Отримує конфігурацію образу за ID
    pub fn getImage(self: Self, id: []const u8) ?ImageConfig {
        return self.images.get(id);
    }

    /// Створює новий диск для контейнера
    pub fn createDisk(self: *Self, storage_id: []const u8, disk_config: DiskConfig) !void {
        const storage = self.getStorage(storage_id) orelse return error.StorageNotFound;

        // TODO: Реалізувати створення диску в залежності від типу сховища
        switch (storage.storage_type) {
            .local => {
                // Створення локального диску
            },
            .nfs => {
                // Створення диску на NFS
            },
            .zfs => {
                // Створення ZFS тому
            },
            .lvm => {
                // Створення LVM тому
            },
        }
    }

    /// Видаляє диск контейнера
    pub fn deleteDisk(self: *Self, storage_id: []const u8, disk_path: []const u8) !void {
        const storage = self.getStorage(storage_id) orelse return error.StorageNotFound;

        // TODO: Реалізувати видалення диску в залежності від типу сховища
        switch (storage.storage_type) {
            .local => {
                // Видалення локального диску
            },
            .nfs => {
                // Видалення диску на NFS
            },
            .zfs => {
                // Видалення ZFS тому
            },
            .lvm => {
                // Видалення LVM тому
            },
        }
    }
}; 