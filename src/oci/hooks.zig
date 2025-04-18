const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;

/// Типи хуків життєвого циклу
pub const HookType = enum {
    prestart,  // Перед запуском контейнера
    poststart, // Після запуску контейнера
    poststop,  // Після зупинки контейнера
};

/// Структура для хука
pub const Hook = struct {
    path: []const u8,           // Шлях до виконуваного файлу
    args: []const []const u8,   // Аргументи
    env: []const []const u8,    // Змінні середовища
    timeout: ?i64,              // Таймаут виконання в секундах
    
    const Self = @This();
    
    /// Створює новий хук
    pub fn init(
        allocator: Allocator,
        path: []const u8,
        args: []const []const u8,
        env: []const []const u8,
        timeout: ?i64,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        self.* = .{
            .path = try allocator.dupe(u8, path),
            .args = try allocator.dupe([]const u8, args),
            .env = try allocator.dupe([]const u8, env),
            .timeout = timeout,
        };
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.path);
        for (self.args) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.args);
        for (self.env) |env_var| {
            allocator.free(env_var);
        }
        allocator.free(self.env);
        allocator.destroy(self);
    }
    
    /// Виконує хук
    pub fn execute(self: *Self) !void {
        var process = std.ChildProcess.init(
            &[_][]const u8{self.path},
            self.allocator,
        );
        
        process.argv = self.args;
        process.env = self.env;
        
        // Встановлюємо таймаут якщо він вказаний
        if (self.timeout) |timeout| {
            process.timeout_ns = timeout * std.time.ns_per_s;
        }
        
        try process.spawn();
        
        const result = try process.wait();
        if (result != 0) {
            return error.HookExecutionFailed;
        }
    }
};

/// Менеджер хуків
pub const HookManager = struct {
    allocator: Allocator,
    prestart_hooks: std.ArrayList(*Hook),
    poststart_hooks: std.ArrayList(*Hook),
    poststop_hooks: std.ArrayList(*Hook),
    
    const Self = @This();
    
    /// Створює новий менеджер хуків
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .prestart_hooks = std.ArrayList(*Hook).init(allocator),
            .poststart_hooks = std.ArrayList(*Hook).init(allocator),
            .poststop_hooks = std.ArrayList(*Hook).init(allocator),
        };
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        for (self.prestart_hooks.items) |hook| {
            hook.deinit(self.allocator);
        }
        self.prestart_hooks.deinit();
        
        for (self.poststart_hooks.items) |hook| {
            hook.deinit(self.allocator);
        }
        self.poststart_hooks.deinit();
        
        for (self.poststop_hooks.items) |hook| {
            hook.deinit(self.allocator);
        }
        self.poststop_hooks.deinit();
    }
    
    /// Додає новий хук
    pub fn addHook(self: *Self, hook_type: HookType, hook: *Hook) !void {
        switch (hook_type) {
            .prestart => try self.prestart_hooks.append(hook),
            .poststart => try self.poststart_hooks.append(hook),
            .poststop => try self.poststop_hooks.append(hook),
        }
    }
    
    /// Виконує всі хуки вказаного типу
    pub fn executeHooks(self: *Self, hook_type: HookType) !void {
        const hooks = switch (hook_type) {
            .prestart => self.prestart_hooks.items,
            .poststart => self.poststart_hooks.items,
            .poststop => self.poststop_hooks.items,
        };
        
        for (hooks) |hook| {
            try hook.execute();
        }
    }
}; 