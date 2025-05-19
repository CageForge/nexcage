const std = @import("std");
const cni = @import("cni.zig");
const cilium = @import("cilium.zig");
const calico = @import("calico.zig");
const Allocator = std.mem.Allocator;

/// Тип CNI плагіна
pub const CNIPluginType = enum {
    cilium,
    calico,
    flannel, // TODO: додати підтримку
    weave, // TODO: додати підтримку
};

/// Інтерфейс CNI плагіна
pub const CNIPluginInterface = struct {
    /// Тип плагіна
    plugin_type: CNIPluginType,

    /// Додає мережевий інтерфейс до контейнера
    addFn: *const fn (self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult,

    /// Видаляє мережевий інтерфейс з контейнера
    deleteFn: *const fn (self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult,

    /// Перевіряє стан мережевого інтерфейсу
    checkFn: *const fn (self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult,

    /// Звільняє ресурси
    deinitFn: *const fn (self: *CNIPluginInterface) void,

    /// Додає мережевий інтерфейс до контейнера
    pub fn add(self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult {
        return self.addFn(self, container_id, netns);
    }

    /// Видаляє мережевий інтерфейс з контейнера
    pub fn delete(self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult {
        return self.deleteFn(self, container_id, netns);
    }

    /// Перевіряє стан мережевого інтерфейсу
    pub fn check(self: *CNIPluginInterface, container_id: []const u8, netns: []const u8) CNIResult {
        return self.checkFn(self, container_id, netns);
    }

    /// Звільняє ресурси
    pub fn deinit(self: *CNIPluginInterface) void {
        self.deinitFn(self);
    }
};

/// Фабрика для створення CNI плагінів
pub const CNIPluginFactory = struct {
    allocator: Allocator,

    const Self = @This();

    /// Створює нову фабрику
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Створює новий CNI плагін
    pub fn createPlugin(self: *Self, plugin_type: CNIPluginType) !*CNIPluginInterface {
        switch (plugin_type) {
            .cilium => {
                var config = try cilium.CiliumConfig.init(self.allocator, "cilium");
                var plugin = try cilium.CiliumPlugin.init(self.allocator, config);
                return @ptrCast(*CNIPluginInterface, plugin);
            },
            .calico => {
                var config = try calico.CalicoConfig.init(self.allocator, "calico");
                var plugin = try calico.CalicoPlugin.init(self.allocator, config);
                return @ptrCast(*CNIPluginInterface, plugin);
            },
            .flannel => {
                // TODO: реалізувати підтримку Flannel
                return error.NotImplemented;
            },
            .weave => {
                // TODO: реалізувати підтримку Weave
                return error.NotImplemented;
            },
        }
    }
};
