const std = @import("std");
const types = @import("types.zig");
const logging = @import("logging.zig");
const constants = @import("constants.zig");
const ArrayList = std.ArrayList;

/// Set from --config
var explicit_path: ?[]const u8 = null;

/// Makes loadDefault read `path` instead of searching the default locations,
/// or restores the search with null. `path` must outlive every later load;
/// main passes its argv.
pub fn setExplicitPath(path: ?[]const u8) void {
    explicit_path = path;
}

/// Where loadDefault looks when --config names no file, in order.
const default_paths = [_][]const u8{
    "./config.json",
    "/etc/nexcage/config.json",
    "/etc/nexcage/nexcage.json",
};

/// The file loadDefault reads: the one --config names, else the first default
/// location that exists. null when there is none and the built-in defaults
/// apply. For `health`, which used to look at files of its own.
pub fn activePath() ?[]const u8 {
    if (explicit_path) |path| return path;
    for (default_paths) |path| {
        // loadDefault moves on only past a file that is not there, so a file
        // that is there but cannot be read is still the one in use.
        std.fs.cwd().access(path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => {},
        };
        return path;
    }
    return null;
}

test "the file in use is the one --config names" {
    setExplicitPath("alt.json");
    defer setExplicitPath(null);
    try std.testing.expectEqualStrings("alt.json", activePath().?);
}

test "an explicit path replaces the default search, and must exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "alt.json", .data = "{\"network\":{\"bridge\":\"vmbr42\"}}" });
    const path = try tmp.dir.realpathAlloc(std.testing.allocator, "alt.json");
    defer std.testing.allocator.free(path);

    setExplicitPath(path);
    defer setExplicitPath(null);
    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadDefault();
    defer cfg.deinit();
    try std.testing.expectEqualStrings("vmbr42", cfg.network.bridge.?);

    setExplicitPath("/nonexistent/nexcage-config.json");
    try std.testing.expectError(types.Error.FileNotFound, loader.loadDefault());
}

