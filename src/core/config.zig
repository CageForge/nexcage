const std = @import("std");
const types = @import("types.zig");
const logging = @import("logging.zig");

/// Configuration loader and manager
pub const ConfigLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Load configuration from default locations
    pub fn loadDefault(self: *Self) !Config {
        const default_paths = [_][]const u8{
            "./config.json",
            "/etc/nexcage/config.json",
        };

        for (default_paths) |path| {
            if (self.loadFromFile(path)) |config| {
                return config;
            } else |err| switch (err) {
                types.Error.FileNotFound => continue,
                else => return err,
            }
        }

        return try Config.init(self.allocator, .lxc);
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Self, path: []const u8) !Config {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return types.Error.FileNotFound,
            else => return err,
        };
        defer self.allocator.free(file_content);

        return self.loadFromString(file_content);
    }

    /// Load configuration from string
    pub fn loadFromString(self: *Self, json_string: []const u8) !Config {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_string, .{});
        defer parsed.deinit();

        return self.parseConfig(parsed.value);
    }

    pub fn parseConfig(self: *Self, value: std.json.Value) !Config {
        var config = try Config.init(self.allocator, .lxc);

        if (value.object.get("log_level")) |level_value| {
            if (level_value == .string) {
                config.log_level = self.parseLogLevel(level_value.string);
            }
        }

        if (value.object.get("log_file")) |file_value| {
            if (file_value == .string) {
                if (config.log_file) |old| self.allocator.free(old);
                config.log_file = try self.allocator.dupe(u8, file_value.string);
            }
        }

        if (value.object.get("data_dir")) |dir_value| {
            if (dir_value == .string) {
                self.allocator.free(config.data_dir);
                config.data_dir = try self.allocator.dupe(u8, dir_value.string);
            }
        }

        return config;
    }

    fn parseLogLevel(self: *Self, level_str: []const u8) logging.LogLevel {
        _ = self;
        if (std.mem.eql(u8, level_str, "debug")) return .debug;
        if (std.mem.eql(u8, level_str, "warn")) return .warn;
        if (std.mem.eql(u8, level_str, "error")) return logging.LogLevel.@"error";
        return .info;
    }
};

/// Global configuration structure
pub const Config = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    runtime_type: types.RuntimeType,
    log_level: logging.LogLevel,
    log_file: ?[]const u8,
    data_dir: []const u8,
    network: types.NetworkConfig,
    container_config: types.ContainerConfig,

    pub fn init(allocator: std.mem.Allocator, runtime_type: types.RuntimeType) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = runtime_type,
            .log_level = .info,
            .log_file = null,
            .data_dir = try allocator.dupe(u8, "/var/lib/nexcage"),
            .network = types.NetworkConfig{
                .bridge = try allocator.dupe(u8, "lxcbr0"),
            },
            .container_config = types.ContainerConfig{
                .default_runtime = .lxc,
            },
        };
    }

    pub fn getRoutedRuntime(self: *const Self, container_name: []const u8) types.RuntimeType {
        _ = self;
        _ = container_name;
        return .lxc;
    }

    pub fn deinit(self: *Self) void {
        if (self.log_file) |log_file| self.allocator.free(log_file);
        self.allocator.free(self.data_dir);
        self.network.deinit(self.allocator);
        self.container_config.deinit(self.allocator);
    }
};
