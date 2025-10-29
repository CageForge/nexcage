/// Hook System - Event-driven coordination for NexCage plugins
/// 
/// This module provides a comprehensive hook system that allows plugins to
/// register callbacks for system events, enabling reactive and coordinated
/// behavior across the plugin ecosystem.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const plugin = @import("plugin.zig");

/// Hook execution priority levels
pub const HookPriority = enum(u8) {
    critical = 0,
    high = 1,
    normal = 2,
    low = 3,
    background = 4,

    pub fn toString(self: HookPriority) []const u8 {
        return @tagName(self);
    }
};

/// Hook execution context passed to hook callbacks
pub const HookContext = struct {
    const Self = @This();

    allocator: Allocator,
    hook_name: []const u8,
    plugin_name: []const u8,
    data: ?*anyopaque = null,
    metadata: std.StringHashMap([]const u8),
    execution_time: i64,
    
    pub fn init(allocator: Allocator, hook_name: []const u8, plugin_name: []const u8) Self {
        return Self{
            .allocator = allocator,
            .hook_name = hook_name,
            .plugin_name = plugin_name,
            .metadata = std.StringHashMap([]const u8).init(allocator),
            .execution_time = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Self) void {
        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }

    /// Set metadata key-value pair
    pub fn setMetadata(self: *Self, key: []const u8, value: []const u8) !void {
        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.metadata.put(owned_key, owned_value);
    }

    /// Get metadata value by key
    pub fn getMetadata(self: *Self, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }

    /// Set typed data pointer
    pub fn setData(self: *Self, data: anytype) void {
        self.data = @ptrCast(data);
    }

    /// Get typed data pointer
    pub fn getData(self: *Self, comptime T: type) ?*T {
        if (self.data) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }
};

/// Hook callback function signature
pub const HookCallback = *const fn(*HookContext) anyerror!void;

/// Hook registration information
pub const HookRegistration = struct {
    plugin_name: []const u8,
    callback: HookCallback,
    priority: HookPriority,
    enabled: bool = true,
    timeout_ms: u32 = 5000,
    
    pub fn deinit(self: *HookRegistration, allocator: Allocator) void {
        allocator.free(self.plugin_name);
    }
};

/// Hook execution result
pub const HookExecutionResult = union(enum) {
    success: void,
    failure: anyerror,
    timeout: void,
    disabled: void,
};

/// Hook execution statistics
pub const HookStats = struct {
    executions: u64 = 0,
    failures: u64 = 0,
    timeouts: u64 = 0,
    total_duration_ms: u64 = 0,
    last_execution: i64 = 0,
    avg_duration_ms: f64 = 0.0,
    min_duration_ms: u64 = std.math.maxInt(u64),
    max_duration_ms: u64 = 0,

    pub fn updateStats(self: *HookStats, duration_ms: u64, success: bool, timeout: bool) void {
        self.executions += 1;
        if (!success) self.failures += 1;
        if (timeout) self.timeouts += 1;
        
        self.total_duration_ms += duration_ms;
        self.last_execution = std.time.timestamp();
        self.avg_duration_ms = @as(f64, @floatFromInt(self.total_duration_ms)) / @as(f64, @floatFromInt(self.executions));
        
        if (duration_ms < self.min_duration_ms) self.min_duration_ms = duration_ms;
        if (duration_ms > self.max_duration_ms) self.max_duration_ms = duration_ms;
    }
};

/// Predefined system hooks
pub const SystemHooks = struct {
    pub const STARTUP = "system.startup";
    pub const SHUTDOWN = "system.shutdown";
    pub const CONFIG_RELOAD = "system.config_reload";
    pub const HEALTH_CHECK = "system.health_check";
    pub const PLUGIN_LOADED = "system.plugin_loaded";
    pub const PLUGIN_UNLOADED = "system.plugin_unloaded";
    pub const ERROR_OCCURRED = "system.error_occurred";
};

/// Container lifecycle hooks
pub const ContainerHooks = struct {
    pub const PRE_CREATE = "container.pre_create";
    pub const POST_CREATE = "container.post_create";
    pub const PRE_START = "container.pre_start";
    pub const POST_START = "container.post_start";
    pub const PRE_STOP = "container.pre_stop";
    pub const POST_STOP = "container.post_stop";
    pub const PRE_DELETE = "container.pre_delete";
    pub const POST_DELETE = "container.post_delete";
    pub const STATUS_CHANGED = "container.status_changed";
};

/// CLI hooks
pub const CLIHooks = struct {
    pub const PRE_COMMAND = "cli.pre_command";
    pub const POST_COMMAND = "cli.post_command";
    pub const COMMAND_ERROR = "cli.command_error";
    pub const HELP_REQUESTED = "cli.help_requested";
};

/// API hooks
pub const APIHooks = struct {
    pub const PRE_REQUEST = "api.pre_request";
    pub const POST_REQUEST = "api.post_request";
    pub const REQUEST_ERROR = "api.request_error";
    pub const AUTHENTICATION = "api.authentication";
    pub const AUTHORIZATION = "api.authorization";
};

/// Hook system configuration
pub const HookSystemConfig = struct {
    max_execution_time_ms: u32 = 5000,
    enable_async_execution: bool = true,
    max_concurrent_hooks: u32 = 10,
    enable_hook_metrics: bool = true,
    enable_hook_tracing: bool = false,
    hook_timeout_strategy: TimeoutStrategy = .skip,

    pub const TimeoutStrategy = enum {
        skip,    // Skip timed out hooks
        retry,   // Retry timed out hooks once
        abort,   // Abort hook execution chain on timeout
    };
};

/// Hook information for listing and monitoring
pub const HookInfo = struct {
    hook_name: []const u8,
    plugin_name: []const u8,
    priority: HookPriority,
    enabled: bool,
    timeout_ms: u32,
    stats: HookStats,

    pub fn deinit(self: *HookInfo, allocator: Allocator) void {
        allocator.free(self.hook_name);
        allocator.free(self.plugin_name);
    }
};

/// Queued hook execution for async processing
const QueuedExecution = struct {
    hook_name: []const u8,
    context: *HookContext,
    timestamp: i64,
};

/// Main hook system implementation
pub const HookSystem = struct {
    const Self = @This();

    allocator: Allocator,
    config: HookSystemConfig,
    
    // Hook storage and management
    hooks: std.StringHashMap(std.ArrayList(HookRegistration)),
    hook_stats: std.StringHashMap(std.StringHashMap(HookStats)), // hook_name -> plugin_name -> stats
    
    // Execution state
    currently_executing: std.StringHashMap(bool), // plugin_name -> executing
    execution_queue: std.ArrayList(QueuedExecution),
    
    // Metrics and monitoring
    total_hooks_executed: u64 = 0,
    total_hook_failures: u64 = 0,

    pub fn init(allocator: Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .config = HookSystemConfig{},
            .hooks = std.StringHashMap(std.ArrayList(HookRegistration)).init(allocator),
            .hook_stats = std.StringHashMap(std.StringHashMap(HookStats)).init(allocator),
            .currently_executing = std.StringHashMap(bool).init(allocator),
            .execution_queue = std.ArrayList(QueuedExecution).empty,
        };

        std.log.info("Hook system initialized", .{});
        return self;
    }

    pub fn deinit(self: *Self) void {
        // Clean up all hook registrations
        var hook_iterator = self.hooks.iterator();
        while (hook_iterator.next()) |entry| {
            const hook_list = entry.value_ptr;
            for (hook_list.items) |*registration| {
                registration.deinit(self.allocator);
            }
            hook_list.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.hooks.deinit();

        // Clean up statistics
        var stats_iterator = self.hook_stats.iterator();
        while (stats_iterator.next()) |entry| {
            var plugin_stats = entry.value_ptr;
            var plugin_iterator = plugin_stats.iterator();
            while (plugin_iterator.next()) |plugin_entry| {
                self.allocator.free(plugin_entry.key_ptr.*);
            }
            plugin_stats.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.hook_stats.deinit();

        self.currently_executing.deinit();
        self.execution_queue.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Register a hook callback for a specific event
    pub fn registerHook(
        self: *Self,
        plugin_name: []const u8,
        hook_name: []const u8,
        callback: HookCallback,
        priority: HookPriority,
        timeout_ms: u32,
    ) !void {
        const registration = HookRegistration{
            .plugin_name = try self.allocator.dupe(u8, plugin_name),
            .callback = callback,
            .priority = priority,
            .timeout_ms = timeout_ms,
        };

        // Get or create hook list
        const hook_list = self.hooks.getPtr(hook_name) orelse blk: {
            const hook_key = try self.allocator.dupe(u8, hook_name);
            const new_list: std.ArrayList(HookRegistration) = .empty;
            try self.hooks.put(hook_key, new_list);
            break :blk self.hooks.getPtr(hook_key).?;
        };

        try hook_list.append(self.allocator, registration);

        // Sort by priority (critical hooks execute first)
        std.sort.pdq(HookRegistration, hook_list.items, {}, compareHookPriority);

        // Initialize statistics
        try self.initializeHookStats(hook_name, plugin_name);

        std.log.debug("Hook registered: {s} -> {s} (priority: {s})", .{ plugin_name, hook_name, priority.toString() });
    }

    /// Unregister all hooks for a specific plugin
    pub fn unregisterPlugin(self: *Self, plugin_name: []const u8) void {
        var hook_iterator = self.hooks.iterator();
        while (hook_iterator.next()) |entry| {
            const hook_list = entry.value_ptr;
            var i: usize = 0;
            while (i < hook_list.items.len) {
                if (std.mem.eql(u8, hook_list.items[i].plugin_name, plugin_name)) {
                    hook_list.items[i].deinit(self.allocator);
                    _ = hook_list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        std.log.debug("All hooks unregistered for plugin: {s}", .{plugin_name});
    }

    /// Execute all registered hooks for a specific event
    pub fn executeHooks(self: *Self, hook_name: []const u8, context: *HookContext) !void {
        const hook_list = self.hooks.get(hook_name) orelse {
            std.log.debug("No hooks registered for event: {s}", .{hook_name});
            return;
        };

        if (hook_list.items.len == 0) return;

        const start_time = std.time.milliTimestamp();
        var successful_executions: u32 = 0;
        var failed_executions: u32 = 0;
        var timed_out_executions: u32 = 0;

        std.log.debug("Executing {} hooks for event: {s}", .{ hook_list.items.len, hook_name });

        for (hook_list.items) |registration| {
            if (!registration.enabled) {
                std.log.debug("Skipping disabled hook: {s} -> {s}", .{ registration.plugin_name, hook_name });
                continue;
            }

            // Check if plugin is already executing (prevent recursion)
            if (self.currently_executing.get(registration.plugin_name) orelse false) {
                std.log.warn("Plugin {s} already executing, skipping hook for {s}", .{ registration.plugin_name, hook_name });
                continue;
            }

            const hook_start = std.time.milliTimestamp();
            
            // Mark plugin as executing
            const plugin_key = try self.allocator.dupe(u8, registration.plugin_name);
            try self.currently_executing.put(plugin_key, true);
            defer {
                _ = self.currently_executing.remove(registration.plugin_name);
                self.allocator.free(plugin_key);
            }

            // Execute hook with timeout
            const result = self.executeHookWithTimeout(registration, context);

            const hook_duration = @as(u64, @intCast(std.time.milliTimestamp() - hook_start));

            // Update statistics
            if (self.config.enable_hook_metrics) {
                self.updateHookStats(hook_name, registration.plugin_name, hook_duration, result);
            }

            // Handle result
            switch (result) {
                .success => {
                    successful_executions += 1;
                    std.log.debug("Hook executed successfully: {s} -> {s} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        hook_duration,
                    });
                },
                .failure => |err| {
                    failed_executions += 1;
                    std.log.err("Hook execution failed: {s} -> {s}: {} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        err,
                        hook_duration,
                    });
                },
                .timeout => {
                    timed_out_executions += 1;
                    std.log.err("Hook execution timed out: {s} -> {s} ({}ms)", .{
                        registration.plugin_name,
                        hook_name,
                        hook_duration,
                    });

                    // Handle timeout strategy
                    switch (self.config.hook_timeout_strategy) {
                        .skip => continue,
                        .retry => {
                            // TODO: Implement retry logic
                            std.log.debug("Hook retry not implemented", .{});
                        },
                        .abort => {
                            std.log.err("Aborting hook execution chain due to timeout", .{});
                            break;
                        },
                    }
                },
                .disabled => {
                    std.log.debug("Hook disabled during execution: {s} -> {s}", .{ registration.plugin_name, hook_name });
                },
            }
        }

        const total_duration = std.time.milliTimestamp() - start_time;
        self.total_hooks_executed += successful_executions;
        self.total_hook_failures += failed_executions;

        std.log.debug("Hook execution completed: {s} - {}/{}/{} (success/failed/timeout) ({}ms total)", .{
            hook_name,
            successful_executions,
            failed_executions,
            timed_out_executions,
            total_duration,
        });
    }

    /// Execute hooks asynchronously (if supported)
    pub fn executeHooksAsync(self: *Self, hook_name: []const u8, context: *HookContext) !void {
        if (!self.config.enable_async_execution) {
            return self.executeHooks(hook_name, context);
        }

        // Queue for async execution
        try self.execution_queue.append(self.allocator, QueuedExecution{
            .hook_name = try self.allocator.dupe(u8, hook_name),
            .context = context,
            .timestamp = std.time.timestamp(),
        });

        // TODO: Implement actual async execution using thread pool
        // For now, execute synchronously
        return self.executeHooks(hook_name, context);
    }

    /// Get statistics for a specific hook
    pub fn getHookStats(self: *Self, hook_name: []const u8, plugin_name: []const u8) ?HookStats {
        const hook_stats = self.hook_stats.get(hook_name) orelse return null;
        return hook_stats.get(plugin_name);
    }

    /// Get all statistics for a hook
    pub fn getAllHookStats(self: *Self, hook_name: []const u8) ?std.StringHashMap(HookStats) {
        return self.hook_stats.get(hook_name);
    }

    /// List all registered hooks
    pub fn listHooks(self: *Self, allocator: Allocator) ![]HookInfo {
        var hook_list: std.ArrayList(HookInfo) = .empty;
        defer hook_list.deinit(allocator);

        var hook_iterator = self.hooks.iterator();
        while (hook_iterator.next()) |entry| {
            const hook_name = entry.key_ptr.*;
            const registrations = entry.value_ptr.*;

            for (registrations.items) |reg| {
                const stats = self.getHookStats(hook_name, reg.plugin_name) orelse HookStats{};
                
                try hook_list.append(allocator, HookInfo{
                    .hook_name = try allocator.dupe(u8, hook_name),
                    .plugin_name = try allocator.dupe(u8, reg.plugin_name),
                    .priority = reg.priority,
                    .enabled = reg.enabled,
                    .timeout_ms = reg.timeout_ms,
                    .stats = stats,
                });
            }
        }

        return hook_list.toOwnedSlice(allocator);
    }

    /// Enable or disable a specific hook
    pub fn setHookEnabled(self: *Self, hook_name: []const u8, plugin_name: []const u8, enabled: bool) !void {
        const hook_list = self.hooks.getPtr(hook_name) orelse return error.HookNotFound;

        for (hook_list.items) |*registration| {
            if (std.mem.eql(u8, registration.plugin_name, plugin_name)) {
                registration.enabled = enabled;
                std.log.info("Hook {s}:{s} {s}", .{ 
                    plugin_name, 
                    hook_name, 
                    if (enabled) "enabled" else "disabled" 
                });
                return;
            }
        }

        return error.PluginNotFound;
    }

    /// Get global hook system statistics
    pub fn getGlobalStats(self: *Self) struct { 
        total_executed: u64, 
        total_failed: u64, 
        total_registered: u32,
        active_executions: u32,
    } {
        var total_registered: u32 = 0;
        var hook_iterator = self.hooks.iterator();
        while (hook_iterator.next()) |entry| {
            total_registered += @intCast(entry.value_ptr.items.len);
        }

        return .{
            .total_executed = self.total_hooks_executed,
            .total_failed = self.total_hook_failures,
            .total_registered = total_registered,
            .active_executions = @intCast(self.currently_executing.count()),
        };
    }

    // Private implementation methods

    fn executeHookWithTimeout(
        self: *Self,
        registration: HookRegistration,
        context: *HookContext,
    ) HookExecutionResult {
        // TODO: Implement proper timeout mechanism with thread cancellation
        // For now, execute directly without timeout
        _ = self;

        if (!registration.enabled) {
            return HookExecutionResult.disabled;
        }

        registration.callback(context) catch |err| {
            return HookExecutionResult{ .failure = err };
        };

        return HookExecutionResult.success;
    }

    fn initializeHookStats(self: *Self, hook_name: []const u8, plugin_name: []const u8) !void {
        if (!self.config.enable_hook_metrics) return;

        // Get or create hook stats map
        const hook_stats_map = self.hook_stats.getPtr(hook_name) orelse blk: {
            const hook_key = try self.allocator.dupe(u8, hook_name);
            const new_map = std.StringHashMap(HookStats).init(self.allocator);
            try self.hook_stats.put(hook_key, new_map);
            break :blk self.hook_stats.getPtr(hook_key).?;
        };

        // Initialize stats for this plugin
        if (!hook_stats_map.contains(plugin_name)) {
            const plugin_key = try self.allocator.dupe(u8, plugin_name);
            try hook_stats_map.put(plugin_key, HookStats{});
        }
    }

    fn updateHookStats(
        self: *Self, 
        hook_name: []const u8, 
        plugin_name: []const u8, 
        duration_ms: u64, 
        result: HookExecutionResult
    ) void {
        const hook_stats_map = self.hook_stats.getPtr(hook_name) orelse return;
        const stats = hook_stats_map.getPtr(plugin_name) orelse return;

        const success = switch (result) {
            .success => true,
            else => false,
        };

        const timeout = switch (result) {
            .timeout => true,
            else => false,
        };

        stats.updateStats(duration_ms, success, timeout);
    }

    fn compareHookPriority(context: void, a: HookRegistration, b: HookRegistration) bool {
        _ = context;
        return @intFromEnum(a.priority) < @intFromEnum(b.priority);
    }
};

/// Test suite
const testing = std.testing;

test "HookContext metadata operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = HookContext.init(allocator, "test.hook", "test-plugin");
    defer context.deinit();

    try context.setMetadata("key1", "value1");
    try context.setMetadata("key2", "value2");

    try testing.expect(std.mem.eql(u8, context.getMetadata("key1").?, "value1"));
    try testing.expect(std.mem.eql(u8, context.getMetadata("key2").?, "value2"));
    try testing.expect(context.getMetadata("nonexistent") == null);
}

test "HookSystem basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const hook_system = try HookSystem.init(allocator);
    defer hook_system.deinit();

    // Test hook registration
    const TestCallback = struct {
        fn callback(context: *HookContext) !void {
            try context.setMetadata("executed", "true");
        }
    };

    try hook_system.registerHook(
        "test-plugin",
        "test.event",
        TestCallback.callback,
        .normal,
        5000
    );

    // Test hook execution
    var context = HookContext.init(allocator, "test.event", "test-plugin");
    defer context.deinit();

    try hook_system.executeHooks("test.event", &context);

    // Verify hook was executed
    try testing.expect(std.mem.eql(u8, context.getMetadata("executed").?, "true"));

    // Test plugin unregistration
    hook_system.unregisterPlugin("test-plugin");
    
    // Test that hooks are cleaned up
    const hooks_after_unregister = try hook_system.listHooks(allocator);
    defer allocator.free(hooks_after_unregister);
    try testing.expect(hooks_after_unregister.len == 0);
}

test "Hook priority ordering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const hook_system = try HookSystem.init(allocator);
    defer hook_system.deinit();

    var execution_order = std.ArrayList([]const u8).empty;
    defer execution_order.deinit(allocator);

    const TestCallbacks = struct {
        var order: *std.ArrayList([]const u8) = undefined;
        var test_allocator: std.mem.Allocator = undefined;
        
        fn criticalCallback(context: *HookContext) !void {
            _ = context;
            try order.append(test_allocator, "critical");
        }
        
        fn normalCallback(context: *HookContext) !void {
            _ = context;
            try order.append(test_allocator, "normal");
        }
        
        fn lowCallback(context: *HookContext) !void {
            _ = context;
            try order.append(test_allocator, "low");
        }
    };
    
    TestCallbacks.order = &execution_order;
    TestCallbacks.test_allocator = allocator;

    // Register hooks in reverse priority order
    try hook_system.registerHook("plugin1", "test.priority", TestCallbacks.lowCallback, .low, 5000);
    try hook_system.registerHook("plugin2", "test.priority", TestCallbacks.normalCallback, .normal, 5000);
    try hook_system.registerHook("plugin3", "test.priority", TestCallbacks.criticalCallback, .critical, 5000);

    var context = HookContext.init(allocator, "test.priority", "test");
    defer context.deinit();

    try hook_system.executeHooks("test.priority", &context);

    // Verify execution order (critical -> normal -> low)
    try testing.expect(execution_order.items.len == 3);
    try testing.expect(std.mem.eql(u8, execution_order.items[0], "critical"));
    try testing.expect(std.mem.eql(u8, execution_order.items[1], "normal"));
    try testing.expect(std.mem.eql(u8, execution_order.items[2], "low"));
}