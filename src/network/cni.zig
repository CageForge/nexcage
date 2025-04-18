const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

/// CNI версія, яку ми підтримуємо
pub const CNI_VERSION = "0.3.1";

/// Типи CNI операцій
pub const CNICommand = enum {
    add,
    del,
    check,
};

/// Конфігурація CNI плагіна
pub const CNIConfig = struct {
    cni_version: []const u8,
    name: []const u8,
    type: []const u8,
    args: ?std.StringHashMap([]const u8) = null,
    
    /// Парсить конфігурацію з JSON
    pub fn fromJson(allocator: Allocator, data: []const u8) !CNIConfig {
        var parsed = try json.parseFromSlice(std.json.Value, allocator, data, .{});
        defer parsed.deinit();

        return CNIConfig{
            .cni_version = try allocator.dupe(u8, parsed.value.object.get("cniVersion").?.string),
            .name = try allocator.dupe(u8, parsed.value.object.get("name").?.string),
            .type = try allocator.dupe(u8, parsed.value.object.get("type").?.string),
            .args = null, // TODO: parse args
        };
    }

    /// Серіалізує конфігурацію в JSON
    pub fn toJson(self: CNIConfig, allocator: Allocator) ![]const u8 {
        var root = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        
        try root.object.put("cniVersion", .{ .string = self.cni_version });
        try root.object.put("name", .{ .string = self.name });
        try root.object.put("type", .{ .string = self.type });

        if (self.args) |args| {
            var args_obj = std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
            var it = args.iterator();
            while (it.next()) |entry| {
                try args_obj.object.put(entry.key_ptr.*, .{ .string = entry.value_ptr.* });
            }
            try root.object.put("args", args_obj);
        }

        return try std.json.stringify(root, .{}, allocator);
    }
};

/// Результат виконання CNI операції
pub const CNIResult = struct {
    success: bool,
    message: ?[]const u8,
    error: ?CNIError,
    
    pub const CNIError = struct {
        code: u32,
        msg: []const u8,
        details: ?[]const u8,
    };
};

/// CNI Plugin інтерфейс
pub const CNIPlugin = struct {
    allocator: Allocator,
    config: CNIConfig,
    plugin_path: []const u8,
    
    const Self = @This();
    
    /// Створює новий екземпляр CNI плагіна
    pub fn init(allocator: Allocator, config: CNIConfig, plugin_path: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .config = config,
            .plugin_path = try allocator.dupe(u8, plugin_path),
        };
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.plugin_path);
        self.allocator.destroy(self);
    }
    
    /// Виконує CNI операцію
    pub fn exec(self: *Self, cmd: CNICommand, container_id: []const u8, netns: []const u8) !CNIResult {
        // Підготовка оточення для CNI плагіна
        var env = std.process.EnvMap.init(self.allocator);
        defer env.deinit();
        
        try env.put("CNI_COMMAND", @tagName(cmd));
        try env.put("CNI_CONTAINERID", container_id);
        try env.put("CNI_NETNS", netns);
        try env.put("CNI_IFNAME", "eth0"); // TODO: make configurable
        try env.put("CNI_PATH", "/opt/cni/bin"); // TODO: make configurable
        
        // Серіалізуємо конфігурацію
        const config_json = try self.config.toJson(self.allocator);
        defer self.allocator.free(config_json);
        
        // Створюємо процес CNI плагіна
        var process = std.ChildProcess.init(&[_][]const u8{self.plugin_path}, self.allocator);
        process.env_map = &env;
        process.stdin_behavior = .Pipe;
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;
        
        try process.spawn();
        
        // Відправляємо конфігурацію через stdin
        try process.stdin.?.writeAll(config_json);
        try process.stdin.?.close();
        
        // Читаємо результат
        const stdout = try process.stdout.?.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(stdout);
        
        const stderr = try process.stderr.?.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(stderr);
        
        const term = try process.wait();
        
        // Обробляємо результат
        if (term.Exited == 0) {
            return CNIResult{
                .success = true,
                .message = try self.allocator.dupe(u8, stdout),
                .error = null,
            };
        } else {
            return CNIResult{
                .success = false,
                .message = null,
                .error = .{
                    .code = term.Exited,
                    .msg = try self.allocator.dupe(u8, stderr),
                    .details = null,
                },
            };
        }
    }
}; 