/// Configuration loader and manager
pub const ConfigLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// A runtime named "runc" was read somewhere in the file. Reported by
    /// main once there is a logger: the rule routes to crun, and the file
    /// should say so itself.
    saw_runc: bool = false,
    /// A runtime naming the Proxmox VM backend, removed in 0.14.0, as the
    /// file wrote it. A string literal, not a slice of the parsed document,
    /// which is gone by the time main reads it.
    removed_vm_runtime: ?[]const u8 = null,
    /// What was wrong with the file when a load failed with InvalidConfig --
    /// the key it stopped at, or that it is not JSON. main prints it.
    problem_buf: [256]u8 = undefined,
    problem_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Load configuration from default locations
    pub fn loadDefault(self: *Self) !Config {
        // --config replaces the search: a missing file is an error there, not
        // a reason to fall back to the defaults
        if (explicit_path) |path| {
            // Named on the command line, so silence would be wrong: say it is
            // the wrong kind of file rather than "not found".
            return self.loadFromFile(path) catch |err| switch (err) {
                types.Error.FileNotFound => blk: {
                    const content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch break :blk types.Error.FileNotFound;
                    defer self.allocator.free(content);
                    break :blk if (isOciSpec(content)) self.refuse("it is an OCI runtime spec, not a nexcage configuration", .{}) else types.Error.FileNotFound;
                },
                else => err,
            };
        }

        // Try to load from default locations in order
        for (default_paths) |path| {
            if (self.loadFromFile(path)) |config| {
                return config;
            } else |err| switch (err) {
                types.Error.FileNotFound => continue,
                else => return err,
            }
        }

        // Return default config if no file found
        return try Config.init(self.allocator, .lxc);
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Self, path: []const u8) !Config {
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return types.Error.FileNotFound,
            else => return err,
        };
        defer self.allocator.free(file_content);

        // An OCI bundle holds a config.json that is a runtime spec, not
        // nexcage's configuration, and a container engine runs the runtime
        // from the bundle directory — so ./config.json in the search path
        // found the spec and silently replaced the real configuration, taking
        // the routing rules with it. A file declaring ociVersion is not ours.
        if (isOciSpec(file_content)) return types.Error.FileNotFound;

        return self.loadFromString(file_content);
    }

    /// Whether this is an OCI runtime spec rather than a nexcage config.
    /// Checked on the text: the spec parses as JSON perfectly well, so
    /// parsing cannot tell them apart, and the difference is that a spec
    /// declares ociVersion at the top level.
    fn isOciSpec(content: []const u8) bool {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, content, .{}) catch return false;
        defer parsed.deinit();
        if (parsed.value != .object) return false;
        return parsed.value.object.get("ociVersion") != null;
    }

    /// Load configuration from string
    pub fn loadFromString(self: *Self, json_string: []const u8) !Config {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_string, .{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return self.refuse("it is not valid JSON ({s})", .{@errorName(err)}),
        };
        defer parsed.deinit();

        const value = parsed.value;
        return self.parseConfig(value);
    }

    pub fn parseConfig(self: *Self, value: std.json.Value) !Config {
        // Everything below relies on the names and types validate checked.
        try self.validate(value);

        var config = try Config.init(self.allocator, .lxc);
        errdefer config.deinit();
        const root = value.object;

        if (root.get("runtime")) |section| {
            const obj = section.object;
            if (obj.get("log_level")) |v| config.log_level = logLevel(v.string).?;
            if (obj.get("log_path")) |v| try self.replace(&config.log_file, v.string);
            if (obj.get("routing")) |v| try self.setRouting(&config.container_config, v.array.items);
        }
        // The top-level spellings win over the runtime section's.
        if (root.get("log_level")) |v| config.log_level = logLevel(v.string).?;
        if (root.get("log_file")) |v| try self.replace(&config.log_file, v.string);

        if (root.get("network")) |section| {
            if (section.object.get("bridge")) |v| try self.replace(&config.network.bridge, v.string);
        }

        if (root.get("proxmox")) |section| {
            const obj = section.object;
            if (obj.get("storage")) |v| try self.replace(&config.proxmox.storage, v.string);
            if (obj.get("rootfs_size_gb")) |v| config.proxmox.rootfs_size_gb = @intCast(v.integer);
            if (obj.get("ostype")) |v| try self.replace(&config.proxmox.ostype, v.string);
            if (obj.get("unprivileged")) |v| config.proxmox.unprivileged = v.bool;
        }

        // Read for files written before runtime.routing; a list here replaces
        // the one there wholesale.
        if (root.get("container_config")) |section| {
            const obj = section.object;
            if (obj.get("routing")) |v| try self.setRouting(&config.container_config, v.array.items);
            if (obj.get("default_runtime")) |v| config.container_config.default_runtime = self.runtimeOf(v.string);
        }

        config.legacy_runc_runtime = self.saw_runc;
        config.removed_vm_runtime = self.removed_vm_runtime;
        return config;
    }

    /// The keys nexcage reads, and what each must hold. A key not here is
    /// refused rather than skipped: a misspelt key did nothing without a word,
    /// and so did keys that were parsed and never used -- `security.seccomp:
    /// true` turned nothing on (#371).
    const Kind = enum { section, string, boolean, size_gb, log_level, runtime, rules };
    const Key = struct { name: []const u8, kind: Kind, keys: []const Key = &.{} };

    const rule_keys = [_]Key{
        .{ .name = "pattern", .kind = .string },
        .{ .name = "runtime", .kind = .runtime },
    };

    const schema = [_]Key{
        .{ .name = "runtime", .kind = .section, .keys = &.{
            .{ .name = "log_level", .kind = .log_level },
            .{ .name = "log_path", .kind = .string },
            .{ .name = "routing", .kind = .rules },
        } },
        .{ .name = "log_level", .kind = .log_level },
        .{ .name = "log_file", .kind = .string },
        .{ .name = "network", .kind = .section, .keys = &.{
            .{ .name = "bridge", .kind = .string },
        } },
        .{ .name = "proxmox", .kind = .section, .keys = &.{
            .{ .name = "storage", .kind = .string },
            .{ .name = "rootfs_size_gb", .kind = .size_gb },
            .{ .name = "ostype", .kind = .string },
            .{ .name = "unprivileged", .kind = .boolean },
        } },
        .{ .name = "container_config", .kind = .section, .keys = &.{
            .{ .name = "routing", .kind = .rules },
            .{ .name = "default_runtime", .kind = .runtime },
        } },
    };

    /// Runtime names a routing rule may give. "runc" routes to crun with a
    /// warning; "vm" and "proxmox" are let through so that main can refuse
    /// the file saying the VM backend is gone.
    const runtime_names = [_][]const u8{ "lxc", "proxmox-lxc", "crun", "runc", "vm", "proxmox" };

    fn validate(self: *Self, value: std.json.Value) types.Error!void {
        switch (value) {
            .object => |obj| try self.validateObject(obj, &schema, ""),
            else => return self.refuse("it must hold a JSON object", .{}),
        }
    }

    fn validateObject(self: *Self, obj: std.json.ObjectMap, keys: []const Key, path: []const u8) types.Error!void {
        var it = obj.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            var buf: [160]u8 = undefined;
            const sub = if (path.len == 0) name else std.fmt.bufPrint(&buf, "{s}.{s}", .{ path, name }) catch name;
            const key = for (keys) |k| {
                if (std.mem.eql(u8, k.name, name)) break k;
            } else {
                // Removed in 0.13.0, and its replacement is one line.
                if (std.mem.eql(u8, sub, "container_config.crun_name_patterns"))
                    return self.refuse("'{s}' is not read since 0.13.0; put each glob under runtime.routing as {{\"pattern\": \"<glob>\", \"runtime\": \"crun\"}}", .{sub});
                return self.refuse("'{s}' is not a key nexcage reads", .{sub});
            };
            try self.validateValue(entry.value_ptr.*, key, sub);
        }
    }

    fn validateValue(self: *Self, value: std.json.Value, key: Key, path: []const u8) types.Error!void {
        switch (key.kind) {
            .section => switch (value) {
                .object => |obj| try self.validateObject(obj, key.keys, path),
                else => return self.refuse("'{s}' must be an object", .{path}),
            },
            .string => if (value != .string) return self.refuse("'{s}' must be a string", .{path}),
            .boolean => if (value != .bool) return self.refuse("'{s}' must be true or false", .{path}),
            // Zero would reach pct as "<storage>:0".
            .size_gb => switch (value) {
                .integer => |n| if (n < 1 or n > std.math.maxInt(u32)) return self.refuse("'{s}' must be a whole number of GB, 1 or more", .{path}),
                else => return self.refuse("'{s}' must be a whole number of GB, 1 or more", .{path}),
            },
            .log_level => switch (value) {
                .string => |s| if (logLevel(s) == null) return self.refuse("'{s}' is \"{s}\"; it must be debug, info, warn or error", .{ path, s }),
                else => return self.refuse("'{s}' must be debug, info, warn or error", .{path}),
            },
            .runtime => switch (value) {
                .string => |s| for (runtime_names) |n| {
                    if (std.mem.eql(u8, n, s)) break;
                } else return self.refuse("'{s}' is \"{s}\", which is not a runtime; name lxc or crun", .{ path, s }),
                else => return self.refuse("'{s}' must be a runtime name, lxc or crun", .{path}),
            },
            .rules => switch (value) {
                .array => |items| for (items.items, 0..) |item, i| {
                    var buf: [160]u8 = undefined;
                    const sub = std.fmt.bufPrint(&buf, "{s}[{d}]", .{ path, i }) catch path;
                    switch (item) {
                        .object => |obj| {
                            try self.validateObject(obj, &rule_keys, sub);
                            for (rule_keys) |k| {
                                if (obj.get(k.name) == null) return self.refuse("'{s}' has no \"{s}\"", .{ sub, k.name });
                            }
                        },
                        else => return self.refuse("'{s}' must be an object with \"pattern\" and \"runtime\"", .{sub}),
                    }
                },
                else => return self.refuse("'{s}' must be a list of rules", .{path}),
            },
        }
    }

    /// Records why the file is refused, for main to print, and returns the
    /// error that says it was.
    fn refuse(self: *Self, comptime format: []const u8, args: anytype) types.Error {
        const msg = std.fmt.bufPrint(&self.problem_buf, format, args) catch self.problem_buf[0..];
        self.problem_len = msg.len;
        return types.Error.InvalidConfig;
    }

    /// Why the last load failed with InvalidConfig, or null.
    pub fn problem(self: *const Self) ?[]const u8 {
        return if (self.problem_len == 0) null else self.problem_buf[0..self.problem_len];
    }

    /// Puts a copy of `s` in `slot`, freeing what was there.
    fn replace(self: *Self, slot: *?[]const u8, s: []const u8) !void {
        const copy = try self.allocator.dupe(u8, s);
        if (slot.*) |old| self.allocator.free(old);
        slot.* = copy;
    }

    /// Replaces the routing rules with `items`, which validate checked.
    fn setRouting(self: *Self, container_config: *types.ContainerConfig, items: []const std.json.Value) !void {
        const rules = try self.allocator.alloc(types.RoutingRule, items.len);
        var made: usize = 0;
        errdefer {
            for (rules[0..made]) |rule| rule.deinit(self.allocator);
            self.allocator.free(rules);
        }
        for (items) |item| {
            const obj = item.object;
            rules[made] = .{
                .pattern = try self.allocator.dupe(u8, obj.get("pattern").?.string),
                .runtime = self.runtimeOf(obj.get("runtime").?.string),
            };
            made += 1;
        }
        container_config.deinit(self.allocator);
        container_config.routing = rules;
    }

    /// The backend a runtime name routes to; validate let only runtime_names
    /// through.
    fn runtimeOf(self: *Self, name: []const u8) types.RuntimeType {
        if (std.mem.eql(u8, name, "crun")) return .crun;
        // The runc backend was removed in 0.13.0. A container a rule sent to
        // it is an OCI container, and crun is the OCI backend -- so the rule
        // keeps working, and main says what it now means.
        if (std.mem.eql(u8, name, "runc")) {
            self.saw_runc = true;
            return .crun;
        }
        // The Proxmox VM backend was removed in 0.14.0, and "proxmox" was
        // mapped to it. The default backend is not a substitute, so main
        // refuses the file and this value is never routed on.
        if (std.mem.eql(u8, name, "vm") or std.mem.eql(u8, name, "proxmox")) {
            self.removed_vm_runtime = if (std.mem.eql(u8, name, "vm")) "vm" else "proxmox";
            return .lxc;
        }
        return .lxc; // "lxc", or "proxmox-lxc" as --runtime spells it
    }

    fn logLevel(name: []const u8) ?logging.LogLevel {
        if (std.mem.eql(u8, name, "debug")) return .debug;
        if (std.mem.eql(u8, name, "info")) return .info;
        if (std.mem.eql(u8, name, "warn")) return .warn;
        if (std.mem.eql(u8, name, "error")) return .@"error";
        return null;
    }
};

