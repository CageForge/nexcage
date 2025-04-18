const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;

pub const RuntimeError = error{
    CreationError,
    StartError,
    StopError,
    DeleteError,
    NotFound,
    InvalidState,
    ConfigurationError,
    ResourceError,
    NetworkError,
};

/// Базовий інтерфейс для runtime контейнерів
pub const RuntimeInterface = struct {
    /// Тип runtime
    pub const RuntimeType = enum {
        oci,
        cri,
    };

    /// Стан контейнера
    pub const State = enum {
        created,
        running,
        stopped,
        paused,
        deleting,
    };

    /// Конфігурація runtime
    pub const Config = struct {
        runtime_type: RuntimeType,
        root_dir: []const u8,
        state_dir: []const u8,
        network_plugin: ?[]const u8 = null,
    };

    /// Метадані контейнера
    pub const Metadata = struct {
        id: []const u8,
        name: []const u8,
        created_at: i128,
        labels: std.StringHashMap([]const u8),
        annotations: std.StringHashMap([]const u8),

        pub fn init(allocator: Allocator, id: []const u8, name: []const u8) !Metadata {
            return Metadata{
                .id = try allocator.dupe(u8, id),
                .name = try allocator.dupe(u8, name),
                .created_at = std.time.nanoTimestamp(),
                .labels = std.StringHashMap([]const u8).init(allocator),
                .annotations = std.StringHashMap([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Metadata, allocator: Allocator) void {
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
    };

    /// Інтерфейс для життєвого циклу контейнера
    pub const Lifecycle = struct {
        /// Створення контейнера
        createFn: *const fn (self: *RuntimeInterface, config: types.ContainerConfig) RuntimeError!void,
        /// Запуск контейнера
        startFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Зупинка контейнера
        stopFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Видалення контейнера
        deleteFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Отримання стану контейнера
        stateFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!State,
    };

    /// Інтерфейс для роботи з ресурсами
    pub const Resources = struct {
        /// Оновлення ресурсів контейнера
        updateFn: *const fn (self: *RuntimeInterface, id: []const u8, resources: types.Resources) RuntimeError!void,
        /// Отримання статистики використання ресурсів
        statsFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!types.ResourceStats,
    };

    /// Дані runtime
    allocator: Allocator,
    config: Config,
    lifecycle: Lifecycle,
    resources: Resources,

    /// Ініціалізація runtime
    pub fn init(allocator: Allocator, config: Config, lifecycle: Lifecycle, resources: Resources) RuntimeInterface {
        return .{
            .allocator = allocator,
            .config = config,
            .lifecycle = lifecycle,
            .resources = resources,
        };
    }

    /// Створення контейнера
    pub fn create(self: *RuntimeInterface, config: types.ContainerConfig) RuntimeError!void {
        return self.lifecycle.createFn(self, config);
    }

    /// Запуск контейнера
    pub fn start(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        return self.lifecycle.startFn(self, id);
    }

    /// Зупинка контейнера
    pub fn stop(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        return self.lifecycle.stopFn(self, id);
    }

    /// Видалення контейнера
    pub fn delete(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        return self.lifecycle.deleteFn(self, id);
    }

    /// Отримання стану контейнера
    pub fn state(self: *RuntimeInterface, id: []const u8) RuntimeError!State {
        return self.lifecycle.stateFn(self, id);
    }

    /// Оновлення ресурсів контейнера
    pub fn updateResources(self: *RuntimeInterface, id: []const u8, resources: types.Resources) RuntimeError!void {
        return self.resources.updateFn(self, id, resources);
    }

    /// Отримання статистики використання ресурсів
    pub fn stats(self: *RuntimeInterface, id: []const u8) RuntimeError!types.ResourceStats {
        return self.resources.statsFn(self, id);
    }
}; 