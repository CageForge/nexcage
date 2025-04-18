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
    HookError,
    MetadataError,
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
        namespace: ?[]const u8,
        labels: std.StringHashMap([]const u8),
        annotations: std.StringHashMap([]const u8),
        created_at: i64,
        
        pub fn init(allocator: Allocator) Metadata {
            return .{
                .id = "",
                .name = "",
                .namespace = null,
                .labels = std.StringHashMap([]const u8).init(allocator),
                .annotations = std.StringHashMap([]const u8).init(allocator),
                .created_at = 0,
            };
        }
        
        pub fn deinit(self: *Metadata) void {
            self.labels.deinit();
            self.annotations.deinit();
        }
    };

    /// Інтерфейс життєвого циклу
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

    /// Інтерфейс для роботи з мережею
    pub const Network = struct {
        /// Налаштування мережі контейнера
        setupFn: *const fn (self: *RuntimeInterface, id: []const u8, config: types.NetworkConfig) RuntimeError!void,
        /// Видалення мережевих налаштувань
        teardownFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Отримання мережевої статистики
        statsFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!types.NetworkStats,
    };

    /// Інтерфейс для роботи з хуками
    pub const Hooks = struct {
        /// Виконання prestart хуків
        prestartFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Виконання poststart хуків
        poststartFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
        /// Виконання poststop хуків
        poststopFn: *const fn (self: *RuntimeInterface, id: []const u8) RuntimeError!void,
    };

    /// Дані runtime
    allocator: Allocator,
    config: Config,
    lifecycle: Lifecycle,
    resources: Resources,
    network: ?Network,
    hooks: ?Hooks,

    /// Ініціалізація runtime
    pub fn init(
        allocator: Allocator,
        config: Config,
        lifecycle: Lifecycle,
        resources: Resources,
        network: ?Network,
        hooks: ?Hooks,
    ) RuntimeInterface {
        return .{
            .allocator = allocator,
            .config = config,
            .lifecycle = lifecycle,
            .resources = resources,
            .network = network,
            .hooks = hooks,
        };
    }

    /// Створення контейнера
    pub fn create(self: *RuntimeInterface, config: types.ContainerConfig) RuntimeError!void {
        return self.lifecycle.createFn(self, config);
    }

    /// Запуск контейнера
    pub fn start(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        // Виконуємо prestart хуки
        if (self.hooks) |hooks| {
            try hooks.prestartFn(self, id);
        }

        // Запускаємо контейнер
        try self.lifecycle.startFn(self, id);

        // Виконуємо poststart хуки
        if (self.hooks) |hooks| {
            try hooks.poststartFn(self, id);
        }
    }

    /// Зупинка контейнера
    pub fn stop(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        // Зупиняємо контейнер
        try self.lifecycle.stopFn(self, id);

        // Виконуємо poststop хуки
        if (self.hooks) |hooks| {
            try hooks.poststopFn(self, id);
        }
    }

    /// Видалення контейнера
    pub fn delete(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        // Видаляємо мережеві налаштування
        if (self.network) |network| {
            try network.teardownFn(self, id);
        }

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
    pub fn resourceStats(self: *RuntimeInterface, id: []const u8) RuntimeError!types.ResourceStats {
        return self.resources.statsFn(self, id);
    }

    /// Налаштування мережі контейнера
    pub fn setupNetwork(self: *RuntimeInterface, id: []const u8, config: types.NetworkConfig) RuntimeError!void {
        if (self.network) |network| {
            return network.setupFn(self, id, config);
        }
        return error.NetworkError;
    }

    /// Видалення мережевих налаштувань
    pub fn teardownNetwork(self: *RuntimeInterface, id: []const u8) RuntimeError!void {
        if (self.network) |network| {
            return network.teardownFn(self, id);
        }
        return error.NetworkError;
    }

    /// Отримання мережевої статистики
    pub fn networkStats(self: *RuntimeInterface, id: []const u8) RuntimeError!types.NetworkStats {
        if (self.network) |network| {
            return network.statsFn(self, id);
        }
        return error.NetworkError;
    }
}; 