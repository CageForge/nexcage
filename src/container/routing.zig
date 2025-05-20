const std = @import("std");
const Allocator = std.mem.Allocator;
const log = @import("logger").log;
const Error = @import("error").Error;
const ContainerType = @import("container").ContainerType;

const RoutingRule = struct {
    pattern: []const u8,
    runtime: []const u8,
};

const RoutingConfig = struct {
    routing: []RoutingRule,
};

pub fn getRuntimeForContainer(allocator: Allocator, container_id: []const u8) !ContainerType {
    const config_path = "config/routing.json";
    const file = try std.fs.cwd().openFile(config_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const content = try allocator.alloc(u8, file_size);
    defer allocator.free(content);

    const bytes_read = try file.read(content);
    if (bytes_read != file_size) {
        return Error.FileReadError;
    }

    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    var tree = try parser.parse(content);
    defer tree.deinit();

    const config = try std.json.parseFromValue(RoutingConfig, allocator, tree.root, .{});
    defer config.deinit();

    // Перевіряємо кожне правило роутингу
    for (config.value.routing) |rule| {
        var regex = try std.regex.compile(allocator, rule.pattern);
        defer regex.deinit();

        if (regex.match(container_id)) {
            if (std.mem.eql(u8, rule.runtime, "crun")) {
                return .crun;
            } else if (std.mem.eql(u8, rule.runtime, "lxc")) {
                return .lxc;
            } else if (std.mem.eql(u8, rule.runtime, "vm")) {
                return .vm;
            }
        }
    }

    // Якщо не знайдено відповідного правила, використовуємо LXC як за замовчуванням
    return .lxc;
} 