/// Global configuration structure
pub const Config = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    runtime_type: types.RuntimeType,
    default_runtime: []const u8,
    log_level: logging.LogLevel,
    log_file: ?[]const u8,
    data_dir: []const u8,
    cache_dir: []const u8,
    temp_dir: []const u8,
    network: types.NetworkConfig,
    security: types.SecurityConfig,
    resources: types.ResourceLimits,
    container_config: types.ContainerConfig,
    proxmox: types.ProxmoxSettings = .{},
    /// The file names "runc" as a runtime. The backend was removed in 0.13.0;
    /// such a rule routes to crun, and main says so once it can.
    legacy_runc_runtime: bool = false,
    /// The file names the Proxmox VM backend, removed in 0.14.0, as a
    /// runtime: "vm", or "proxmox", which was mapped to it. No backend runs
    /// what such a rule describes, so main refuses the file.
    removed_vm_runtime: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, runtime_type: types.RuntimeType) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = runtime_type,
            .default_runtime = try allocator.dupe(u8, "proxmox-lxc"),
            .log_level = logging.LogLevel.info,
            .log_file = null,
            .data_dir = try allocator.dupe(u8, "/var/lib/nexcage"),
            .cache_dir = try allocator.dupe(u8, "/var/cache/nexcage"),
            .temp_dir = try allocator.dupe(u8, "/tmp/nexcage"),
            .network = types.NetworkConfig{
                // Proxmox's own bridge; lxcbr0 belongs to plain LXC and does not exist on PVE
                .bridge = try allocator.dupe(u8, constants.DEFAULT_BRIDGE_NAME),
                .ip = null,
                .gateway = null,
            },
            .security = types.SecurityConfig{
                .seccomp = null,
                .apparmor = null,
                .capabilities = null,
                .read_only = null,
            },
            .resources = types.ResourceLimits{
                .memory = null,
                .cpu = null,
                .disk = null,
                .network_bandwidth = null,
            },
            .container_config = types.ContainerConfig{
                .default_container_type = .lxc,
                .routing = &[_]types.RoutingRule{},
                .default_runtime = .lxc,
            },
        };
    }

    pub fn getContainerType(self: *const Self, container_name: []const u8) types.ContainerType {
        // Try new routing system first
        const runtime_type = self.getRoutedRuntime(container_name);
        return switch (runtime_type) {
            .lxc => .lxc,
            .crun => .crun,
            .proxmox_lxc => .proxmox_lxc,
        };
    }

    /// The backend a container goes to: the first routing rule its name
    /// matches, else the default. ADR-001 is the record of why this is a
    /// name lookup and nothing more -- there is no fallback from one backend
    /// to another, because a container is one thing on one backend.
    pub fn getRoutedRuntime(self: *const Self, container_name: []const u8) types.RuntimeType {
        for (self.container_config.routing) |rule| {
            if (self.matchesRoutingPattern(container_name, rule.pattern)) {
                return rule.runtime;
            }
        }
        return self.container_config.default_runtime;
    }

    /// Enhanced pattern matching that supports both simple wildcards and basic regex patterns
    pub fn matchesRoutingPattern(_: *const Self, name: []const u8, pattern: []const u8) bool {
        // Check if pattern looks like a regex (starts with ^ or ends with $)
        if (pattern.len > 0 and (pattern[0] == '^' or pattern[pattern.len - 1] == '$')) {
            return matchesRegexPattern(name, pattern);
        }

        // Fallback to simple wildcard matching for non-regex patterns
        return matchesWildcardPattern(name, pattern);
    }

    /// Simple wildcard pattern matching (existing logic)
    fn matchesWildcardPattern(name: []const u8, pattern: []const u8) bool {
        var name_idx: usize = 0;
        var pattern_idx: usize = 0;

        while (pattern_idx < pattern.len) {
            if (pattern[pattern_idx] == '*') {
                // Skip until next pattern character or end
                while (name_idx < name.len and (pattern_idx + 1 >= pattern.len or name[name_idx] != pattern[pattern_idx + 1])) {
                    name_idx += 1;
                }
                pattern_idx += 1;
            } else if (name_idx < name.len and pattern[pattern_idx] == name[name_idx]) {
                name_idx += 1;
                pattern_idx += 1;
            } else {
                return false;
            }
        }

        return name_idx == name.len;
    }

    pub fn deinit(self: *Self) void {
        // Always free default_runtime - it's always allocated dynamically in init() or parseConfig()
        self.allocator.free(self.default_runtime);

        if (self.log_file) |log_file| {
            // Always free log_file - it's allocated by parseConfig
            self.allocator.free(log_file);
        }
        self.allocator.free(self.data_dir);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.temp_dir);
        self.network.deinit(self.allocator);
        self.security.deinit();
        self.resources.deinit();
        self.container_config.deinit(self.allocator);
        self.proxmox.deinit(self.allocator);
    }
};

