const std = @import("std");
const oci = @import("../oci/hooks.zig");
const Allocator = std.mem.Allocator;

/// CRI-O специфічні типи хуків
pub const CrioHookType = enum {
    prestart,      // Перед запуском контейнера
    poststart,     // Після запуску контейнера
    poststop,      // Після зупинки контейнера
    precreate,     // Перед створенням контейнера
    postpinning,   // Після закріплення ресурсів
};

/// Структура для CRI-O хука
pub const CrioHook = struct {
    hook: oci.Hook,           // Базовий OCI хук
    stage: CrioHookType,      // Етап виконання
    when: ?struct {           // Умови виконання
        annotations: std.StringHashMap([]const u8),
        commands: [][]const u8,
        has_bind_mounts: bool,
        has_mount_options: bool,
    },
    
    const Self = @This();
    
    /// Створює новий CRI-O хук
    pub fn init(
        allocator: Allocator,
        path: []const u8,
        args: []const []const u8,
        env: []const []const u8,
        timeout: ?i64,
        stage: CrioHookType,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        
        const base_hook = try oci.Hook.init(allocator, path, args, env, timeout);
        errdefer base_hook.deinit(allocator);
        
        self.* = .{
            .hook = base_hook.*,
            .stage = stage,
            .when = null,
        };
        
        return self;
    }
    
    /// Звільняє ресурси
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.when) |when| {
            var it = when.annotations.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            when.annotations.deinit();
            
            for (when.commands) |cmd| {
                allocator.free(cmd);
            }
            allocator.free(when.commands);
        }
        
        self.hook.deinit(allocator);
        allocator.destroy(self);
    }
    
    /// Встановлює умови виконання
    pub fn setConditions(
        self: *Self,
        allocator: Allocator,
        annotations: ?std.StringHashMap([]const u8),
        commands: ?[][]const u8,
        has_bind_mounts: bool,
        has_mount_options: bool,
    ) !void {
        if (self.when != null) return error.ConditionsAlreadySet;
        
        self.when = .{
            .annotations = if (annotations) |a| try a.clone() else std.StringHashMap([]const u8).init(allocator),
            .commands = if (commands) |c| try allocator.dupe([]const u8, c) else &[_][]const u8{},
            .has_bind_mounts = has_bind_mounts,
            .has_mount_options = has_mount_options,
        };
    }
    
    /// Перевіряє чи потрібно виконувати хук
    pub fn shouldExecute(
        self: *const Self,
        container_annotations: std.StringHashMap([]const u8),
        container_command: []const u8,
        has_bind_mounts: bool,
        has_mount_options: bool,
    ) bool {
        if (self.when) |when| {
            // Перевіряємо анотації
            var annotations_it = when.annotations.iterator();
            while (annotations_it.next()) |entry| {
                if (container_annotations.get(entry.key_ptr.*)) |value| {
                    if (!std.mem.eql(u8, value, entry.value_ptr.*)) {
                        return false;
                    }
                } else {
                    return false;
                }
            }
            
            // Перевіряємо команди
            var command_match = when.commands.len == 0;
            for (when.commands) |cmd| {
                if (std.mem.indexOf(u8, container_command, cmd) != null) {
                    command_match = true;
                    break;
                }
            }
            if (!command_match) return false;
            
            // Перевіряємо монтування
            if (when.has_bind_mounts and !has_bind_mounts) return false;
            if (when.has_mount_options and !has_mount_options) return false;
        }
        
        return true;
    }
    
    /// Конвертує в OCI хук
    pub fn toOciHook(self: *const Self) oci.Hook {
        return self.hook;
    }
}; 