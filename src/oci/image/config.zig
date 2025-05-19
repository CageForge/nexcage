const std = @import("std");
const types = @import("types.zig");
const json = std.json;

pub const ConfigError = error{
    InvalidConfig,
    InvalidRootFS,
    InvalidHistory,
};

pub fn parseConfig(allocator: std.mem.Allocator, data: []const u8) !types.ImageConfig {
    var parsed = try json.parseFromSlice(types.ImageConfig, allocator, data, .{});
    defer parsed.deinit();

    // Validate required fields
    if (parsed.value.architecture.len == 0 or parsed.value.os.len == 0) {
        return ConfigError.InvalidConfig;
    }

    // Validate rootfs
    if (parsed.value.rootfs.type.len == 0 or parsed.value.rootfs.diff_ids.len == 0) {
        return ConfigError.InvalidRootFS;
    }

    return parsed.value;
}

pub fn createConfig(
    allocator: std.mem.Allocator,
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
    return try json.stringifyAlloc(allocator, config, .{});
}