/// Public standalone regex pattern matching function for testing
pub fn matchesRegexPattern(name: []const u8, pattern: []const u8) bool {
    var pattern_clean = pattern;
    const name_clean = name;

    // Handle ^ anchor (start of string)
    var start_anchor = false;
    if (pattern_clean.len > 0 and pattern_clean[0] == '^') {
        start_anchor = true;
        pattern_clean = pattern_clean[1..];
    }

    // Handle $ anchor (end of string)
    var end_anchor = false;
    if (pattern_clean.len > 0 and pattern_clean[pattern_clean.len - 1] == '$') {
        end_anchor = true;
        pattern_clean = pattern_clean[0 .. pattern_clean.len - 1];
    }

    // Handle alternation patterns like (kube-ovn-.*|cilium-.*)
    if (std.mem.indexOf(u8, pattern_clean, "|")) |_| {
        return matchesAlternationPattern(name_clean, pattern_clean, start_anchor, end_anchor);
    }

    // Handle simple regex patterns
    return matchesSimpleRegex(name_clean, pattern_clean, start_anchor, end_anchor);
}

/// Handle alternation patterns like (kube-ovn-.*|cilium-.*)
fn matchesAlternationPattern(name: []const u8, pattern: []const u8, start_anchor: bool, end_anchor: bool) bool {
    // Find parentheses
    const open_paren = std.mem.indexOf(u8, pattern, "(") orelse return false;
    const close_paren = std.mem.lastIndexOf(u8, pattern, ")") orelse return false;

    if (open_paren >= close_paren) return false;

    const prefix = pattern[0..open_paren];
    const alternatives = pattern[open_paren + 1 .. close_paren];
    const suffix = pattern[close_paren + 1 ..];

    // Split alternatives by |
    var alt_iter = std.mem.splitSequence(u8, alternatives, "|");
    while (alt_iter.next()) |alt| {
        // Create combined pattern using allocator
        const total_len = prefix.len + alt.len + suffix.len;
        var combined = std.heap.page_allocator.alloc(u8, total_len) catch continue;
        defer std.heap.page_allocator.free(combined);

        std.mem.copyForwards(u8, combined[0..prefix.len], prefix);
        std.mem.copyForwards(u8, combined[prefix.len .. prefix.len + alt.len], alt);
        std.mem.copyForwards(u8, combined[prefix.len + alt.len ..], suffix);

        if (matchesSimpleRegex(name, combined, start_anchor, end_anchor)) {
            return true;
        }
    }

    return false;
}

