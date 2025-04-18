const std = @import("std");
const Container = @import("container.zig").Container;
const Spec = @import("spec.zig").Spec;
const Allocator = std.mem.Allocator;

/// Тип події життєвого циклу контейнера
pub const ContainerEvent = enum {
    /// Контейнер створено
    Created,
    /// Контейнер запущено
    Started,
    /// Контейнер зупинено
    Stopped,
    /// Контейнер видалено
    Deleted,
};

/// Інтерфейс для плагінів контейнера
pub const ContainerPlugin = struct {
    /// Контекст плагіна
    context: *anyopaque,
    
    /// Функція ініціалізації плагіна
    initFn: *const fn(context: *anyopaque) anyerror!void,
    
    /// Функція деініціалізації плагіна
    deinitFn: *const fn(context: *anyopaque) void,
    
    /// Обробник подій життєвого циклу контейнера
    handleEventFn: *const fn(
        context: *anyopaque,
        container: *Container,
        event: ContainerEvent,
    ) anyerror!void,
    
    /// Функція для виконання команди в контейнері
    execFn: ?*const fn(
        context: *anyopaque,
        container: *Container,
        command: []const []const u8,
    ) anyerror!void,

    /// Ініціалізує плагін
    pub fn init(self: *ContainerPlugin) !void {
        try self.initFn(self.context);
    }

    /// Звільняє ресурси плагіна
    pub fn deinit(self: *ContainerPlugin) void {
        self.deinitFn(self.context);
    }

    /// Обробляє подію контейнера
    pub fn handleEvent(self: *ContainerPlugin, container: *Container, event: ContainerEvent) !void {
        try self.handleEventFn(self.context, container, event);
    }

    /// Виконує команду в контейнері
    pub fn exec(self: *ContainerPlugin, container: *Container, command: []const []const u8) !void {
        if (self.execFn) |execFn| {
            try execFn(self.context, container, command);
        }
    }
};

/// Менеджер плагінів
pub const PluginManager = struct {
    allocator: Allocator,
    plugins: std.ArrayList(*ContainerPlugin),

    const Self = @This();

    /// Створює новий менеджер плагінів
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .plugins = std.ArrayList(*ContainerPlugin).init(allocator),
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        for (self.plugins.items) |plugin| {
            plugin.deinit();
        }
        self.plugins.deinit();
    }

    /// Додає плагін
    pub fn addPlugin(self: *Self, plugin: *ContainerPlugin) !void {
        try plugin.init();
        try self.plugins.append(plugin);
    }

    /// Видаляє плагін
    pub fn removePlugin(self: *Self, plugin: *ContainerPlugin) void {
        for (self.plugins.items, 0..) |p, i| {
            if (p == plugin) {
                _ = self.plugins.orderedRemove(i);
                plugin.deinit();
                break;
            }
        }
    }

    /// Сповіщає всі плагіни про подію
    pub fn notifyEvent(self: *Self, container: *Container, event: ContainerEvent) !void {
        for (self.plugins.items) |plugin| {
            plugin.handleEvent(container, event) catch |err| {
                std.log.err("Plugin error handling event {s}: {any}", .{@tagName(event), err});
            };
        }
    }

    /// Виконує команду через всі плагіни, які підтримують виконання команд
    pub fn execCommand(self: *Self, container: *Container, command: []const []const u8) !void {
        for (self.plugins.items) |plugin| {
            plugin.exec(container, command) catch |err| {
                std.log.err("Plugin error executing command: {any}", .{err});
            };
        }
    }
}; 