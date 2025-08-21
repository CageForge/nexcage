const std = @import("std");
const zig_json = @import("zig_json");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
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
            .default_timeout = 10000, // 10 seconds by default
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

        var env_map = try process.getEnvMap(self.allocator);
        defer env_map.deinit();

        // Set environment variables
        if (hook.env) |env| {
            for (env) |env_var| {
                const index = std.mem.indexOf(u8, env_var, "=") orelse continue;
                const key = env_var[0..index];
                const value = env_var[index + 1 ..];
                try env_map.put(key, value);
            }
        }

        // Add context
        try env_map.put("OCI_CONTAINER_ID", context.container_id);
        try env_map.put("OCI_BUNDLE", context.bundle);
        try env_map.put("OCI_CONTAINER_STATE", context.state);

        // Set timeout
        const timeout = hook.timeout orelse self.default_timeout;

        var child = process.Child.init(args.items, self.allocator);

        child.env_map = &env_map;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const start_time = std.time.milliTimestamp();
        const stdout = try child.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stdout);

        const stderr = try child.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(stderr);

        const term = try child.wait();
        const end_time = std.time.milliTimestamp();
        const duration = @as(i64, @intCast(end_time - start_time));

        if (duration > timeout) {
            logger.err("Hook {s} exceeded timeout of {d}ms (took {d}ms)", .{ hook.path, timeout, duration });
            return error.TimeoutExceeded;
        }

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

pub fn parseHooks(allocator: std.mem.Allocator, content: []const u8) !types.Hooks {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    const hooks = types.Hooks{
        .prestart = try parseHookArray(obj, "prestart", allocator),
        .poststart = try parseHookArray(obj, "poststart", allocator),
        .poststop = try parseHookArray(obj, "poststop", allocator),
    };

    return hooks;
}

fn parseHookArray(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?[]types.Hook {
    const value = obj.get(field) orelse return null;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    const hooks = try allocator.alloc(types.Hook, array.len());
    for (hooks, 0..) |*hook, i| {
        const hook_value = array.get(i);
        if (hook_value.type != .object) return error.InvalidType;
        const hook_obj = hook_value.object();

        hook.* = types.Hook{
            .path = try getString(hook_obj, "path"),
            .args = try parseStringArray(hook_obj, "args", allocator),
            .env = try parseStringArray(hook_obj, "env", allocator),
            .timeout = try getOptionalInt(hook_obj, "timeout"),
        };
    }

    return hooks;
}

fn getString(obj: *zig_json.Object, field: []const u8) ![]const u8 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}

fn getOptionalInt(obj: *zig_json.Object, field: []const u8) !?i64 {
    const value = obj.get(field) orelse return null;
    if (value.type != .integer) return error.InvalidType;
    return value.integer();
}

fn parseStringArray(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?[][]const u8 {
    const value = obj.get(field) orelse return null;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    const result = try allocator.alloc([]const u8, array.len());
    for (result, 0..) |*entry, i| {
        const entry_value = array.get(i);
        if (entry_value.type != .string) return error.InvalidType;
        entry.* = try allocator.dupe(u8, entry_value.string());
    }

    return result;
}

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

    try testing.expectError(HookError.TimeoutExceeded, executor.executeHook(hook, context));
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

    try testing.expectError(HookError.InvalidPath, executor.executeHook(hook, context));
}