/// Simple regex pattern matching for basic patterns
fn matchesSimpleRegex(name: []const u8, pattern: []const u8, start_anchor: bool, end_anchor: bool) bool {
    if (start_anchor and end_anchor) {
        // Must match exactly
        return matchesExactRegex(name, pattern);
    } else if (start_anchor) {
        // Must match from start
        return matchesFromStart(name, pattern);
    } else if (end_anchor) {
        // Must match at end
        return matchesAtEnd(name, pattern);
    } else {
        // Can match anywhere
        return matchesAnywhere(name, pattern);
    }
}

/// Exact regex matching (for patterns with both ^ and $)
fn matchesExactRegex(name: []const u8, pattern: []const u8) bool {
    var name_idx: usize = 0;
    var pattern_idx: usize = 0;

    while (pattern_idx < pattern.len and name_idx <= name.len) {
        if (pattern_idx + 1 < pattern.len and pattern[pattern_idx + 1] == '*') {
            // Handle .* or character*
            const char_to_match = pattern[pattern_idx];
            pattern_idx += 2;

            if (char_to_match == '.') {
                // .* matches any characters
                if (pattern_idx >= pattern.len) {
                    return true; // .* at end matches rest of string
                }
                // Try to match the rest of the pattern at different positions
                while (name_idx <= name.len) {
                    if (matchesExactRegex(name[name_idx..], pattern[pattern_idx..])) {
                        return true;
                    }
                    name_idx += 1;
                }
                return false;
            } else {
                // character* matches repeated character
                while (name_idx < name.len and name[name_idx] == char_to_match) {
                    name_idx += 1;
                }
            }
        } else if (pattern[pattern_idx] == '.') {
            // . matches any single character
            if (name_idx >= name.len) return false;
            name_idx += 1;
            pattern_idx += 1;
        } else {
            // Literal character match
            if (name_idx >= name.len or name[name_idx] != pattern[pattern_idx]) {
                return false;
            }
            name_idx += 1;
            pattern_idx += 1;
        }
    }

    return pattern_idx == pattern.len and name_idx == name.len;
}

