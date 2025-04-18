const std = @import("std");
const container = @import("container.zig");

pub const PodConfig = struct {
    /// Унікальний ідентифікатор Pod-а
    id: []const u8,
    /// Назва Pod-а
    name: []const u8,
    /// Простір імен Pod-а
    namespace: []const u8,
    /// Конфігурація образу
    image: ImageConfig,
    /// Конфігурація сховища
    storage: StorageConfig,
    /// Анотації Pod-а
    annotations: std.StringHashMap([]const u8),
    /// Мережеві налаштування
    network: NetworkConfig,
    /// Ресурси Pod-а
    resources: ResourceConfig,
};

pub const ImageConfig = struct {
    /// URL для завантаження образу
    url: []const u8,
    /// Локальний шлях до образу
    path: []const u8,
    /// Тип файлової системи образу
    fs_type: []const u8,
    /// Додаткові опції монтування
    mount_options: ?[]const u8,
    /// Тип образу
    type: ImageType,
};

pub const ImageType = enum {
    /// Стандартний LXC template
    template,
    /// Готовий rootfs
    rootfs,
    /// Docker образ
    docker,
};

pub const StorageConfig = struct {
    /// Тип сховища
    type: StorageType,
    /// Розмір сховища в байтах
    size: u64,
    /// Шлях до сховища
    path: []const u8,
    /// Додаткові опції
    options: ?[]const u8,
};

pub const StorageType = enum {
    /// ZFS dataset
    zfs,
    /// Raw образ
    raw,
    /// Директорія
    dir,
};

pub const NetworkConfig = struct {
    /// Режим мережі
    mode: NetworkMode,
    /// DNS налаштування
    dns: DnsConfig,
    /// Порти для проксіювання
    port_mappings: []PortMapping,
};

pub const NetworkMode = enum {
    host,
    bridge,
    none,
};

pub const DnsConfig = struct {
    /// DNS сервери
    servers: [][]const u8,
    /// Пошукові домени
    search: [][]const u8,
    /// Опції DNS
    options: [][]const u8,
};

pub const PortMapping = struct {
    /// Протокол (tcp/udp)
    protocol: Protocol,
    /// Порт контейнера
    container_port: u16,
    /// Порт хоста
    host_port: u16,
    /// Адреса хоста для прив'язки
    host_ip: ?[]const u8,
};

pub const Protocol = enum {
    tcp,
    udp,
};

pub const ResourceConfig = struct {
    /// Ліміти CPU
    cpu: CpuConfig,
    /// Ліміти пам'яті
    memory: MemoryConfig,
};

pub const CpuConfig = struct {
    /// Кількість ядер CPU
    cores: u32,
    /// Ліміт CPU в процентах (1-100)
    limit: u32,
};

pub const MemoryConfig = struct {
    /// Ліміт пам'яті в байтах
    limit: u64,
    /// Резервація пам'яті в байтах
    reservation: u64,
}; 