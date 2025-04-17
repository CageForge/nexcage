const std = @import("std");
const Container = @import("container.zig").Container;
const ContainerError = @import("container.zig").ContainerError;
const Spec = @import("spec.zig").Spec;
const proxmox = @import("proxmox");
const plugin = @import("plugin.zig");
const Allocator = std.mem.Allocator;

/// Помилки, які можуть виникнути при роботі з Runtime
pub const RuntimeError = error{
    /// Помилка ініціалізації
    InitError,
    /// Помилка створення контейнера
    CreateError,
    /// Помилка запуску контейнера
    StartError,
    /// Помилка зупинки контейнера
    StopError,
    /// Помилка видалення контейнера
    DeleteError,
    /// Помилка отримання стану контейнера
    StateError,
    /// Контейнер не знайдено
    NotFound,
    /// Помилка SSH з'єднання
    SshError,
    /// Помилка Proxmox API
    ProxmoxError,
} || ContainerError;

/// Структура для управління контейнерами через Proxmox
pub const Runtime = struct {
    allocator: Allocator,
    containers: std.StringHashMap(*Container),
    proxmox_client: *proxmox.ProxmoxClient,
    plugin_manager: plugin.PluginManager,

    const Self = @This();

    /// Створює новий екземпляр Runtime
    pub fn init(allocator: Allocator, proxmox_client: *proxmox.ProxmoxClient) !Self {
        return Self{
            .allocator = allocator,
            .containers = std.StringHashMap(*Container).init(allocator),
            .proxmox_client = proxmox_client,
            .plugin_manager = plugin.PluginManager.init(allocator),
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var it = self.containers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.containers.deinit();
        self.plugin_manager.deinit();
    }

    /// Додає плагін
    pub fn addPlugin(self: *Self, p: *plugin.ContainerPlugin) !void {
        try self.plugin_manager.addPlugin(p);
    }

    /// Видаляє плагін
    pub fn removePlugin(self: *Self, p: *plugin.ContainerPlugin) void {
        self.plugin_manager.removePlugin(p);
    }

    /// Створює новий контейнер
    pub fn createContainer(self: *Self, metadata: *ContainerMetadata, spec: *Spec) !*Container {
        // Перевіряємо чи не існує вже контейнер з таким ID
        if (self.containers.get(metadata.id)) |_| {
            return RuntimeError.CreateError;
        }

        // Створюємо новий контейнер
        var container = try Container.init(self.allocator, metadata, spec);
        errdefer container.deinit();

        // Додаємо контейнер до списку
        try self.containers.put(metadata.id, container);

        // Викликаємо хуки створення контейнера
        try self.plugin_manager.onContainerCreate(container);

        return container;
    }

    /// Запускає контейнер
    pub fn startContainer(self: *Self, container_id: []const u8) !void {
        // Отримуємо контейнер
        var container = self.containers.get(container_id) orelse return RuntimeError.NotFound;

        // Запускаємо контейнер
        try container.start();

        // Викликаємо хуки запуску контейнера
        try self.plugin_manager.onContainerStart(container);
    }

    /// Зупиняє контейнер
    pub fn stopContainer(self: *Self, container_id: []const u8) !void {
        // Отримуємо контейнер
        var container = self.containers.get(container_id) orelse return RuntimeError.NotFound;

        // Зупиняємо контейнер
        try container.stop();

        // Викликаємо хуки зупинки контейнера
        try self.plugin_manager.onContainerStop(container);
    }

    /// Видаляє контейнер
    pub fn deleteContainer(self: *Self, container_id: []const u8) !void {
        // Отримуємо контейнер
        var container = self.containers.get(container_id) orelse return RuntimeError.NotFound;

        // Викликаємо хуки видалення контейнера
        try self.plugin_manager.onContainerDelete(container);

        // Видаляємо контейнер зі списку
        _ = self.containers.remove(container_id);

        // Звільняємо ресурси контейнера
        container.deinit();
    }

    /// Отримує контейнер за ID
    pub fn getContainer(self: *Self, container_id: []const u8) !*Container {
        return self.containers.get(container_id) orelse return RuntimeError.NotFound;
    }

    /// Отримує список всіх контейнерів
    pub fn listContainers(self: *Self) !std.ArrayList(*Container) {
        var containers = std.ArrayList(*Container).init(self.allocator);
        errdefer containers.deinit();

        var it = self.containers.iterator();
        while (it.next()) |entry| {
            try containers.append(entry.value_ptr.*);
        }

        return containers;
    }

    /// Виконує команду в контейнері через плагіни
    pub fn execInContainer(self: *Self, id: []const u8, command: []const []const u8) !void {
        const container = self.containers.get(id) orelse return RuntimeError.NotFound;
        try self.plugin_manager.execCommand(container, command);
    }
}; 