const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const Error = @import("error").Error;
const json = std.json;

pub const RuntimeType = enum {
    crun,
    lxc,
    vm,
};

pub const NamespaceConfig = struct {
    name: []const u8,
    value: []const u8,
};

pub const RuntimeConfig = struct {
    type: RuntimeType,
    namespaces: []const NamespaceConfig,
    container_mask: []const u8, // Регулярний вираз для маски імен контейнерів
    priority: u8, // Пріоритет цього runtime (вищий пріоритет = вище значення)
};

pub const RoutingConfig = struct {
    runtimes: []const RuntimeConfig,
    default_runtime: RuntimeType,

    pub fn deinit(self: *RoutingConfig, allocator: Allocator) void {
        for (self.runtimes) |runtime| {
            for (runtime.namespaces) |ns| {
                allocator.free(ns.name);
                allocator.free(ns.value);
            }
            allocator.free(runtime.namespaces);
            allocator.free(runtime.container_mask);
        }
        allocator.free(self.runtimes);
    }
};

pub fn loadRoutingConfig(allocator: Allocator, config_path: []const u8) !RoutingConfig {
    const file = try std.fs.cwd().openFile(config_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);

    _ = try file.read(content);

    var parser = json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(content);
    defer tree.deinit();

    const root = tree.root.Object;

    var runtimes = std.ArrayList(RuntimeConfig).init(allocator);
    defer runtimes.deinit();

    const runtimes_array = root.get("runtimes").?.Array;
    for (runtimes_array.items) |runtime_obj| {
        const runtime = runtime_obj.Object;
        const runtime_type_str = runtime.get("type").?.String;
        const runtime_type = std.meta.stringToEnum(RuntimeType, runtime_type_str) orelse {
            return Error.InvalidConfig;
        };

        var namespaces = std.ArrayList(NamespaceConfig).init(allocator);
        defer namespaces.deinit();

        if (runtime.get("namespaces")) |ns_array| {
            for (ns_array.Array.items) |ns_obj| {
                const ns = ns_obj.Object;
                try namespaces.append(.{
                    .name = try allocator.dupe(u8, ns.get("name").?.String),
                    .value = try allocator.dupe(u8, ns.get("value").?.String),
                });
            }
        }

        try runtimes.append(.{
            .type = runtime_type,
            .namespaces = try namespaces.toOwnedSlice(),
            .container_mask = try allocator.dupe(u8, runtime.get("container_mask").?.String),
            .priority = @intCast(runtime.get("priority").?.Integer),
        });
    }

    const default_runtime_str = root.get("default_runtime").?.String;
    const default_runtime = std.meta.stringToEnum(RuntimeType, default_runtime_str) orelse {
        return Error.InvalidConfig;
    };

    return RoutingConfig{
        .runtimes = try runtimes.toOwnedSlice(),
        .default_runtime = default_runtime,
    };
}

pub fn selectRuntime(config: *const RoutingConfig, container_id: []const u8, namespaces: []const NamespaceConfig) RuntimeType {
    var best_match: ?RuntimeConfig = null;
    var best_priority: u8 = 0;

    for (config.runtimes) |runtime| {
        // Перевіряємо чи відповідає маска контейнера
        const regex = std.regex.compile(container_id, runtime.container_mask) catch continue;
        defer regex.deinit();

        if (!regex.match(container_id)) continue;

        // Перевіряємо чи відповідають namespaces
        var all_namespaces_match = true;
        for (runtime.namespaces) |required_ns| {
            var found = false;
            for (namespaces) |provided_ns| {
                if (std.mem.eql(u8, required_ns.name, provided_ns.name) and
                    std.mem.eql(u8, required_ns.value, provided_ns.value))
                {
                    found = true;
                    break;
                }
            }
            if (!found) {
                all_namespaces_match = false;
                break;
            }
        }

        if (all_namespaces_match and runtime.priority > best_priority) {
            best_match = runtime;
            best_priority = runtime.priority;
        }
    }

    return if (best_match) |match| match.type else config.default_runtime;
} 