/// Match from start (patterns with ^)
fn matchesFromStart(name: []const u8, pattern: []const u8) bool {
    // For now, treat as exact match - can be enhanced later
    return matchesExactRegex(name, pattern);
}

/// Match at end (patterns with $)
fn matchesAtEnd(name: []const u8, pattern: []const u8) bool {
    if (pattern.len > name.len) return false;

    const start_pos = name.len - pattern.len;
    return matchesExactRegex(name[start_pos..], pattern);
}

/// Match anywhere in string
fn matchesAnywhere(name: []const u8, pattern: []const u8) bool {
    var pos: usize = 0;
    while (pos <= name.len) {
        if (pos + pattern.len <= name.len) {
            if (matchesExactRegex(name[pos .. pos + pattern.len], pattern)) {
                return true;
            }
        }
        pos += 1;
    }
    return false;
}

test "the proxmox section and bridge reach Config" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadFromString(
        \\{
        \\  "network": { "bridge": "vmbr9" },
        \\  "proxmox": { "storage": "local-zfs", "rootfs_size_gb": 4, "ostype": "debian",
        \\               "unprivileged": true }
        \\}
    );
    defer cfg.deinit();

    try std.testing.expectEqualStrings("vmbr9", cfg.network.bridge.?);
    try std.testing.expectEqualStrings("local-zfs", cfg.proxmox.storage.?);
    try std.testing.expectEqual(@as(?u32, 4), cfg.proxmox.rootfs_size_gb);
    try std.testing.expectEqualStrings("debian", cfg.proxmox.ostype.?);
    try std.testing.expectEqual(@as(?bool, true), cfg.proxmox.unprivileged);
}

