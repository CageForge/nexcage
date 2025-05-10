const std = @import("std");
const json = std.json;
const net = std.net;
const os = std.os;
const json_helper = @import("../json_helper.zig");

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
        const plugin_path = try std.fs.path.join(self.allocator, &[_][]const u8{ self.plugin_dir, self.config.type });
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
        var scanner = try json_helper.createScanner(self.allocator, result.stdout);
        defer scanner.deinit();

        try json_helper.expectToken(&scanner, .object_begin);

        var cni_version: ?[]const u8 = null;
        var ips = std.ArrayList(IPConfig).init(self.allocator);
        var dns: ?DNSConfig = null;
        var routes = std.ArrayList(Route).init(self.allocator);

        errdefer {
            if (cni_version) |v| self.allocator.free(v);
            for (ips.items) |ip| {
                self.allocator.free(ip.version);
                self.allocator.free(ip.address);
                if (ip.gateway) |g| self.allocator.free(g);
            }
            ips.deinit();
            if (dns) |d| {
                for (d.nameservers) |ns| self.allocator.free(ns);
                for (d.search) |s| self.allocator.free(s);
                for (d.options) |o| self.allocator.free(o);
                self.allocator.free(d.nameservers);
                self.allocator.free(d.search);
                self.allocator.free(d.options);
            }
            for (routes.items) |route| {
                self.allocator.free(route.dst);
                if (route.gw) |g| self.allocator.free(g);
            }
            routes.deinit();
        }

        while (true) {
            const token = try scanner.next();
            if (token == .object_end) break;
            if (token != .string) return error.InvalidConfig;

            const key = token.string;

            if (std.mem.eql(u8, key, "cniVersion")) {
                cni_version = try json_helper.parseString(self.allocator, scanner);
            } else if (std.mem.eql(u8, key, "ips")) {
                try json_helper.expectToken(&scanner, .array_begin);

                while (true) {
                    const ip_token = try scanner.next();
                    if (ip_token == .array_end) break;
                    if (ip_token != .object_begin) return error.InvalidConfig;

                    var ip_version: ?[]const u8 = null;
                    var ip_address: ?[]const u8 = null;
                    var ip_gateway: ?[]const u8 = null;

                    while (true) {
                        const ip_field_token = try scanner.next();
                        if (ip_field_token == .object_end) break;
                        if (ip_field_token != .string) return error.InvalidConfig;

                        const ip_key = ip_field_token.string;

                        if (std.mem.eql(u8, ip_key, "version")) {
                            ip_version = try json_helper.parseString(self.allocator, scanner);
                        } else if (std.mem.eql(u8, ip_key, "address")) {
                            ip_address = try json_helper.parseString(self.allocator, scanner);
                        } else if (std.mem.eql(u8, ip_key, "gateway")) {
                            ip_gateway = try json_helper.parseString(self.allocator, scanner);
                        } else {
                            try json_helper.skipValue(&scanner);
                        }
                    }

                    if (ip_version == null or ip_address == null) {
                        return error.InvalidConfig;
                    }

                    try ips.append(IPConfig{
                        .version = ip_version.?,
                        .address = ip_address.?,
                        .gateway = ip_gateway,
                    });
                }
            } else if (std.mem.eql(u8, key, "dns")) {
                try json_helper.expectToken(&scanner, .object_begin);

                var nameservers = std.ArrayList([]const u8).init(self.allocator);
                var search = std.ArrayList([]const u8).init(self.allocator);
                var options = std.ArrayList([]const u8).init(self.allocator);

                while (true) {
                    const dns_token = try scanner.next();
                    if (dns_token == .object_end) break;
                    if (dns_token != .string) return error.InvalidConfig;

                    const dns_key = dns_token.string;

                    if (std.mem.eql(u8, dns_key, "nameservers")) {
                        nameservers = try json_helper.parseStringArray(self.allocator, scanner);
                    } else if (std.mem.eql(u8, dns_key, "search")) {
                        search = try json_helper.parseStringArray(self.allocator, scanner);
                    } else if (std.mem.eql(u8, dns_key, "options")) {
                        options = try json_helper.parseStringArray(self.allocator, scanner);
                    } else {
                        try json_helper.skipValue(&scanner);
                    }
                }

                dns = DNSConfig{
                    .nameservers = try nameservers.toOwnedSlice(),
                    .search = try search.toOwnedSlice(),
                    .options = try options.toOwnedSlice(),
                };
            } else if (std.mem.eql(u8, key, "routes")) {
                try json_helper.expectToken(&scanner, .array_begin);

                while (true) {
                    const route_token = try scanner.next();
                    if (route_token == .array_end) break;
                    if (route_token != .object_begin) return error.InvalidConfig;

                    var route_dst: ?[]const u8 = null;
                    var route_gw: ?[]const u8 = null;

                    while (true) {
                        const route_field_token = try scanner.next();
                        if (route_field_token == .object_end) break;
                        if (route_field_token != .string) return error.InvalidConfig;

                        const route_key = route_field_token.string;

                        if (std.mem.eql(u8, route_key, "dst")) {
                            route_dst = try json_helper.parseString(self.allocator, scanner);
                        } else if (std.mem.eql(u8, route_key, "gw")) {
                            route_gw = try json_helper.parseString(self.allocator, scanner);
                        } else {
                            try json_helper.skipValue(&scanner);
                        }
                    }

                    if (route_dst == null) {
                        return error.InvalidConfig;
                    }

                    try routes.append(Route{
                        .dst = route_dst.?,
                        .gw = route_gw,
                    });
                }
            } else {
                try json_helper.skipValue(&scanner);
            }
        }

        if (cni_version == null) {
            return error.InvalidConfig;
        }

        return CNIResult{
            .cniVersion = cni_version.?,
            .ips = if (ips.items.len > 0) try ips.toOwnedSlice() else null,
            .dns = dns,
            .routes = if (routes.items.len > 0) try routes.toOwnedSlice() else null,
        };
    }
};
