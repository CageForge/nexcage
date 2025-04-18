const std = @import("std");
const json = std.json;
const net = std.net;
const os = std.os;

pub const CNIError = error{
    InvalidConfig,
    NetworkCreateFailed,
    NetworkDeleteFailed,
    NetworkCheckFailed,
    PluginNotFound,
    CommandFailed,
};

/// CNI версія, яку ми підтримуємо
pub const CNI_VERSION = "1.0.0";

/// Базова конфігурація CNI
pub const CNIConfig = struct {
    /// Назва мережі
    name: []const u8,
    /// Тип CNI плагіна
    type: []const u8,
    /// Версія CNI
    cniVersion: []const u8,
    /// Додаткові параметри плагіна
    args: ?std.StringHashMap([]const u8) = null,
};

/// Результат виконання CNI операції
pub const CNIResult = struct {
    /// Версія CNI
    cniVersion: []const u8,
    /// IP адреси
    ips: ?[]IPConfig = null,
    /// DNS налаштування
    dns: ?DNSConfig = null,
    /// Маршрути
    routes: ?[]Route = null,
};

pub const IPConfig = struct {
    /// Версія IP (4 або 6)
    version: []const u8,
    /// IP адреса
    address: []const u8,
    /// Gateway
    gateway: ?[]const u8 = null,
};

pub const DNSConfig = struct {
    /// DNS сервери
    nameservers: [][]const u8,
    /// Пошукові домени
    search: [][]const u8,
    /// Опції
    options: [][]const u8,
};

pub const Route = struct {
    /// Призначення
    dst: []const u8,
    /// Gateway
    gw: ?[]const u8 = null,
};

/// CNI плагін
pub const CNIPlugin = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: CNIConfig,
    plugin_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, config: CNIConfig, plugin_dir: []const u8) !Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .plugin_dir = try allocator.dupe(u8, plugin_dir),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.config.args) |*args| {
            args.deinit();
        }
        self.allocator.free(self.plugin_dir);
    }

    /// Додає контейнер до мережі
    pub fn add(self: *Self, container_id: []const u8, netns: []const u8) !CNIResult {
        return self.execPlugin("ADD", .{
            .container_id = container_id,
            .netns = netns,
        });
    }

    /// Видаляє контейнер з мережі
    pub fn delete(self: *Self, container_id: []const u8, netns: []const u8) !void {
        _ = try self.execPlugin("DEL", .{
            .container_id = container_id,
            .netns = netns,
        });
    }

    /// Перевіряє стан мережі контейнера
    pub fn check(self: *Self, container_id: []const u8, netns: []const u8) !void {
        _ = try self.execPlugin("CHECK", .{
            .container_id = container_id,
            .netns = netns,
        });
    }

    /// Виконує CNI плагін
    fn execPlugin(self: *Self, cmd: []const u8, args: struct {
        container_id: []const u8,
        netns: []const u8,
    }) !CNIResult {
        const plugin_path = try std.fs.path.join(self.allocator, 
            &[_][]const u8{self.plugin_dir, self.config.type});
        defer self.allocator.free(plugin_path);

        // Перевіряємо чи існує плагін
        const plugin_stat = try std.fs.cwd().statFile(plugin_path);
        if (plugin_stat.kind != .file) {
            return error.PluginNotFound;
        }

        // Готуємо змінні оточення
        var env = std.process.EnvMap.init(self.allocator);
        defer env.deinit();

        try env.put("CNI_COMMAND", cmd);
        try env.put("CNI_CONTAINERID", args.container_id);
        try env.put("CNI_NETNS", args.netns);
        try env.put("CNI_IFNAME", "eth0");
        try env.put("CNI_VERSION", CNI_VERSION);

        // Серіалізуємо конфігурацію в JSON
        var config_json = std.ArrayList(u8).init(self.allocator);
        defer config_json.deinit();
        try json.stringify(self.config, .{}, config_json.writer());
        try env.put("CNI_ARGS", config_json.items);

        // Виконуємо плагін
        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{plugin_path},
            .env_map = &env,
        });
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }

        if (result.term.Exited != 0) {
            return error.CommandFailed;
        }

        // Парсимо результат
        var parser = json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(result.stdout);
        defer tree.deinit();

        const root = tree.root;
        return try json.parse(CNIResult, &root, .{
            .allocator = self.allocator,
        });
    }
}; 