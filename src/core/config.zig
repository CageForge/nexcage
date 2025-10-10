const std = @import("std");
const types = @import("types.zig");
const logging = @import("logging.zig");
const ArrayList = std.ArrayList;

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
        // Try to load from default locations in order
        const default_paths = [_][]const u8{
            "./config.json",
            "/etc/nexcage/config.json",
            "/etc/nexcage/nexcage.json",
        };

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

        return self.loadFromString(file_content);
    }

    /// Load configuration from string
    pub fn loadFromString(self: *Self, json_string: []const u8) !Config {
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_string, .{}) catch |err| switch (err) {
            error.InvalidCharacter => return types.Error.InvalidConfig,
            error.InvalidNumber => return types.Error.InvalidConfig,
            error.UnexpectedEndOfInput => return types.Error.InvalidConfig,
            else => return err,
        };
        defer parsed.deinit();

        const value = parsed.value;
        return self.parseConfig(value);
    }

    pub fn parseConfig(self: *Self, value: std.json.Value) !Config {
        // Start with default config
        var config = try Config.init(self.allocator, .lxc);

        // runtime_type
        if (value.object.get("runtime_type")) |runtime_value| {
            switch (runtime_value) {
                .string => |runtime_str| {
                    config.runtime_type = self.parseRuntimeType(runtime_str);
                },
                else => {},
            }
        }

        // default_runtime
        if (value.object.get("default_runtime")) |default_value| {
            switch (default_value) {
                .string => |default_str| {
                    // replace allocated string safely
                    self.allocator.free(config.default_runtime);
                    config.default_runtime = try self.allocator.dupe(u8, default_str);
                },
                else => {},
            }
        }

        // runtime section with routing and other runtime-specific config
        if (value.object.get("runtime")) |runtime_section| {
            const runtime_obj = runtime_section.object;
            
            // Parse log_level
            if (runtime_obj.get("log_level")) |log_level_value| {
                switch (log_level_value) {
                    .string => |log_level_str| {
                        config.log_level = self.parseLogLevel(log_level_str);
                    },
                    else => {},
                }
            }
            
            // Parse log_path  
            if (runtime_obj.get("log_path")) |log_path_value| {
                switch (log_path_value) {
                    .string => |log_path_str| {
                        if (config.log_file) |old_log_file| {
                            self.allocator.free(old_log_file);
                        }
                        config.log_file = try self.allocator.dupe(u8, log_path_str);
                    },
                    else => {},
                }
            }
            
            // Parse root_path (data_dir)
            if (runtime_obj.get("root_path")) |root_path_value| {
                switch (root_path_value) {
                    .string => |root_path_str| {
                        self.allocator.free(config.data_dir);
                        config.data_dir = try self.allocator.dupe(u8, root_path_str);
                    },
                    else => {},
                }
            }
            
            // Parse routing configuration from runtime section
            if (runtime_obj.get("routing")) |routing_value| {
                switch (routing_value) {
                    .array => |routing_array| {
                        var routing_rules = try self.allocator.alloc(types.RoutingRule, routing_array.items.len);
                        for (routing_array.items, 0..) |rule_item, i| {
                            switch (rule_item) {
                                .object => |rule_obj| {
                                    const pattern = if (rule_obj.get("pattern")) |p| 
                                        switch (p) {
                                            .string => |s| s,
                                            else => "",
                                        } else "";
                                    const runtime_str = if (rule_obj.get("runtime")) |r| 
                                        switch (r) {
                                            .string => |s| s,
                                            else => "lxc",
                                        } else "lxc";
                                    
                                    routing_rules[i] = types.RoutingRule{
                                        .pattern = try self.allocator.dupe(u8, pattern),
                                        .runtime = self.parseRuntimeType(runtime_str),
                                    };
                                },
                                else => {
                                    // Initialize with default values for invalid entries
                                    routing_rules[i] = types.RoutingRule{
                                        .pattern = try self.allocator.dupe(u8, ""),
                                        .runtime = .lxc,
                                    };
                                },
                            }
                        }
                        
                        // Update container config with new routing rules
                        var container_cfg = config.container_config;
                        
                        // Clean up existing routing rules if any
                        for (container_cfg.routing) |*rule| {
                            var mutable_rule = rule.*;
                            mutable_rule.deinit(self.allocator);
                        }
                        self.allocator.free(container_cfg.routing);
                        
                        container_cfg.routing = routing_rules;
                        config.container_config = container_cfg;
                    },
                    else => {},
                }
            }
        }

        // log_level
        if (value.object.get("log_level")) |level_value| {
            switch (level_value) {
                .string => |level_str| {
                    config.log_level = self.parseLogLevel(level_str);
                },
                else => {},
            }
        }

        // log_file
        if (value.object.get("log_file")) |file_value| {
            switch (file_value) {
                .string => |file_str| {
                    if (config.log_file) |old| self.allocator.free(old);
                    config.log_file = try self.allocator.dupe(u8, file_str);
                },
                else => {},
            }
        }

        // data_dir
        if (value.object.get("data_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.data_dir);
                    config.data_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // cache_dir
        if (value.object.get("cache_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.cache_dir);
                    config.cache_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // temp_dir
        if (value.object.get("temp_dir")) |dir_value| {
            switch (dir_value) {
                .string => |dir_str| {
                    self.allocator.free(config.temp_dir);
                    config.temp_dir = try self.allocator.dupe(u8, dir_str);
                },
                else => {},
            }
        }

        // network
        if (value.object.get("network")) |network_value| {
            // start from existing defaults
            var net = config.network;
            const obj = network_value.object;

            if (obj.get("bridge")) |bridge_value| {
                switch (bridge_value) {
                    .string => |bridge_str| {
                        if (net.bridge) |old_bridge| self.allocator.free(old_bridge);
                        net.bridge = try self.allocator.dupe(u8, bridge_str);
                    },
                    else => {},
                }
            }

            if (obj.get("ip")) |ip_value| {
                switch (ip_value) {
                    .string => |ip_str| {
                        if (net.ip) |old_ip| self.allocator.free(old_ip);
                        net.ip = try self.allocator.dupe(u8, ip_str);
                    },
                    else => {},
                }
            }

            if (obj.get("gateway")) |gateway_value| {
                switch (gateway_value) {
                    .string => |gw_str| {
                        if (net.gateway) |old_gw| self.allocator.free(old_gw);
                        net.gateway = try self.allocator.dupe(u8, gw_str);
                    },
                    else => {},
                }
            }

            config.network = net;
        }

        // security
        if (value.object.get("security")) |sec_value| {
            const obj = sec_value.object;
            var sec = config.security;

            if (obj.get("seccomp")) |v| {
                switch (v) {
                    .bool => |b| sec.seccomp = b,
                    else => {},
                }
            }
            if (obj.get("apparmor")) |v| {
                switch (v) {
                    .bool => |b| sec.apparmor = b,
                    else => {},
                }
            }
            if (obj.get("read_only")) |v| {
                switch (v) {
                    .bool => |b| sec.read_only = b,
                    else => {},
                }
            }

            // capabilities: array of strings (by reference; not allocating here)
            // If needed later, we can dupe each entry and manage lifetime

            config.security = sec;
        }

        // resources
        if (value.object.get("resources")) |res_value| {
            const obj = res_value.object;
            var res = config.resources;

            if (obj.get("memory")) |v| {
                switch (v) {
                    .integer => |n| res.memory = @intCast(n),
                    else => {},
                }
            }
            if (obj.get("cpu")) |v| {
                switch (v) {
                    .float => |f| res.cpu = f,
                    .integer => |n| res.cpu = @floatFromInt(n),
                    else => {},
                }
            }
            if (obj.get("disk")) |v| {
                switch (v) {
                    .integer => |n| res.disk = @intCast(n),
                    else => {},
                }
            }
            if (obj.get("network_bandwidth")) |v| {
                switch (v) {
                    .integer => |n| res.network_bandwidth = @intCast(n),
                    else => {},
                }
            }

            config.resources = res;
        }

        // container_config
        if (value.object.get("container_config")) |container_value| {
            const obj = container_value.object;
            var container_cfg = config.container_config;

            if (obj.get("crun_name_patterns")) |patterns_value| {
                switch (patterns_value) {
                    .array => |patterns_array| {
                        var patterns = try self.allocator.alloc([]const u8, patterns_array.items.len);
                        for (patterns_array.items, 0..) |pattern_item, i| {
                            switch (pattern_item) {
                                .string => |pattern_str| {
                                    patterns[i] = try self.allocator.dupe(u8, pattern_str);
                                },
                                else => {},
                            }
                        }
                        container_cfg.crun_name_patterns = patterns;
                    },
                    else => {},
                }
            }

            if (obj.get("default_container_type")) |type_value| {
                switch (type_value) {
                    .string => |type_str| {
                        container_cfg.default_container_type = self.parseContainerType(type_str);
                    },
                    else => {},
                }
            }

            // Parse new routing configuration
            if (obj.get("routing")) |routing_value| {
                switch (routing_value) {
                    .array => |routing_array| {
                        var routing_rules = try self.allocator.alloc(types.RoutingRule, routing_array.items.len);
                        for (routing_array.items, 0..) |rule_item, i| {
                            switch (rule_item) {
                                .object => |rule_obj| {
                                    const pattern = if (rule_obj.get("pattern")) |p| 
                                        switch (p) {
                                            .string => |s| s,
                                            else => "",
                                        } else "";
                                    const runtime_str = if (rule_obj.get("runtime")) |r| 
                                        switch (r) {
                                            .string => |s| s,
                                            else => "lxc",
                                        } else "lxc";
                                    
                                    routing_rules[i] = types.RoutingRule{
                                        .pattern = try self.allocator.dupe(u8, pattern),
                                        .runtime = self.parseRuntimeType(runtime_str),
                                    };
                                },
                                else => {
                                    // Initialize with default values for invalid entries
                                    routing_rules[i] = types.RoutingRule{
                                        .pattern = try self.allocator.dupe(u8, ""),
                                        .runtime = .lxc,
                                    };
                                },
                            }
                        }
                        container_cfg.routing = routing_rules;
                    },
                    else => {},
                }
            }

            // Parse default_runtime if specified
            if (obj.get("default_runtime")) |runtime_value| {
                switch (runtime_value) {
                    .string => |runtime_str| {
                        container_cfg.default_runtime = self.parseRuntimeType(runtime_str);
                    },
                    else => {},
                }
            }

            config.container_config = container_cfg;
        }

        return config;
    }

    fn parseRuntimeType(self: *Self, runtime_str: []const u8) types.RuntimeType {
        _ = self;
        if (std.mem.eql(u8, runtime_str, "lxc")) {
            return .lxc;
        } else if (std.mem.eql(u8, runtime_str, "crun")) {
            return .crun;
        } else if (std.mem.eql(u8, runtime_str, "runc")) {
            return .runc;
        } else if (std.mem.eql(u8, runtime_str, "proxmox")) {
            return .vm; // proxmox maps to vm
        }
        return .lxc; // default
    }

    fn parseLogLevel(self: *Self, level_str: []const u8) logging.LogLevel {
        _ = self;
        if (std.mem.eql(u8, level_str, "debug")) {
            return .debug;
        } else if (std.mem.eql(u8, level_str, "info")) {
            return .info;
        } else if (std.mem.eql(u8, level_str, "warn")) {
            return .warn;
        } else if (std.mem.eql(u8, level_str, "error")) {
            return logging.LogLevel.@"error";
        }
        return .info; // default
    }

    fn parseContainerType(self: *Self, type_str: []const u8) types.ContainerType {
        _ = self;
        if (std.mem.eql(u8, type_str, "lxc")) {
            return .lxc;
        } else if (std.mem.eql(u8, type_str, "crun")) {
            return .crun;
        } else if (std.mem.eql(u8, type_str, "runc")) {
            return .runc;
        } else if (std.mem.eql(u8, type_str, "vm")) {
            return .vm;
        }
        return .lxc; // default
    }

    pub fn parseNetworkConfig(self: *Self, value: std.json.Value) !types.NetworkConfig {
        var config = types.NetworkConfig{
            .bridge = try self.allocator.dupe(u8, "lxcbr0"),
            .ip = null,
            .gateway = null,
        };

        if (value.object.get("bridge")) |bridge_value| {
            switch (bridge_value) {
                .string => |bridge_str| {
                    self.allocator.free(config.bridge);
                    config.bridge = try self.allocator.dupe(u8, bridge_str);
                },
                else => {},
            }
        }

        if (value.object.get("ip")) |ip_value| {
            switch (ip_value) {
                .string => |ip_str| {
                    config.ip = try self.allocator.dupe(u8, ip_str);
                },
                else => {},
            }
        }

        if (value.object.get("gateway")) |gateway_value| {
            switch (gateway_value) {
                .string => |gateway_str| {
                    config.gateway = try self.allocator.dupe(u8, gateway_str);
                },
                else => {},
            }
        }

        return config;
    }

    fn parseSecurityConfig(self: *Self, value: std.json.Value) !types.SecurityConfig {
        _ = self;
        _ = value;
        return types.SecurityConfig{
            .seccomp = null,
            .apparmor = null,
            .capabilities = null,
            .read_only = null,
        };
    }

    fn parseResourceLimits(self: *Self, value: std.json.Value) !types.ResourceLimits {
        _ = self;
        _ = value;
        return types.ResourceLimits{
            .memory = null,
            .cpu = null,
            .disk = null,
            .network_bandwidth = null,
        };
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

    pub fn init(allocator: std.mem.Allocator, runtime_type: types.RuntimeType) !Config {
        return Config{
            .allocator = allocator,
            .runtime_type = runtime_type,
            .default_runtime = try allocator.dupe(u8, "lxc"),
            .log_level = logging.LogLevel.info,
            .log_file = null,
            .data_dir = try allocator.dupe(u8, "/var/lib/nexcage"),
            .cache_dir = try allocator.dupe(u8, "/var/cache/nexcage"),
            .temp_dir = try allocator.dupe(u8, "/tmp/nexcage"),
            .network = types.NetworkConfig{
                .bridge = try allocator.dupe(u8, "lxcbr0"),
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
                .crun_name_patterns = &[_][]const u8{},
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
            .runc => .runc,
            .vm => .vm,
            else => self.container_config.default_container_type,
        };
    }

    /// Get runtime type based on routing rules with pattern matching
    pub fn getRoutedRuntime(self: *const Self, container_name: []const u8) types.RuntimeType {
        // Check new routing rules first (takes precedence)
        for (self.container_config.routing) |rule| {
            if (self.matchesRoutingPattern(container_name, rule.pattern)) {
                return rule.runtime;
            }
        }
        
        // Fallback to legacy pattern matching for backward compatibility
        for (self.container_config.crun_name_patterns) |pattern| {
            if (self.matchesPattern(container_name, pattern)) {
                return .crun;
            }
        }
        
        // Return default runtime
        return self.container_config.default_runtime;
    }

    fn matchesPattern(_: *const Self, name: []const u8, pattern: []const u8) bool {
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
        self.allocator.free(self.default_runtime);
        if (self.log_file) |log_file| {
            self.allocator.free(log_file);
        }
        self.allocator.free(self.data_dir);
        self.allocator.free(self.cache_dir);
        self.allocator.free(self.temp_dir);
        self.network.deinit(self.allocator);
        self.security.deinit();
        self.resources.deinit();
        self.container_config.deinit(self.allocator);
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
        pattern_clean = pattern_clean[0..pattern_clean.len - 1];
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
    const alternatives = pattern[open_paren + 1..close_paren];
    const suffix = pattern[close_paren + 1..];
    
    // Split alternatives by |
    var alt_iter = std.mem.splitSequence(u8, alternatives, "|");
    while (alt_iter.next()) |alt| {
        // Create combined pattern using allocator
        const total_len = prefix.len + alt.len + suffix.len;
        var combined = std.heap.page_allocator.alloc(u8, total_len) catch continue;
        defer std.heap.page_allocator.free(combined);
        
        std.mem.copyForwards(u8, combined[0..prefix.len], prefix);
        std.mem.copyForwards(u8, combined[prefix.len..prefix.len + alt.len], alt);
        std.mem.copyForwards(u8, combined[prefix.len + alt.len..], suffix);
        
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
            if (matchesExactRegex(name[pos..pos + pattern.len], pattern)) {
                return true;
            }
        }
        pos += 1;
    }
    return false;
}

