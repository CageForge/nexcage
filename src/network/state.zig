const std = @import("std");
const Allocator = std.mem.Allocator;

/// Стан мережевого інтерфейсу
pub const NetworkState = struct {
    container_id: []const u8,
    interface_name: []const u8,
    ip_v4: ?[]const u8,
    ip_v6: ?[]const u8,
    mac: []const u8,
    dns: ?DNSConfig,
    routes: std.ArrayList(Route),
    
    pub const DNSConfig = struct {
        servers: []const []const u8,
        search: []const []const u8,
        options: []const []const u8,
    };
    
    pub const Route = struct {
        destination: []const u8,
        gateway: []const u8,
        interface: []const u8,
    };
    
    /// Створює новий стан мережевого інтерфейсу
    pub fn init(
        allocator: Allocator,
        container_id: []const u8,
        interface_name: []const u8,
        mac: []const u8,
    ) !*NetworkState {
        const self = try allocator.create(NetworkState);
        
        self.* = .{
            .container_id = try allocator.dupe(u8, container_id),
            .interface_name = try allocator.dupe(u8, interface_name),
            .ip_v4 = null,
            .ip_v6 = null,
            .mac = try allocator.dupe(u8, mac),
            .dns = null,
            .routes = std.ArrayList(Route).init(allocator),
        };
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *NetworkState, allocator: Allocator) void {
        allocator.free(self.container_id);
        allocator.free(self.interface_name);
        if (self.ip_v4) |ip| allocator.free(ip);
        if (self.ip_v6) |ip| allocator.free(ip);
        allocator.free(self.mac);
        
        if (self.dns) |dns| {
            for (dns.servers) |server| allocator.free(server);
            for (dns.search) |domain| allocator.free(domain);
            for (dns.options) |opt| allocator.free(opt);
            allocator.free(dns.servers);
            allocator.free(dns.search);
            allocator.free(dns.options);
        }
        
        for (self.routes.items) |route| {
            allocator.free(route.destination);
            allocator.free(route.gateway);
            allocator.free(route.interface);
        }
        self.routes.deinit();
        
        allocator.destroy(self);
    }
};

/// Менеджер мережевого стану
pub const NetworkStateManager = struct {
    allocator: Allocator,
    states: std.StringHashMap(*NetworkState),
    state_dir: []const u8,
    
    const Self = @This();
    
    /// Створює новий менеджер стану
    pub fn init(allocator: Allocator, state_dir: []const u8) !*Self {
        const self = try allocator.create(Self);
        
        self.* = .{
            .allocator = allocator,
            .states = std.StringHashMap(*NetworkState).init(allocator),
            .state_dir = try allocator.dupe(u8, state_dir),
        };
        
        // Створюємо директорію для стану якщо її немає
        try std.fs.makeDirAbsolute(state_dir);
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        var it = self.states.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.states.deinit();
        self.allocator.free(self.state_dir);
        self.allocator.destroy(self);
    }
    
    /// Додає новий стан
    pub fn addState(self: *Self, state: *NetworkState) !void {
        try self.states.put(state.container_id, state);
        try self.saveState(state);
    }
    
    /// Отримує стан за ID контейнера
    pub fn getState(self: *Self, container_id: []const u8) ?*NetworkState {
        return self.states.get(container_id);
    }
    
    /// Видаляє стан
    pub fn removeState(self: *Self, container_id: []const u8) void {
        if (self.states.fetchRemove(container_id)) |entry| {
            entry.value.deinit(self.allocator);
            self.deleteStateFile(container_id) catch {};
        }
    }
    
    /// Зберігає стан на диск
    fn saveState(self: *Self, state: *NetworkState) !void {
        const path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.state_dir,
            state.container_id,
        });
        defer self.allocator.free(path);
        
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();
        
        // Серіалізуємо стан в JSON
        var root = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
        
        try root.object.put("container_id", .{ .string = state.container_id });
        try root.object.put("interface_name", .{ .string = state.interface_name });
        if (state.ip_v4) |ip| {
            try root.object.put("ip_v4", .{ .string = ip });
        }
        if (state.ip_v6) |ip| {
            try root.object.put("ip_v6", .{ .string = ip });
        }
        try root.object.put("mac", .{ .string = state.mac });
        
        if (state.dns) |dns| {
            var dns_obj = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
            
            var servers = std.json.Value{ .array = std.json.Array.init(self.allocator) };
            for (dns.servers) |server| {
                try servers.array.append(.{ .string = server });
            }
            try dns_obj.object.put("servers", servers);
            
            var search = std.json.Value{ .array = std.json.Array.init(self.allocator) };
            for (dns.search) |domain| {
                try search.array.append(.{ .string = domain });
            }
            try dns_obj.object.put("search", search);
            
            var options = std.json.Value{ .array = std.json.Array.init(self.allocator) };
            for (dns.options) |opt| {
                try options.array.append(.{ .string = opt });
            }
            try dns_obj.object.put("options", options);
            
            try root.object.put("dns", dns_obj);
        }
        
        var routes = std.json.Value{ .array = std.json.Array.init(self.allocator) };
        for (state.routes.items) |route| {
            var route_obj = std.json.Value{ .object = std.json.ObjectMap.init(self.allocator) };
            try route_obj.object.put("destination", .{ .string = route.destination });
            try route_obj.object.put("gateway", .{ .string = route.gateway });
            try route_obj.object.put("interface", .{ .string = route.interface });
            try routes.array.append(route_obj);
        }
        try root.object.put("routes", routes);
        
        const json = try std.json.stringify(root, .{}, self.allocator);
        defer self.allocator.free(json);
        
        try file.writeAll(json);
    }
    
    /// Видаляє файл стану
    fn deleteStateFile(self: *Self, container_id: []const u8) !void {
        const path = try std.fs.path.join(self.allocator, &[_][]const u8{
            self.state_dir,
            container_id,
        });
        defer self.allocator.free(path);
        
        std.fs.deleteFileAbsolute(path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }
}; 