test "a root filesystem size below 1 GiB is rejected" {
    var loader = ConfigLoader.init(std.testing.allocator);
    try std.testing.expectError(types.Error.InvalidConfig, loader.loadFromString(
        \\{ "proxmox": { "storage": "local-lvm", "rootfs_size_gb": 0 } }
    ));
}

test "without a config file the defaults target a Proxmox host" {
    var cfg = try Config.init(std.testing.allocator, .lxc);
    defer cfg.deinit();

    try std.testing.expectEqualStrings(constants.DEFAULT_BRIDGE_NAME, cfg.network.bridge.?);
    try std.testing.expect(cfg.proxmox.storage == null);
    try std.testing.expect(cfg.proxmox.rootfs_size_gb == null);
}

test "routing is a name lookup: a glob under runtime.routing, first match wins" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadFromString(
        \\{ "runtime": { "routing": [ { "pattern": "kube-ovn-*", "runtime": "crun" } ] } }
    );
    defer cfg.deinit();

    try std.testing.expectEqual(types.RuntimeType.crun, cfg.getRoutedRuntime("kube-ovn-1"));
    try std.testing.expectEqual(cfg.container_config.default_runtime, cfg.getRoutedRuntime("web-1"));
}

test "a file is refused at the first key nexcage does not read, which the message names" {
    const cases = [_]struct { file: []const u8, says: []const u8 }{
        // A misspelt key used to do nothing without a word.
        .{ .file = "{ \"routnig\": [] }", .says = "'routnig' is not a key nexcage reads" },
        // Keys that were parsed and never used: this one turned nothing on.
        .{ .file = "{ \"security\": { \"seccomp\": true } }", .says = "'security' is not a key nexcage reads" },
        .{ .file = "{ \"proxmox\": { \"pct_path\": \"/usr/sbin/pct\" } }", .says = "'proxmox.pct_path' is not a key nexcage reads" },
        .{ .file = "{ \"container_config\": { \"crun_name_patterns\": [\"kube-ovn-*\"] } }", .says = "put each glob under runtime.routing" },
        // A misspelt runtime routed to LXC.
        .{ .file = "{ \"runtime\": { \"routing\": [ { \"pattern\": \"*\", \"runtime\": \"crn\" } ] } }", .says = "'runtime.routing[0].runtime' is \"crn\", which is not a runtime" },
        .{ .file = "{ \"runtime\": { \"routing\": [ { \"pattern\": \"*\" } ] } }", .says = "'runtime.routing[0]' has no \"runtime\"" },
        // A section of the wrong type panicked.
        .{ .file = "{ \"runtime\": 5 }", .says = "'runtime' must be an object" },
        .{ .file = "{ \"network\": [] }", .says = "'network' must be an object" },
        .{ .file = "{ \"log_level\": \"verbose\" }", .says = "it must be debug, info, warn or error" },
        .{ .file = "{ \"proxmox\": { \"unprivileged\": \"yes\" } }", .says = "'proxmox.unprivileged' must be true or false" },
        .{ .file = "[ 1 ]", .says = "it must hold a JSON object" },
        .{ .file = "{ \"network\":", .says = "it is not valid JSON" },
    };
    for (cases) |case| {
        var loader = ConfigLoader.init(std.testing.allocator);
        try std.testing.expectError(types.Error.InvalidConfig, loader.loadFromString(case.file));
        const why = loader.problem() orelse return error.TestExpectedProblem;
        if (std.mem.indexOf(u8, why, case.says) == null) {
            std.debug.print("for {s}: got \"{s}\"\n", .{ case.file, why });
            return error.TestUnexpectedProblem;
        }
    }
}

