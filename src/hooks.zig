const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;

pub const HookError = error{
    ExecutionError,
    TimeoutError,
    ValidationError,
    ResourceError,
};

/// Менеджер хуків для контейнерів
pub const HooksManager = struct {
    allocator: Allocator,
    hooks_dir: []const u8,
    timeout_ms: u64,

    const Self = @This();

    /// Структура для хука
    const Hook = struct {
        path: []const u8,
        args: []const []const u8,
        env: std.StringHashMap([]const u8),
        timeout_ms: ?u64,

        fn init(allocator: Allocator) Hook {
            return .{
                .path = "",
                .args = &[_][]const u8{},
                .env = std.StringHashMap([]const u8).init(allocator),
                .timeout_ms = null,
            };
        }

        fn deinit(self: *Hook) void {
            self.env.deinit();
        }
    };

    /// Ініціалізує менеджер хуків
    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.hooks_dir = try allocator.dupe(u8, "/etc/proxmox-lxcri/hooks");
        self.timeout_ms = 5000; // 5 секунд за замовчуванням

        return self;
    }

    /// Звільняє ресурси
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hooks_dir);
        self.allocator.destroy(self);
    }

    /// Виконує prestart хуки
    pub fn runPrestart(self: *Self, container: anytype) HookError!void {
        var hook = Hook.init(self.allocator);
        defer hook.deinit();

        // Додаємо змінні оточення
        try hook.env.put("CONTAINER_ID", container.id);
        try hook.env.put("CONTAINER_STATE", @tagName(container.state));
        
        if (container.resources) |res| {
            try hook.env.put("CONTAINER_MEMORY_LIMIT", try std.fmt.allocPrint(
                self.allocator,
                "{}",
                .{res.memory.limit},
            ));
            try hook.env.put("CONTAINER_CPU_SHARES", try std.fmt.allocPrint(
                self.allocator,
                "{}",
                .{res.cpu.shares},
            ));
        }

        // Виконуємо хуки з prestart директорії
        try self.executeHooks("prestart", &hook);
    }

    /// Виконує poststart хуки
    pub fn runPoststart(self: *Self, container: anytype) HookError!void {
        var hook = Hook.init(self.allocator);
        defer hook.deinit();

        // Додаємо змінні оточення
        try hook.env.put("CONTAINER_ID", container.id);
        try hook.env.put("CONTAINER_STATE", @tagName(container.state));
        
        if (container.network) |net| {
            try hook.env.put("CONTAINER_IP", net.ip_address);
            try hook.env.put("CONTAINER_INTERFACE", net.interface);
        }

        // Виконуємо хуки з poststart директорії
        try self.executeHooks("poststart", &hook);
    }

    /// Виконує poststop хуки
    pub fn runPoststop(self: *Self, container: anytype) HookError!void {
        var hook = Hook.init(self.allocator);
        defer hook.deinit();

        // Додаємо змінні оточення
        try hook.env.put("CONTAINER_ID", container.id);
        try hook.env.put("CONTAINER_STATE", @tagName(container.state));

        // Виконуємо хуки з poststop директорії 
        try self.executeHooks("poststop", &hook);
    }

    /// Виконує всі хуки з вказаної директорії
    fn executeHooks(self: *Self, hook_type: []const u8, hook: *Hook) HookError!void {
        const hooks_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.hooks_dir, hook_type },
        );
        defer self.allocator.free(hooks_path);

        var dir = std.fs.openDirAbsolute(hooks_path, .{}) catch |err| {
            std.log.err("Failed to open hooks directory: {s}", .{@errorName(err)});
            return HookError.ExecutionError;
        };
        defer dir.close();

        var it = dir.iterate();
        while (it.next() catch |err| {
            std.log.err("Failed to iterate hooks directory: {s}", .{@errorName(err)});
            return HookError.ExecutionError;
        }) |entry| {
            if (entry.kind != .File) continue;

            const hook_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ hooks_path, entry.name },
            );
            defer self.allocator.free(hook_path);

            // Встановлюємо шлях до хука
            hook.path = hook_path;

            // Виконуємо хук з таймаутом
            try self.executeHook(hook);
        }
    }

    /// Виконує окремий хук
    fn executeHook(self: *Self, hook: *Hook) HookError!void {
        const timeout = hook.timeout_ms orelse self.timeout_ms;

        var process = std.ChildProcess.init(
            &[_][]const u8{hook.path},
            self.allocator,
        );

        // Встановлюємо змінні оточення
        var env_list = std.ArrayList([]const u8).init(self.allocator);
        defer env_list.deinit();

        var env_it = hook.env.iterator();
        while (env_it.next()) |entry| {
            const env_str = try std.fmt.allocPrint(
                self.allocator,
                "{s}={s}",
                .{ entry.key_ptr.*, entry.value_ptr.* },
            );
            try env_list.append(env_str);
        }

        process.env = env_list.items;

        // Запускаємо процес
        try process.spawn();

        // Чекаємо завершення з таймаутом
        const result = process.wait() catch |err| {
            std.log.err("Failed to wait for hook process: {s}", .{@errorName(err)});
            return HookError.ExecutionError;
        };

        if (result != 0) {
            std.log.err("Hook failed with exit code: {}", .{result});
            return HookError.ExecutionError;
        }
    }
}; 