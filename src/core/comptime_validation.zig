const std = @import("std");
const types = @import("types.zig");

/// Comptime validation utilities for type-safe configuration
/// This module provides compile-time checks and validations

/// Validate that a config type has required fields
pub fn validateConfigType(comptime ConfigType: type) void {
    comptime {
        const type_info = @typeInfo(ConfigType);
        if (type_info != .Struct) {
            @compileError("ConfigType must be a struct");
        }

        // Check for runtime_type field
        const struct_info = type_info.Struct;
        var has_runtime_type = false;
        for (struct_info.fields) |field| {
            if (std.mem.eql(u8, field.name, "runtime_type")) {
                has_runtime_type = true;
                break;
            }
        }
        if (!has_runtime_type) {
            @compileError("Config type must have 'runtime_type' field");
        }

        // Validate that deinit exists
        if (@hasDecl(ConfigType, "deinit")) {
            const deinit_info = @typeInfo(@TypeOf(ConfigType.deinit));
            if (deinit_info != .Fn) {
                @compileError("Config type 'deinit' must be a function");
            }
        } else {
            @compileError("Config type must implement 'deinit()' method");
        }
    }
}

/// Validate that a struct has all required fields
pub fn hasRequiredFields(comptime T: type, comptime required_fields: []const []const u8) bool {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .Struct) {
            return false;
        }

        const struct_info = type_info.Struct;
        for (required_fields) |field_name| {
            var found = false;
            for (struct_info.fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                return false;
            }
        }
        return true;
    }
}

/// Compile-time check that struct has field
pub fn assertHasField(comptime T: type, comptime field_name: []const u8) void {
    comptime {
        if (!hasField(T, field_name)) {
            @compileError("Type " ++ @typeName(T) ++ " must have field '" ++ field_name ++ "'");
        }
    }
}

/// Check if type has a specific field
pub fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    comptime {
        const type_info = @typeInfo(T);
        if (type_info != .Struct) {
            return false;
        }

        const struct_info = type_info.Struct;
        for (struct_info.fields) |field| {
            if (std.mem.eql(u8, field.name, field_name)) {
                return true;
            }
        }
        return false;
    }
}

/// Compile-time check that struct implements method
pub fn assertHasMethod(comptime T: type, comptime method_name: []const u8) void {
    comptime {
        if (!hasMethod(T, method_name)) {
            @compileError("Type " ++ @typeName(T) ++ " must implement method '" ++ method_name ++ "()'");
        }
    }
}

/// Check if type has a specific method
pub fn hasMethod(comptime T: type, comptime method_name: []const u8) bool {
    comptime {
        return @hasDecl(T, method_name);
    }
}

/// Validate SandboxConfig structure at compile time
pub fn validateSandboxConfig() void {
    comptime {
        validateConfigType(types.SandboxConfig);
        
        const required_fields = [_][]const u8{ "allocator", "name", "runtime_type" };
        if (!hasRequiredFields(types.SandboxConfig, &required_fields)) {
            @compileError("SandboxConfig missing required fields");
        }

        assertHasMethod(types.SandboxConfig, "deinit");
    }
}

/// Validate ResourceLimits structure at compile time
pub fn validateResourceLimits() void {
    comptime {
        const required_fields = [_][]const u8{ "memory", "cpu", "disk", "network_bandwidth" };
        if (!hasRequiredFields(types.ResourceLimits, &required_fields)) {
            @compileError("ResourceLimits missing required fields");
        }

        assertHasMethod(types.ResourceLimits, "deinit");
    }
}

/// Validate NetworkConfig structure at compile time
pub fn validateNetworkConfig() void {
    comptime {
        assertHasMethod(types.NetworkConfig, "deinit");
    }
}

/// Generic configuration validator
/// Validates that config type has required fields and methods
pub fn validateConfigStruct(comptime ConfigType: type, comptime required_fields: []const []const u8) void {
    comptime {
        const type_info = @typeInfo(ConfigType);
        if (type_info != .Struct) {
            @compileError("ConfigType must be a struct");
        }

        // Check required fields
        for (required_fields) |field_name| {
            assertHasField(ConfigType, field_name);
        }

        // Check for deinit method
        assertHasMethod(ConfigType, "deinit");
    }
}

/// Type-safe configuration builder using comptime
pub fn ConfigBuilder(comptime ConfigType: type) type {
    return struct {
        const Self = @This();
        const BuilderConfig = ConfigType;

        allocator: std.mem.Allocator,
        config: ConfigType,

        /// Initialize builder with default config
        pub fn init(allocator: std.mem.Allocator, default_config: ConfigType) Self {
            comptime {
                validateConfigStruct(ConfigType, &[_][]const u8{"allocator"});
            }

            return Self{
                .allocator = allocator,
                .config = default_config,
            };
        }

        /// Set field value (type-safe)
        pub fn set(self: *Self, comptime field_name: []const u8, value: anytype) !void {
            comptime {
                assertHasField(ConfigType, field_name);
            }

            @field(self.config, field_name) = value;
        }

        /// Build final configuration
        pub fn build(self: *Self) ConfigType {
            return self.config;
        }
    };
}

/// Runtime type validation using comptime string operations
pub fn parseRuntimeTypeComptime(comptime runtime_str: []const u8) types.RuntimeType {
    comptime {
        return switch (runtime_str.len) {
            3 => if (std.mem.eql(u8, runtime_str, "lxc")) types.RuntimeType.lxc else @compileError("Invalid runtime type"),
            4 => if (std.mem.eql(u8, runtime_str, "crun")) types.RuntimeType.crun else if (std.mem.eql(u8, runtime_str, "runc")) types.RuntimeType.runc else @compileError("Invalid runtime type"),
            2 => if (std.mem.eql(u8, runtime_str, "vm")) types.RuntimeType.vm else @compileError("Invalid runtime type"),
            11 => if (std.mem.eql(u8, runtime_str, "proxmox_lxc")) types.RuntimeType.proxmox_lxc else @compileError("Invalid runtime type"),
            else => @compileError("Invalid runtime type length"),
        };
    }
}

/// Compile-time string operations for configuration
pub const StringOps = struct {
    /// Check if string starts with prefix (comptime)
    pub fn startsWith(comptime str: []const u8, comptime prefix: []const u8) bool {
        comptime {
            if (prefix.len > str.len) return false;
            for (prefix, 0..) |char, i| {
                if (str[i] != char) return false;
            }
            return true;
        }
    }

    /// Check if string ends with suffix (comptime)
    pub fn endsWith(comptime str: []const u8, comptime suffix: []const u8) bool {
        comptime {
            if (suffix.len > str.len) return false;
            const start = str.len - suffix.len;
            for (suffix, 0..) |char, i| {
                if (str[start + i] != char) return false;
            }
            return true;
        }
    }

    /// Check if string contains substring (comptime)
    pub fn contains(comptime str: []const u8, comptime substr: []const u8) bool {
        comptime {
            if (substr.len > str.len) return false;
            if (substr.len == 0) return true;
            
            var i: usize = 0;
            while (i <= str.len - substr.len) {
                var match = true;
                for (substr, 0..) |char, j| {
                    if (str[i + j] != char) {
                        match = false;
                        break;
                    }
                }
                if (match) return true;
                i += 1;
            }
            return false;
        }
    }
};

/// Compile-time initialization check
pub fn ensureInitialized(comptime T: type, comptime field: []const u8) void {
    comptime {
        assertHasField(T, field);
    }
}

// Run validation at compile time
comptime {
    validateSandboxConfig();
    validateResourceLimits();
    validateNetworkConfig();
}