test "\"proxmox-lxc\", as --runtime spells it, is read as lxc" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadFromString(
        \\{ "runtime": { "routing": [ { "pattern": "*", "runtime": "proxmox-lxc" } ] } }
    );
    defer cfg.deinit();
    try std.testing.expectEqual(types.RuntimeType.lxc, cfg.getRoutedRuntime("web-1"));
}

test "a rule naming runc routes to crun and is flagged: the backend is gone, the container is still OCI" {
    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadFromString(
        \\{ "runtime": { "routing": [ { "pattern": "*", "runtime": "runc" } ] } }
    );
    defer cfg.deinit();

    try std.testing.expectEqual(types.RuntimeType.crun, cfg.getRoutedRuntime("anything"));
    try std.testing.expect(cfg.legacy_runc_runtime);
}

test "a file naming the removed VM backend is flagged, however it names it, so main can refuse it" {
    const files = [_][]const u8{
        \\{ "runtime": { "routing": [ { "pattern": "vm-*", "runtime": "vm" } ] } }
        ,
        \\{ "container_config": { "routing": [ { "pattern": "*", "runtime": "proxmox" } ] } }
        ,
        \\{ "container_config": { "default_runtime": "vm" } }
    };
    for (files) |file| {
        var loader = ConfigLoader.init(std.testing.allocator);
        var cfg = try loader.loadFromString(file);
        defer cfg.deinit();
        try std.testing.expect(cfg.removed_vm_runtime != null);
    }

    var loader = ConfigLoader.init(std.testing.allocator);
    var cfg = try loader.loadFromString(
        \\{ "runtime": { "routing": [ { "pattern": "*", "runtime": "crun" } ] } }
    );
    defer cfg.deinit();
    try std.testing.expect(cfg.removed_vm_runtime == null);
}
