const std = @import("std");
const zig_json = @import("zig_json");
const types = @import("types.zig");

pub const ConfigError = error{
    InvalidConfig,
    InvalidRootFS,
    InvalidHistory,
};

pub fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !types.ImageConfig {
    var parsed = try zig_json.parse(allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value.type != .object) return error.InvalidJson;
    const obj = parsed.value.object();

    return types.ImageConfig{
        .created = try getOptionalString(obj, "created"),
        .author = try getOptionalString(obj, "author"),
        .architecture = try getString(obj, "architecture"),
        .os = try getString(obj, "os"),
        .os_version = try getOptionalString(obj, "os.version"),
        .config = try parseConfigObject(obj, "config", allocator),
        .rootfs = try parseRootfs(obj, "rootfs", allocator),
        .history = try parseHistory(obj, "history", allocator),
    };
}

fn getString(obj: *zig_json.Object, field: []const u8) ![]const u8 {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}

fn getOptionalString(obj: *zig_json.Object, field: []const u8) !?[]const u8 {
    const value = obj.get(field) orelse return null;
    if (value.type != .string) return error.InvalidType;
    return value.string();
}

fn parseConfigObject(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !types.Config {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .object) return error.InvalidType;
    const config_obj = value.object();

    return types.Config{
        .user = try getOptionalString(config_obj, "User"),
        .exposed_ports = try parseExposedPorts(config_obj, "ExposedPorts", allocator),
        .env = try parseStringArray(config_obj, "Env", allocator),
        .entrypoint = try parseStringArray(config_obj, "Entrypoint", allocator),
        .cmd = try parseStringArray(config_obj, "Cmd", allocator),
        .volumes = try parseVolumes(config_obj, "Volumes", allocator),
        .working_dir = try getOptionalString(config_obj, "WorkingDir"),
        .labels = try parseLabels(config_obj, "Labels", allocator),
        .stop_signal = try getOptionalString(config_obj, "StopSignal"),
    };
}

fn parseExposedPorts(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?std.StringHashMap(zig_json.JsonValue) {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const ports_obj = value.object();

    var ports = std.StringHashMap(zig_json.JsonValue).init(allocator);
    var it = ports_obj.iterator();
    while (it.next()) |entry| {
        try ports.put(entry.key, entry.value);
    }

    return ports;
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

fn parseVolumes(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?std.StringHashMap(zig_json.JsonValue) {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const volumes_obj = value.object();

    var volumes = std.StringHashMap(zig_json.JsonValue).init(allocator);
    var it = volumes_obj.iterator();
    while (it.next()) |entry| {
        try volumes.put(entry.key, entry.value);
    }

    return volumes;
}

fn parseLabels(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?std.StringHashMap([]const u8) {
    const value = obj.get(field) orelse return null;
    if (value.type != .object) return error.InvalidType;
    const labels_obj = value.object();

    var labels = std.StringHashMap([]const u8).init(allocator);
    var it = labels_obj.iterator();
    while (it.next()) |entry| {
        if (entry.value.type != .string) return error.InvalidType;
        try labels.put(entry.key, try allocator.dupe(u8, entry.value.string()));
    }

    return labels;
}

fn parseRootfs(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !types.Rootfs {
    const value = obj.get(field) orelse return error.MissingField;
    if (value.type != .object) return error.InvalidType;
    const rootfs_obj = value.object();

    return types.Rootfs{
        .type = try getString(rootfs_obj, "type"),
        .diff_ids = try parseStringArray(rootfs_obj, "diff_ids", allocator) orelse return error.MissingField,
    };
}

fn parseHistory(obj: *zig_json.Object, field: []const u8, allocator: std.mem.Allocator) !?[]types.History {
    const value = obj.get(field) orelse return null;
    if (value.type != .array) return error.InvalidType;
    const array = value.array();

    const history = try allocator.alloc(types.History, array.len());
    for (history, 0..) |*entry, i| {
        const entry_value = array.get(i);
        if (entry_value.type != .object) return error.InvalidType;
        const history_obj = entry_value.object();

        entry.* = types.History{
            .created = try getOptionalString(history_obj, "created"),
            .author = try getOptionalString(history_obj, "author"),
            .created_by = try getOptionalString(history_obj, "created_by"),
            .comment = try getOptionalString(history_obj, "comment"),
            .empty_layer = try getOptionalBool(history_obj, "empty_layer"),
        };
    }

    return history;
}

fn getOptionalBool(obj: *zig_json.Object, field: []const u8) !?bool {
    const value = obj.get(field) orelse return null;
    if (value.type != .boolean) return error.InvalidType;
    return value.boolean();
}

pub fn createConfig(
    _: std.mem.Allocator,
    architecture: []const u8,
    os: []const u8,
    config: ?types.Config,
    rootfs: types.RootFS,
    history: ?[]types.History,
) !types.ImageConfig {
    if (architecture.len == 0 or os.len == 0) {
        return ConfigError.InvalidConfig;
    }

    if (rootfs.type.len == 0 or rootfs.diff_ids.len == 0) {
        return ConfigError.InvalidRootFS;
    }

    return types.ImageConfig{
        .architecture = architecture,
        .os = os,
        .config = config,
        .rootfs = rootfs,
        .history = history,
    };
}

pub fn serializeConfig(allocator: std.mem.Allocator, config: types.ImageConfig) ![]const u8 {
    return try zig_json.stringifyAlloc(allocator, config, .{});
}
