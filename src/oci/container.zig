const std = @import("std");
const spec = @import("spec.zig");
const container_state = @import("container_state.zig");
const Allocator = std.mem.Allocator;

/// Помилки, які можуть виникнути при роботі з контейнером
pub const ContainerError = error{
    /// Помилка при створенні контейнера
    CreationError,
    /// Помилка при видаленні контейнера
    DeletionError,
    /// Помилка при запуску контейнера
    StartError,
    /// Помилка при зупинці контейнера
    StopError,
    /// Помилка при паузі контейнера
    PauseError,
    /// Помилка при відновленні контейнера
    ResumeError,
    /// Помилка при оновленні стану
    StateError,
    /// Контейнер не знайдено
    NotFound,
    /// Неправильний стан контейнера для операції
    InvalidState,
} || container_state.StateError;

/// Структура для зберігання метаданих контейнера
pub const ContainerMetadata = struct {
    /// Унікальний ідентифікатор контейнера
    id: []const u8,
    /// Ім'я контейнера
    name: []const u8,
    /// Час створення (в наносекундах від епохи)
    created_at: i128,
    /// Мітки контейнера
    labels: std.StringHashMap([]const u8),
    /// Анотації контейнера
    annotations: std.StringHashMap([]const u8),

    /// Створює нові метадані контейнера
    pub fn create(allocator: Allocator, id: []const u8, name: []const u8) !ContainerMetadata {
        return ContainerMetadata{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .created_at = std.time.nanoTimestamp(),
            .labels = std.StringHashMap([]const u8).init(allocator),
            .annotations = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *ContainerMetadata, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.name);
        
        var labels_it = self.labels.iterator();
        while (labels_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.labels.deinit();
        
        var annotations_it = self.annotations.iterator();
        while (annotations_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.annotations.deinit();
    }

    /// Додає мітку
    pub fn addLabel(self: *ContainerMetadata, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const key_owned = try allocator.dupe(u8, key);
        errdefer allocator.free(key_owned);
        const value_owned = try allocator.dupe(u8, value);
        errdefer allocator.free(value_owned);
        
        try self.labels.put(key_owned, value_owned);
    }

    /// Додає анотацію
    pub fn addAnnotation(self: *ContainerMetadata, allocator: Allocator, key: []const u8, value: []const u8) !void {
        const key_owned = try allocator.dupe(u8, key);
        errdefer allocator.free(key_owned);
        const value_owned = try allocator.dupe(u8, value);
        errdefer allocator.free(value_owned);
        
        try self.annotations.put(key_owned, value_owned);
    }
};

/// Структура контейнера
pub const Container = struct {
    metadata: ContainerMetadata,
    spec: spec.Spec,
    state: container_state.ContainerState,
    allocator: Allocator,

    const Self = @This();

    /// Створює новий контейнер
    pub fn create(allocator: Allocator, id: []const u8, name: []const u8, container_spec: spec.Spec) !Self {
        return Self{
            .metadata = try ContainerMetadata.create(allocator, id, name),
            .spec = container_spec,
            .state = container_state.ContainerState.init(),
            .allocator = allocator,
        };
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.metadata.deinit(self.allocator);
        self.spec.deinit(self.allocator);
    }

    /// Запускає контейнер
    pub fn start(self: *Self) ContainerError!void {
        try self.state.transitionTo(.running);
    }

    /// Зупиняє контейнер
    pub fn stop(self: *Self) ContainerError!void {
        try self.state.transitionTo(.stopped);
    }

    /// Призупиняє контейнер
    pub fn pause(self: *Self) ContainerError!void {
        try self.state.transitionTo(.paused);
    }

    /// Відновлює роботу контейнера
    pub fn resumeContainer(self: *Self) ContainerError!void {
        try self.state.transitionTo(.running);
    }

    /// Видаляє контейнер
    pub fn delete(self: *Self) ContainerError!void {
        try self.state.transitionTo(.deleting);
    }

    /// Отримує поточний стан контейнера
    pub fn getState(self: Self) container_state.State {
        return self.state.state;
    }

    /// Встановлює PID головного процесу контейнера
    pub fn setPid(self: *Self, pid: i32) void {
        self.state.setPid(pid);
    }

    /// Встановлює код виходу та причину зупинки
    pub fn setExit(self: *Self, code: i32, reason: ?[]const u8) void {
        self.state.setExit(code, reason);
    }
}; 