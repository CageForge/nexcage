const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const json = std.json;
const fs = std.fs;
const types = @import("types.zig");
const logger = std.log.scoped(.oci_hooks);
const os = std.os;
const time = std.time;
const process = std.process;
const mem = std.mem;
const errors = @import("error");
const sys = std.os.system;

pub const HookError = error{
    ExecutionFailed,
    TimeoutExceeded,
    InvalidPath,
    PermissionDenied,
    ProcessSpawnFailed,
    InvalidExitCode,
    SignalInterrupt,
};

pub const HookContext = struct {
    container_id: []const u8,
    bundle: []const u8,
    state: []const u8,
};

pub const HookResult = struct {
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    duration_ms: u64,
};

pub const HookExecutor = struct {
    allocator: Allocator,
    default_timeout: i64,

    const Self = @This();

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .default_timeout = 10000, // 10 секунд за замовчуванням
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn executeHooks(self: *Self, hooks: []const types.Hook, context: HookContext) !void {
        for (hooks) |hook| {
            try self.executeHook(hook, context);
        }
    }

    pub fn executeHook(self: *Self, hook: types.Hook, context: HookContext) !void {
        var args = ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append(hook.path);
        if (hook.args) |hook_args| {
            for (hook_args) |arg| {
                try args.append(arg);
            }
        }

        var child = std.ChildProcess.init(args.items, self.allocator);
        defer child.deinit();

        // Встановлюємо environment змінні
        if (hook.env) |env| {
            child.env_map = try std.process.getEnvMap(self.allocator);
            for (env) |env_var| {
                const index = std.mem.indexOf(u8, env_var, "=") orelse continue;
                const key = env_var[0..index];
                const value = env_var[index + 1 ..];
                try child.env_map.?.put(key, value);
            }
        }

        // Встановлюємо timeout
        if (hook.timeout) |timeout| {
            child.term_timeout = timeout;
        } else {
            child.term_timeout = self.default_timeout;
        }

        // Додаємо контекст
        try child.env_map.?.put("OCI_CONTAINER_ID", context.container_id);
        try child.env_map.?.put("OCI_BUNDLE", context.bundle);
        try child.env_map.?.put("OCI_CONTAINER_STATE", context.state);

        const term = try child.spawnAndWait();
        switch (term) {
            .Exited => |code| {
                if (code != 0) {
                    logger.err("Hook {s} failed with exit code {d}", .{ hook.path, code });
                    return error.HookFailed;
                }
            },
            else => {
                logger.err("Hook {s} failed with term {}", .{ hook.path, term });
                return error.HookFailed;
            },
        }
    }
};

test "HookExecutor - basic execution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try HookExecutor.init(allocator);
    defer executor.deinit();

    const hook = types.Hook{
        .path = "/bin/echo",
        .args = &[_][]const u8{"Hello"},
        .env = null,
        .timeout = null,
    };

    const context = HookContext{
        .container_id = "test-container",
        .bundle = "/test/bundle",
        .state = "creating",
    };

    try executor.executeHook(hook, context);
}

test "HookExecutor - timeout" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try HookExecutor.init(allocator);
    defer executor.deinit();

    const hook = types.Hook{
        .path = "/bin/sleep",
        .args = &[_][]const u8{"1"},
        .env = null,
        .timeout = 100, // 100ms timeout
    };

    const context = HookContext{
        .container_id = "test-container",
        .bundle = "/test/bundle",
        .state = "creating",
    };

    try testing.expectError(
        HookError.TimeoutExceeded,
        executor.executeHook(hook, context)
    );
}

test "HookExecutor - invalid path" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var executor = try HookExecutor.init(allocator);
    defer executor.deinit();

    const hook = types.Hook{
        .path = "/nonexistent/path",
        .args = null,
        .env = null,
        .timeout = null,
    };

    const context = HookContext{
        .container_id = "test-container",
        .bundle = "/test/bundle",
        .state = "creating",
    };

    try testing.expectError(
        HookError.InvalidPath,
        executor.executeHook(hook, context)
    );
} 